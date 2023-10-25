# YOLO3WrapperEx

YOLOv3モデルを使用した物体検出GenServerです。

## 動作環境
- Erlang 25 以降
- Elixir 1.14 以降
- wget
  - `download_model.sh` 内でモデルファイルのダウンロードに使用

## 準備
```sh
$ git clone https://github.com/b5g-ex/yolov3_wrapper_ex.git
$ cd yolov3_wrapper_ex
$ ./download_model.sh
$ mix deps.get
```

## 起動
```sh
# 全設定がデフォルト値の場合
$ ./start_node.sh

# 設定を変更する場合 (例: MODEL と USE_XLA を変更)
$ MODEL="416" USE_XLA="true" ./start_node.sh
```

## 設定 (環境変数)
| 項目 | 初期値 | 説明 |
| --- | --- | --- |
| NODE_NAME | "yolov3_wrapper_ex" | 起動する `node` の名前 |
| NODE_IPADDR | "127.0.0.1" | 起動する `node` のIPアドレス（`ifconfig` や `ip a` 等のコマンドで確認後入力してください） |
| COOKIE | "idkp" | COOKIEの値 |
| INET_DIST_LISTEN_MIN | "9100" | epmdが利用するノード間通信ポート |
| INET_DIST_LISTEN_MAX | "9155" | epmdが利用するノード間通信ポート |
| MY_PROCESS_NAME | ":yolov3_wrapper_ex" | 起動するGenServerの名前 |
| MODEL | "608" | 物体検出に使用するモデル (`tiny`, `320`, `416`, `608` : 右にいくほど精度は良いが処理が遅い) |
| USE_XLA | "false" | XLA (Accelerated Linear Algebra) の有効 / 無効設定 (`false`, `true` : 使用すると処理速度が速くなる : Raspberry Pi 4 Model B は非対応) |

## GenServer Callbacks
### handle_call
#### Request
- {:detect, binary}
- {:detect, binary: binary, model: model}
#### Response
- {processing_time, detected_data}
  - processing_time: integer
    - call を受けてから結果を返すまでの時間 (マイクロ秒)
  - detected_data: [Map]
    - "box" => [float, float, float, float]
      - 検出物の座標情報。(左, 上, 右, 下)
    - "class" => String
      - 検出物の分類。
    - "score" => float
      - 検出物の確度。


## 使い方
```elixir
iex> binary = File.read!("hoge.jpg")
iex> {processing_time, detected_data} = GenServer.call({:yolov3_wrapper_ex, :"yolov3_wrapper_ex@127.0.0.1"}, {:detect, binary}, 180000)
iex> detected_data
[
  %{
    "box" => [811.1929931640625, 50.926673889160156, 1271.2266845703125,
     713.273681640625],
    "class" => "person",
    "score" => 0.944570004940033
  },
  %{
    "box" => [368.71551513671875, 513.757080078125, 627.0322265625,
     719.4850463867188],
    "class" => "chair",
    "score" => 0.762179970741272
  }
]
```
