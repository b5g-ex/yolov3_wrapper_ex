import Config

config :yolov3_wrapper_ex,
  my_process_name: System.get_env("MY_PROCESS_NAME") |> Code.eval_string |> elem(0),
  model: System.get_env("MODEL", "608"),
  use_xla: System.get_env("USE_XLA", "false") |> Code.eval_string |> elem(0)
