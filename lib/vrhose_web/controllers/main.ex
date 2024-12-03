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
    |> json(timeline)
  end

  def fetch_delta(conn, %{"timestamp" => worldspace_timestamp_str}) do
    {worldspace_timestamp, ""} = Integer.parse(worldspace_timestamp_str, 10)

    # we need to convert from worldspace to serverspace
    # worldspace_timestamp = rem (realspace_timestamp |> DateTime.to_unix), 1000

    # note:
    # - only 1000 seconds resolution (thats fine for us)

    # basically utc now but ending in 000 lol
    base_timestamp = (((DateTime.utc_now() |> DateTime.to_unix()) / 1000) |> trunc) * 1000

    # add worldspace to get the second
    realspace_timestamp =
      base_timestamp + worldspace_timestamp

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
