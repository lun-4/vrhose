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

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    Logger.info("opening connection to #{@host}...")

    {:ok, pid} = VRHose.Websocket.connect(@jetstream)
    {:noreply, %{conn_pid: pid}}
  end

  def handle_info({:websocket_text, text}, state) do
    now = DateTime.utc_now()

    msg =
      text
      |> Jason.decode!()

    if msg["commit"]["record"]["$type"] != "app.bsky.feed.post" do
      Logger.debug("ignoring non-post record: #{inspect(msg)}")
    else
      post_text = msg["commit"]["record"]["text"]
      IO.puts("#{inspect(now)} -> #{post_text}")
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{conn_pid: conn_pid}) do
    VRHose.Websocket.close(conn_pid, 1000)
  end

  @impl true
  def terminate(reason, state) do
    Logger.error("terminating #{inspect(reason)} #{inspect(state)}")
  end
end
