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
    case Integer.parse(worldspace_timestamp_str, 10) do
      {worldspace_timestamp, ""} ->
        unless worldspace_timestamp < 0 do
          fetch_delta_validated(conn, worldspace_timestamp)
        else
          conn
          |> put_status(400)
          |> json(%{"error" => "Invalid negative timestamp: #{worldspace_timestamp_str}"})
        end

      _ ->
        conn
        |> put_status(400)
        |> json(%{"error" => "Invalid timestamp: #{worldspace_timestamp_str}"})
    end
  end

  def fetch_delta_validated(conn, worldspace_timestamp) do
    current_server_timestamp = DateTime.utc_now() |> DateTime.to_unix()

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
    |> json(timeline |> vrcjson_workaround)
  end
end
