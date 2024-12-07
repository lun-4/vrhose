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

  defmodule Metrics do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :vrhose_firehose_event_count,
        help: "fire hose...... wrow",
        labels: [:kind, :operation, :type]
      )
    end

    def commit(operation, type) do
      Counter.inc(
        name: :vrhose_firehose_event_count,
        labels: ["commit", to_string(operation), to_string(type)]
      )
    end

    def identity() do
      Counter.inc(
        name: :vrhose_firehose_event_count,
        labels: ["identity", "<unk>", "<unk>"]
      )
    end

    def account(active, status) do
      Counter.inc(
        name: :vrhose_firehose_event_count,
        labels: ["account", active, status]
      )
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("initializing ingestor")
    Process.send_after(self(), :print_stats, 1000)
    Process.send_after(self(), :ping_ws, 20000)

    zstd_ctx = :ezstd.create_decompression_context(8192)
    dd = :ezstd.create_ddict(File.read!(Path.join([:code.priv_dir(:vrhose), "/zstd_dictionary"])))
    :ezstd.select_ddict(zstd_ctx, dd)

    {:ok,
     %{
       subscribers: [],
       handles: %{},
       counter: 0,
       message_counter: 0,
       unfiltered_post_counter: 0,
       filtered_post_counter: 0,
       zero_counter: 0,
       conn_pid: nil,
       pong: true,
       zstd_ctx: zstd_ctx
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

  defp kill_websocket(state, reason) do
    ws_pid =
      Supervisor.which_children(VRHose.Supervisor)
      |> Enum.filter(fn {name, _, _, _} ->
        name == "websocket"
      end)
      |> Enum.at(0)
      |> then(fn {_, pid, _, _} -> pid end)

    Logger.warning(
      "killing #{inspect(ws_pid)} due to reason=#{inspect(reason)}.. ws should restart afterwards"
    )

    if ws_pid != :restarting do
      :erlang.exit(ws_pid, reason)
    end

    put_in(state.conn_pid, nil)
  end

  @impl true
  def handle_info({:ws_connected, pid}, state) do
    {:noreply, put_in(state.conn_pid, pid)}
  end

  @impl true
  def handle_info(:print_stats, state) do
    Logger.info(
      "#{DateTime.utc_now()} - message counter: #{state.message_counter}, unfiltered posts: #{state.unfiltered_post_counter}, filtered posts: #{state.filtered_post_counter}"
    )

    if state.zero_counter > 0 do
      Logger.warning("got zero messages for the #{state.zero_counter} time")
    end

    state =
      if state.zero_counter > 20 do
        Logger.error("must restart")
        kill_websocket(state, :zero_msgs)
      else
        state
      end

    Process.send_after(self(), :print_stats, 1000)

    zero_counter =
      if state.message_counter > 0 do
        0
      else
        state.zero_counter + 1
      end

    state = put_in(state.zero_counter, zero_counter)
    state = put_in(state.message_counter, 0)
    state = put_in(state.unfiltered_post_counter, 0)
    state = put_in(state.filtered_post_counter, 0)
    {:noreply, state}
  end

  @impl true
  def handle_info(:ping_ws, state) do
    Logger.info("#{DateTime.utc_now()} - pinging websocket")

    Process.send_after(self(), :check_websocket_pong, 10000)

    if state.conn_pid do
      Process.send_after(self(), :ping_ws, 20000)
      :ok = VRHose.Websocket.send_ping(state.conn_pid)
      {:noreply, put_in(state.pong, false)}
    else
      # restart the websocket immediately (its been 20sec)
      Logger.warning(
        "no connection available to ping, this should not happen, finding process to kill.."
      )

      state = kill_websocket(state, :no_pid)

      {:noreply, put_in(state.pong, true)}
    end
  end

  @impl true
  def handle_info({:websocket_binary, timestamp, compressed}, state) do
    decompressed = :ezstd.decompress_streaming(state.zstd_ctx, compressed)

    case decompressed do
      {:error, v} ->
        Logger.error("Decompression error: #{inspect(v)}")

        {:noreply, state}

      decompressed ->
        send(self(), {:websocket_text, timestamp, decompressed})
        {:noreply, state}
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
        case msg["commit"]["operation"] do
          "create" ->
            event_type = msg["commit"]["record"]["$type"]
            __MODULE__.Metrics.commit(:create, event_type)

            case event_type do
              "app.bsky.feed.post" ->
                state = put_in(state.unfiltered_post_counter, state.unfiltered_post_counter + 1)
                state = fanout_post(state, timestamp, msg)
                {:noreply, state}

              "app.bsky.feed.like" ->
                fanout(state, :like)
                {:noreply, state}

              "app.bsky.graph.follow" ->
                fanout(state, :follow)
                {:noreply, state}

              "app.bsky.graph.block" ->
                fanout(state, :block)
                {:noreply, state}

              "app.bsky.feed.repost" ->
                fanout(state, :repost)
                {:noreply, state}

              "app.bsky.actor.profile" ->
                fanout(state, :signup)
                {:noreply, state}
            end

          "delete" ->
            event_type = msg["commit"]["collection"]
            __MODULE__.Metrics.commit(:delete, event_type)
            {:noreply, state}

          "update" ->
            event_type = msg["commit"]["record"]["$type"]
            __MODULE__.Metrics.commit(:update, event_type)
            {:noreply, state}

          v ->
            Logger.warning("Unsupported commit type: #{inspect(v)} from #{inspect(msg)}")
            {:noreply, state}
        end

      "identity" ->
        __MODULE__.Metrics.identity()
        did = msg["identity"]["did"]
        handle = msg["identity"]["handle"]
        {:noreply, put_in(state.handles, Map.put(state.handles, did, handle))}

      "account" ->
        active? = msg["account"]["active"]
        status = msg["account"]["status"]

        __MODULE__.Metrics.account(
          if active? do
            "active"
          else
            "inactive"
          end,
          status
        )

        {:noreply, state}

      v ->
        Logger.warning("Unsupported message from jetstream: #{inspect(v)}: #{inspect(msg)}")
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
      state = kill_websocket(state, :timeout_ping)
      {:noreply, put_in(state.pong, true)}
    end
  end

  defp maybe_reply_flag(rec) do
    if rec["reply"] != nil do
      ["r"]
    else
      []
    end
  end

  defp maybe_quote_flag(rec) do
    has_bsky_link_facet? =
      Enum.any?(
        (rec["facets"] || [])
        |> Enum.filter(fn facet ->
          facet["features"]
          |> Enum.filter(fn feature ->
            is_link = feature["$type"] == "app.bsky.richtext.facet#link"
            is_bsky = String.starts_with?(feature["uri"] || "", "https://bsky.app")
            is_link and is_bsky
          end)
          |> Enum.any?()
        end)
      )

    has_post_embed? =
      (rec["embed"] || %{})["$type"] == "app.bsky.embed.record" and
        String.contains?(((rec["embed"] || %{})["record"] || %{})["uri"], "app.bsky.feed.post")

    if has_bsky_link_facet? || has_post_embed? do
      ["q"]
    else
      []
    end
  end

  defp maybe_mention_flag(rec) do
    unless Enum.empty?(
             (rec["facets"] || [])
             |> Enum.filter(fn facet ->
               facet["features"]
               |> Enum.filter(fn feature ->
                 is_mention = feature["$type"] == "app.bsky.richtext.facet#mention"
                 has_did = feature["did"] != nil
                 is_mention and has_did
               end)
               |> Enum.any?()
             end)
           ) do
      ["m"]
    else
      []
    end
  end

  @media_embed_types [
    "app.bsky.embed.images",
    "app.bsky.embed.video"
  ]

  defp maybe_media_flag(rec) do
    maybe_embed = rec["embed"] || %{}
    embed_type = maybe_embed["$type"]

    if embed_type in @media_embed_types do
      ["M"]
    else
      []
    end
  end

  # test posts:
  # https://pdsls.dev/at/did:plc:iw5dbzqr3hbt4qrsqv5bsv2n/app.bsky.feed.post/3lbwdzpzu722e
  # https://pdsls.dev/at/did:plc:ghmhveudel6es5chzycsi2hi/app.bsky.feed.post/3lb2ed5bl7222
  @wrld_id_regex ~r/wrld_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

  defp is_vrchat_feature(feature) do
    maybe_uri = feature["uri"] || ""

    feature["$type"] == "app.bsky.richtext.facet#link" and
      (String.starts_with?(maybe_uri, "https://vrchat.com/home/world/wrld_") or
         String.starts_with?(maybe_uri, "https://vrchat.com/home/launch?worldId=wrld_"))
  end

  defp extract_world_id(rec) do
    first_wrld_link =
      (rec["facets"] || [])
      |> Enum.filter(fn facet ->
        facet["features"]
        |> Enum.filter(&is_vrchat_feature/1)
        |> Enum.any?()
      end)
      |> Enum.at(0)
      |> then(fn
        nil ->
          nil

        facet ->
          feature =
            facet["features"]
            |> Enum.filter(&is_vrchat_feature/1)
            |> Enum.at(0)

          feature["uri"]
      end)

    if first_wrld_link == nil do
      # fallback to post text, maybe they posted the wrld id directly
      @wrld_id_regex
      |> Regex.run(rec["text"] || "")
      |> then(fn
        nil -> []
        v -> v
      end)
      |> Enum.at(0)
    else
      # regex so it extracts wrld_ id (could do String.trim too if im up for optimizing lol)
      @wrld_id_regex
      |> Regex.run(first_wrld_link)
      |> then(fn
        nil ->
          Logger.error("no wrld id found in first wrld link: #{inspect(first_wrld_link)}")

        v ->
          v
          |> Enum.at(0)
      end)
    end
  end

  @wordfilter [
    "nsfw",
    "cock",
    "dick",
    "penis",
    "nude",
    "findom",
    "pussy",
    "porn",
    "2dfd",
    "onlyfans",
    "fansly",
    "bbw",
    "paypig"
  ]
  defp run_filters(post) do
    text = post["text"] || ""

    # TODO better filter chain (regex)
    @wordfilter
    |> Enum.map(fn word ->
      text
      |> String.downcase()
      |> String.contains?(word)
    end)
    |> Enum.any?()
  end

  defp fanout_post(state, timestamp, msg) do
    post = msg["commit"]["record"]
    filtered? = run_filters(post)

    unless filtered? do
      fanout_filtered_post(state, timestamp, msg)
      state
    else
      put_in(state.filtered_post_counter, state.filtered_post_counter + 1)
    end
  end

  def post_flags_for(post_record) do
    (maybe_reply_flag(post_record) ++
       maybe_quote_flag(post_record) ++
       maybe_mention_flag(post_record) ++
       maybe_media_flag(post_record))
    |> Enum.join("")
  end

  defp fanout_filtered_post(state, timestamp, msg) do
    post_record = msg["commit"]["record"]
    # IO.puts("#{inspect(timestamp)} -> #{post_text}")

    text = post_record["text"]

    post_flags = post_flags_for(post_record)

    post_data = %{
      timestamp: (timestamp |> DateTime.to_unix(:millisecond)) / 1000,
      text: text,
      languages: (post_record["langs"] || []) |> Enum.at(0) || "",
      author_name: "<...processing...>",
      author_handle: Map.get(state.handles, msg["did"]) || msg["did"],
      author_did: msg["did"],
      hash: :erlang.phash2(text <> msg["did"]),
      flags: post_flags,
      world_id: extract_world_id(post_record),
      micro_id: msg["commit"]["rkey"]
    }

    {:ok, worker} = ExHashRing.Ring.find_node(VRHose.Hydrator.Ring, msg["did"])
    worker_pid = worker |> to_charlist() |> :erlang.list_to_pid()
    VRHose.Hydrator.submit_post(worker_pid, {msg["did"], post_data, state.subscribers})
  end

  defp fanout(state, anything) do
    state.subscribers
    |> Enum.each(fn pid ->
      send(pid, anything)
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
