defmodule VRHoseWeb.MainController do
  use VRHoseWeb, :controller

  def hi(conn, _) do
    conn
    |> json(%{message: "Hello World!"})
  end
end
