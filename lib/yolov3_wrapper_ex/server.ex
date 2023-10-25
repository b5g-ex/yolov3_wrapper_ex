defmodule Yolov3WrapperEx.Server do
  use GenServer
  import Nx.Defn

  # COCOデータセットのクラス名を取得。
  # 今回使うモデルはCOCOデータセットを学習しているため。
  @labels File.stream!("coco.names") |> Enum.map(&String.trim/1)

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: Application.fetch_env!(:yolov3_wrapper_ex, :my_process_name))
  end

  def init(initial_state) do
    {:ok, initial_state}
  end

  def handle_call(:detect, _from, state) do
    {:reply, :detect, state}
  end

  def handle_call({:detect, binary: binary, model: model, use_xla: use_xla}, _from, state) do
    {:reply, :timer.tc(__MODULE__, :detect, [binary, model, use_xla]), state}
  end

  def handle_call({:detect, binary: binary, model: model}, _from, state) do
    {:reply, :timer.tc(__MODULE__, :detect, [binary, model]), state}
  end

  def handle_call({:detect, binary}, _from, state) do
    {:reply, :timer.tc(__MODULE__, :detect, [binary]), state}
  end

  def detect(binary) do
    detect(binary, Application.fetch_env!(:yolov3_wrapper_ex, :model))
  end

  def detect(binary, model) do
    detect(binary, model, Application.fetch_env!(:yolov3_wrapper_ex, :use_xla))
  end

  def detect(binary, model, use_xla) do
    detect(binary, model, use_xla, 0.6)
  end

  def detect(binary, model, use_xla, score_threshold) do
    image_data = load_image(binary)

    predict(image_data, model, use_xla)
    |> filter_predictions(score_threshold)
    |> form_objects(image_data, score_threshold)
    |> format_objects()
  end

  defp load_image(binary) do
    image = Evision.imdecode(binary, Evision.Constant.cv_IMREAD_COLOR())
    {height, width, _} = Evision.Mat.shape(image)
    {image, width, height}
  end

  defp predict({image, _width, _height}, model, use_xla) do
    # モデルの読み込み。
    net = read_network_model(model)

    # 出力層の名前を取得。推論実行時に使用。
    out_names = Evision.DNN.Net.getUnconnectedOutLayersNames(net)

    # 画像を推論用の形式に変換。
    img_blob = blob_from_image(image, model)

    # 推論を実行。
    # 推論結果を Evision の行列形式から、Nx のテンソル形式に変換。
    net
    |> Evision.DNN.Net.setInput(img_blob, name: "", scalefactor: 1 / 255, mean: {0, 0, 0})
    |> Evision.DNN.Net.forward(outBlobNames: out_names)
    |> Enum.map(fn prediction ->
      mat_to_nx(prediction, use_xla)
    end)
    |> Nx.concatenate()
  end

  defp read_network_model("tiny"), do: _read_network_model("yolov3-tiny.cfg", "yolov3-tiny.weights")
  defp read_network_model(_model), do: _read_network_model("yolov3.cfg", "yolov3.weights")
  defp _read_network_model(cfg_file_name, weights_file_name) do
    Evision.DNN.readNetFromDarknet("./models/#{cfg_file_name}", darknetModel: "./models/#{weights_file_name}")
  end

  defp blob_from_image(image, "320"), do: _blob_from_image(image, {320, 320})
  defp blob_from_image(image, model) when model in ["416", "tiny"], do: _blob_from_image(image, {416, 416})
  defp blob_from_image(image, _model), do: _blob_from_image(image, {608, 608})
  defp _blob_from_image(image, size) do
    # OpenCV で読み込んだ場合、色空間が BGR になっているので、 RGB に変換するため swapRB を true にする。
    # リサイズ時に画像の一部を切り捨てないよう crop は false にする。
    Evision.DNN.blobFromImage(image, size: size, swapRB: true, crop: false)
  end

  defp mat_to_nx(mat, true), do: _mat_to_nx(mat, EXLA.Backend)
  defp mat_to_nx(mat, _use_xla), do: _mat_to_nx(mat, Nx.BinaryBackend)
  defp _mat_to_nx(mat, backend), do: Evision.Mat.to_nx(mat, backend)

  defp filter_predictions(predictions, score_threshold) do
    {_, score} = extract_top_class_index_and_score(predictions)

    # スコアのうち何番目のものが閾値を超えているか取得する。
    # 閾値を超えていれば1、閾値以下なら0にする。
    greater = Nx.greater(score, score_threshold)

    # 閾値を超えているスコアの数を取得。
    greater_count = Nx.sum(greater) |> Nx.to_number()

    case greater_count do
      0 ->
        nil

      _ ->
        # 降順でソートし、元のテンソルの対応するインデックスを取得。
        greater_indices = Nx.argsort(greater, direction: :desc)[[0..(greater_count - 1)]]

        # 閾値を超えた領域だけを抽出。
        Nx.take(predictions, greater_indices, axis: 0)
    end
  end

  defp form_objects(nil, _, _), do: nil

  defp form_objects(predictions, {_image, width, height}, score_threshold) do
    coordinates = extract_coordinates(predictions)
    formatted_coordinates = format_coordinates(coordinates, width, height)

    {top_class_index, score} = extract_top_class_index_and_score(predictions)

    nms_threshold = 0.7

    nms(
      formatted_coordinates,
      top_class_index,
      score,
      score_threshold,
      nms_threshold
    )
  end

  defp extract_coordinates(predictions) do
    predictions[[0..-1//1, 0..3]]
  end

  defp nms(
         formatted_coordinates,
         class_index,
         score,
         score_threshold,
         nms_threshold
       ) do
    score_list = Nx.to_list(score)

    selected_indices =
      formatted_coordinates
      |> Evision.DNN.nmsBoxes(score_list, score_threshold, nms_threshold)

    case selected_indices do
      [] ->
        nil

      _ ->
        selected_indices_tensor = Nx.tensor(selected_indices)

        selected_bboxes =
          formatted_coordinates
          |> Nx.take(selected_indices_tensor)

        selected_classes =
          class_index
          |> Nx.take(selected_indices_tensor)
          |> Nx.new_axis(1)

        selected_scores =
          score
          |> Nx.take(selected_indices_tensor)
          |> Nx.new_axis(1)

        [selected_bboxes, selected_classes, selected_scores]
        |> Nx.concatenate(axis: 1)
    end
  end

  defp format_objects(nil), do: []

  defp format_objects(formed_objects) do
    formed_objects
    |> Nx.to_list()
    |> Enum.map(&format_object(&1, @labels))
  end

  defp format_object([left, top, right, bottom, class_index, score], labels) do
    %{
      "box" => [left, top, right, bottom],
      "class" => Enum.at(labels, trunc(class_index)),
      "score" => score
    }
  end

  defn extract_top_class_index_and_score(predictions) do
    # 各領域の座標のスコアを取り出す。
    bbox_score = predictions[[0..-1//1, 4]]

    # 各領域のクラス毎のスコアを取得。
    all_class_score = predictions[[0..-1//1, 5..-1//1]]

    top_class_index = Nx.argmax(all_class_score, axis: 1)

    # 各領域のトップのクラススコアを取得。
    top_class_score = Nx.reduce_max(all_class_score, axes: [1])

    # 座標スコアとクラススコアを掛けて、最終的なスコアを計算。
    score = bbox_score * top_class_score

    {top_class_index, score}
  end

  defn format_coordinates(coordinates, img_width, img_height) do
    bbox_half_width = coordinates[[0..-1//1, 2]] / 2
    bbox_half_height = coordinates[[0..-1//1, 3]] / 2

    min_x = (coordinates[[0..-1//1, 0]] - bbox_half_width) * img_width
    min_y = (coordinates[[0..-1//1, 1]] - bbox_half_height) * img_height
    max_x = (coordinates[[0..-1//1, 0]] + bbox_half_width) * img_width
    max_y = (coordinates[[0..-1//1, 1]] + bbox_half_height) * img_height

    [min_x, min_y, max_x, max_y]
    |> Nx.stack()
    |> Nx.transpose()
  end
end
