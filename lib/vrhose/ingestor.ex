defmodule VRHose.Ingestor do
  use GenServer
  require Logger

  # @host "jetstream2.us-west.bsky.network"
  # @path "/subscribe"

  @jetstream "wss://jetstream2.us-west.bsky.network/subscribe?wantedCollections=app.bsky.feed.post"
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
    {:ok,
     %{
       subscribers: [],
       handles: %{},
       conn_pid: nil
     }, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    Logger.info("opening connection to #{@jetstream}...")

    {:ok, pid} = VRHose.Websocket.connect(@jetstream)
    {:noreply, put_in(state.conn_pid, pid)}
  end

  @impl true
  def handle_call(:subscribe, {pid, _}, state) do
    {:reply, :ok, put_in(state.subscribers, state.subscribers ++ [pid])}
  end

  @impl true
  def handle_info({:websocket_text, timestamp, text}, state) do
    msg =
      text
      |> Jason.decode!()

    case msg["kind"] do
      "commit" ->
        case msg["commit"]["record"]["$type"] do
          "app.bsky.feed.post" ->
            fanout_post(state, timestamp, msg)
            {:noreply, state}

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

  defp fanout_post(state, timestamp, msg) do
    post_record = msg["commit"]["record"]
    # IO.puts("#{inspect(timestamp)} -> #{post_text}")

    post_data = %{
      timestamp: timestamp |> DateTime.to_unix(),
      text: post_record["text"],
      author_handle: Map.get(state.handles, post_record["did"]) || "unknown atm"
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
  def terminate(_reason, %{conn_pid: conn_pid}) do
    VRHose.Websocket.close(conn_pid, 1000, "uwaa")
  end

  @impl true
  def terminate(reason, state) do
    Logger.error("terminating #{inspect(reason)} #{inspect(state)}")
  end
end
