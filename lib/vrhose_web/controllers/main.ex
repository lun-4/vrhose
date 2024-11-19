defmodule VRHoseWeb.MainController do
  use VRHoseWeb, :controller
  # vrcjson does not support unbalanced braces inside strings
  # this has been reported to vrchat already
  #
  # https://feedback.vrchat.com/vrchat-udon-closed-alpha-bugs/p/braces-inside-strings-in-vrcjson-can-fail-to-deserialize
  #
  # workaround for now is to strip off any brace character. we could write a balancer and strip
  # off the edge case, but i dont think i care enough to do that just for vrchat.
  # taken from YTS/yt_search

  def vrcjson_workaround(incoming_data, opts \\ []) do
    ignore_keys = Keyword.get(opts || [], :ignore_keys, [])

    case incoming_data do
      data when is_bitstring(data) ->
        data
        |> String.replace(~r/[\[\]{}]/, "")
        |> String.trim(" ")

      data when is_map(data) ->
        data
        |> Map.to_list()
        |> Enum.map(fn {key, value} ->
          if key in ignore_keys do
            {key, value}
          else
            {key, value |> vrcjson_workaround(opts)}
          end
        end)
        |> Map.new()

      data when is_list(data) ->
        data
        |> Enum.map(fn x -> vrcjson_workaround(x, opts) end)

      v when is_boolean(v) ->
        v

      nil ->
        nil

      v when is_atom(v) ->
        raise "Unsupported type #{inspect(v)}"

      v when is_tuple(v) ->
        raise "Unsupported type #{inspect(v)}"

      v ->
        v
    end
  end

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
    |> json(timeline |> vrcjson_workaround)
  end
end
