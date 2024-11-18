defmodule VRHose.Websocket do
  use GenServer

  require Logger
  require Mint.HTTP

  defstruct [
    :conn,
    :websocket,
    :request_ref,
    :caller,
    :caller_pid,
    :status,
    :resp_headers,
    :closing?
  ]

  def start_and_connect(opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, opts)
    url = opts |> Keyword.get(:url)
    send_to = opts |> Keyword.get(:send_to)
    {:ok, :connected} = GenServer.call(pid, {:connect, url, send_to})
    {:ok, pid}
  end

  def connect(url) do
    with {:ok, socket} <- GenServer.start_link(__MODULE__, []),
         {:ok, :connected} <- GenServer.call(socket, {:connect, url, self()}) do
      {:ok, socket}
    end
  end

  def send_message(pid, text) do
    GenServer.call(pid, {:send_text, text})
  end

  def send_ping(pid) do
    GenServer.call(pid, :ping)
  end

  def close(pid, code, reason) do
    GenServer.call(pid, {:close, code, reason})
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call({:send_text, text}, _from, state) do
    {:ok, state} = send_frame(state, {:text, text})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:ping, _from, state) do
    with {:ok, state} <- send_frame(state, {:ping, "ping!"}) do
      {:reply, :ok, state}
    else
      v ->
        {:reply, {:error, v}, state}
    end
  end

  @impl GenServer
  def handle_call({:close, code, reason}, _from, state) do
    _ = send_frame(state, {:close, code, reason})
    Mint.HTTP.close(state.conn)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:connect, url, caller_pid}, from, state) do
    Logger.info("connecting to #{url}")
    uri = URI.parse(url)

    http_scheme =
      case uri.scheme do
        "ws" -> :http
        "wss" -> :https
      end

    ws_scheme =
      case uri.scheme do
        "ws" -> :ws
        "wss" -> :wss
      end

    path =
      case uri.query do
        nil -> uri.path
        query -> uri.path <> "?" <> query
      end

    with {:ok, conn} <- Mint.HTTP1.connect(http_scheme, uri.host, uri.port),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, path, []) do
      state = %{state | conn: conn, request_ref: ref, caller: from, caller_pid: caller_pid}
      Logger.info("connected to #{url}!")
      send(caller_pid, {:ws_connected, self()})
      {:noreply, state}
    else
      {:error, reason} ->
        Logger.error("failed to connect, #{inspect(reason)}")
        {:reply, {:error, reason}, state}

      {:error, conn, reason} ->
        Logger.error("failed to connect, #{inspect(conn)}, #{inspect(reason)}")
        {:reply, {:error, reason}, put_in(state.conn, conn)}
    end
  end

  @impl GenServer
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = put_in(state.conn, conn) |> handle_responses(responses)
        if state.closing?, do: do_close(state), else: {:noreply, state}

      {:error, conn, reason, _responses} ->
        state = put_in(state.conn, conn) |> reply({:error, reason})
        {:noreply, state}

      :unknown ->
        {:noreply, state}
    end
  end

  defp handle_responses(state, responses)

  defp handle_responses(%{request_ref: ref} = state, [{:status, ref, status} | rest]) do
    put_in(state.status, status)
    |> handle_responses(rest)
  end

  defp handle_responses(%{request_ref: ref} = state, [{:headers, ref, resp_headers} | rest]) do
    put_in(state.resp_headers, resp_headers)
    |> handle_responses(rest)
  end

  defp handle_responses(%{request_ref: ref} = state, [{:done, ref} | rest]) do
    case Mint.WebSocket.new(state.conn, ref, state.status, state.resp_headers) do
      {:ok, conn, websocket} ->
        %{state | conn: conn, websocket: websocket, status: nil, resp_headers: nil}
        |> reply({:ok, :connected})
        |> handle_responses(rest)

      {:error, conn, reason} ->
        put_in(state.conn, conn)
        |> reply({:error, reason})
    end
  end

  defp handle_responses(%{request_ref: ref, websocket: websocket} = state, [
         {:data, ref, data} | rest
       ])
       when websocket != nil do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} ->
        put_in(state.websocket, websocket)
        |> handle_frames(frames)
        |> handle_responses(rest)

      {:error, websocket, reason} ->
        put_in(state.websocket, websocket)
        |> reply({:error, reason})
    end
  end

  defp handle_responses(state, [_response | rest]) do
    handle_responses(state, rest)
  end

  defp handle_responses(state, []), do: state

  defp send_frame(state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, frame),
         state = put_in(state.websocket, websocket),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.request_ref, data) do
      {:ok, put_in(state.conn, conn)}
    else
      {:error, %Mint.WebSocket{} = websocket, reason} ->
        {:error, put_in(state.websocket, websocket), reason}

      {:error, conn, reason} ->
        {:error, put_in(state.conn, conn), reason}
    end
  end

  def handle_frames(state, frames) do
    Enum.reduce(frames, state, fn
      # reply to pings with pongs
      {:ping, data}, state ->
        {:ok, state} = send_frame(state, {:pong, data})
        state

      {:pong, data}, state ->
        send(state.caller_pid, {:websocket_pong, data})
        state

      {:close, _code, reason}, state ->
        Logger.debug("Closing connection: #{inspect(reason)}")
        %{state | closing?: true}

      {:text, text}, state ->
        timestamp = DateTime.utc_now()
        send(state.caller_pid, {:websocket_text, timestamp, text})
        state

      frame, state ->
        Logger.warning("Unexpected frame received: #{inspect(frame)}")
        state
    end)
  end

  defp do_close(state) do
    # Streaming a close frame may fail if the server has already closed
    # for writing.
    Logger.info("closing #{inspect(state)}")
    _ = send_frame(state, {:close, 1000, nil})
    Mint.HTTP.close(state.conn)
    {:stop, :normal, state}
  end

  defp reply(state, response) do
    if state.caller, do: GenServer.reply(state.caller, response)
    put_in(state.caller, nil)
  end
end
