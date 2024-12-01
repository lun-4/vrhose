defmodule VRHose.Data do
  def generate_unix_timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
  end
end
