defmodule VRHoseWeb.MainController do
  use VRHoseWeb, :controller

  def hi(conn, _) do
    {:ok, timeline} =
      Registry.lookup(Registry.Timeliners, "timeliner")
      |> Enum.random()
      |> then(fn {pid, _} ->
        VRHose.Timeliner.fetch_all(pid)
      end)

    conn
    |> json(timeline |> vrcjson_workaround)
  end

  def fetch_delta(conn, %{"timestamp" => worldspace_timestamp_str}) do
    current_server_timestamp = DateTime.utc_now() |> DateTime.to_unix()
    {worldspace_timestamp, ""} = Integer.parse(worldspace_timestamp_str, 10)

    # we need to convert from worldspace to serverspace
    # worldspace_timestamp = rem (realspace_timestamp |> DateTime.to_unix), 1000

    # note:
    # - only 1000 seconds resolution (thats fine for us)

    # basically utc now but ending in 000 lol
    base_timestamp = ((current_server_timestamp / 1000) |> trunc) * 1000

    server_delta_in_worldspace = current_server_timestamp - base_timestamp

    realspace_timestamp =
      if server_delta_in_worldspace < 100 and worldspace_timestamp > 900 do
        # use base_timestamp from previous cycle
        base_timestamp - 1000 + worldspace_timestamp
      else
        base_timestamp + worldspace_timestamp
      end

    {:ok, timeline} =
      Registry.lookup(Registry.Timeliners, "timeliner")
      |> Enum.random()
      |> then(fn {pid, _} ->
        VRHose.Timeliner.fetch(pid, realspace_timestamp)
      end)

    conn
    |> json(timeline)
  end
end
