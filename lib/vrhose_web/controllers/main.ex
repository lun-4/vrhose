defmodule VRHoseWeb.MainController do
  use VRHoseWeb, :controller

  def hi(conn, _) do
    timeline =
      Registry.lookup(Registry.Timeliners, "timeliner")
      |> Enum.random()
      |> then(fn {pid, _} ->
        VRHose.Timeliner.fetch(pid)
      end)

    conn
    |> json(%{
      batch: timeline
    })
  end
end
