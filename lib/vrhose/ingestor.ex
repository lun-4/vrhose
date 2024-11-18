defmodule VRHose.Ingestor do
  use GenServer
  require Logger

  # @host "jetstream2.us-west.bsky.network"
  # @path "/subscribe"

  # @jetstream "wss://jetstream2.us-west.bsky.network/subscribe?wantedCollections=app.bsky.feed.post"
  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe(ingestor) do
    GenServer.call(ingestor, :subscribe)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("initializing ingestor")
    Process.send_after(self(), :print_stats, 1000)
    Process.send_after(self(), :ping_ws, 20000)

    {:ok,
     %{
       subscribers: [],
       handles: %{},
       counter: 0,
       message_counter: 0,
       conn_pid: nil,
       pong: true
     }, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    # Logger.info("opening connection to #{@jetstream}...")

    # {:ok, pid} = VRHose.Websocket.connect(@jetstream)
    # {:noreply, put_in(state.conn_pid, pid)}
    {:noreply, state}
  end

  @impl true
  def handle_call(:subscribe, {pid, _}, state) do
    {:reply, :ok, put_in(state.subscribers, state.subscribers ++ [pid])}
  end

  @impl true
  def handle_info({:ws_connected, pid}, state) do
    {:noreply, put_in(state.conn_pid, pid)}
  end

  @impl true
  def handle_info(:print_stats, state) do
    Logger.info("#{DateTime.utc_now()} - message counter: #{state.message_counter}")
    Process.send_after(self(), :print_stats, 1000)
    {:noreply, put_in(state.message_counter, 0)}
  end

  @impl true
  def handle_info(:ping_ws, state) do
    Logger.info("#{DateTime.utc_now()} - pinging websocket")

    if state.conn_pid do
      Process.send_after(self(), :ping_ws, 20000)
      Process.send_after(self(), :check_websocket_pong, 10000)
      :ok = VRHose.Websocket.send_ping(state.conn_pid)
      {:noreply, put_in(state.pong, false)}
    else
      # restart the websocket immediately (its been 20sec)
      Logger.warning(
        "no connection available to ping, this should not happen, finding process to kill.."
      )

      ws_pid =
        Supervisor.which_children(VRHose.Supervisor)
        |> Enum.filter(fn {name, _, _, _} ->
          name == "websocket"
        end)
        |> Enum.at(0)
        |> then(fn {_, pid, _, _} -> pid end)

      Logger.warning("killing #{inspect(ws_pid)}.. ws should restart afterwards")
      :erlang.exit(ws_pid, :no_connection)

      {:noreply, put_in(state.pong, true)}
    end
  end

  @impl true
  def handle_info({:websocket_text, timestamp, text}, state) do
    msg =
      text
      |> Jason.decode!()

    state = put_in(state.message_counter, state.message_counter + 1)

    case msg["kind"] do
      "commit" ->
        case msg["commit"]["record"]["$type"] do
          "app.bsky.feed.post" ->
            fanout_post(state, timestamp, msg)
            {:noreply, put_in(state.counter, state.counter + 1)}

          _ ->
            # simply ignore non-posts lol
            {:noreply, state}
        end

      "identity" ->
        did = msg["identity"]["did"]
        handle = msg["identity"]["handle"]
        {:noreply, put_in(state.handles, Map.put(state.handles, did, handle))}

      _ ->
        # simply ignore non-commits lol
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:websocket_pong, _data}, state) do
    Logger.info("pong")
    {:noreply, put_in(state.pong, true)}
  end

  @impl true
  def handle_info(:check_websocket_pong, state) do
    if state.pong do
      {:noreply, put_in(state.pong, true)}
    else
      Logger.warning("no pong... killing the connection")
      :erlang.exit(state.conn_pid, :timeout_ping)
      {:noreply, put_in(state.pong, true)}
    end
  end

  defp fanout_post(state, timestamp, msg) do
    post_record = msg["commit"]["record"]
    # IO.puts("#{inspect(timestamp)} -> #{post_text}")

    text = post_record["text"]

    post_data = %{
      timestamp: (timestamp |> DateTime.to_unix(:millisecond)) / 1000,
      text: text,
      languages: (post_record["langs"] || []) |> Enum.at(0) || "",
      author_handle: Map.get(state.handles, msg["did"]) || msg["did"],
      hash: :erlang.phash2(text)
    }

    state.subscribers
    |> Enum.each(fn pid ->
      send(
        pid,
        {:post, post_data}
      )
    end)
  end

  @impl true
  def terminate(reason, state) do
    if state.conn_pid != nil do
      VRHose.Websocket.close(state.conn_pid, 1000, "uwaa")
    end

    Logger.error("terminating #{inspect(reason)} #{inspect(state)}")
  end
end
