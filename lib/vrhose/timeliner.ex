defmodule VRHose.Timeliner do
  use GenServer
  require Logger
  @worlds_in_timeline 10

  defmodule Counters do
    defstruct posts: 0,
              likes: 0,
              reposts: 0,
              follows: 0,
              blocks: 0,
              signups: 0
  end

  def start_link(opts \\ []) do
    IO.inspect(opts)
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def fetch_all(pid) do
    now = DateTime.utc_now() |> DateTime.to_unix(:second)
    GenServer.call(pid, {:fetch, now - 30, false})
  end

  def fetch(pid, timestamp) do
    GenServer.call(pid, {:fetch, timestamp, true})
  end

  defmodule Metrics do
    use Prometheus.Metric

    def setup() do
      Histogram.declare(
        name: :vrhose_timeliner_events,
        help: "sent posts from timeliner processes to users",
        labels: [:call_type],
        buckets:
          [
            10..100//10,
            100..1000//100,
            1000..2000//100,
            2000..4000//500,
            4000..10000//1000,
            10000..20000//1500,
            20000..40000//2000
          ]
          |> Enum.flat_map(&Enum.to_list/1)
          |> Enum.uniq()
      )
    end

    def sent_events(call_type, amount) do
      Histogram.observe(
        [
          name: :vrhose_timeliner_events,
          labels: [call_type]
        ],
        amount
      )
    end
  end

  @impl true
  def init(opts) do
    Registry.register(Registry.Timeliners, "timeliner", :awoo)

    register_with =
      opts
      |> Keyword.get(:register_with)

    worker_id =
      opts
      |> Keyword.get(:worker_id)

    ingestor_pid = GenServer.whereis(register_with)
    monitor_ref = Process.monitor(ingestor_pid)
    :ok = VRHose.Ingestor.subscribe(register_with)
    handle = VRHose.TimelinerStorage.create()

    Process.send_after(self(), :compute_rates, 1000)

    worlds = VRHose.World.last_worlds(@worlds_in_timeline)

    resolved_worlds =
      worlds
      |> Enum.map(fn world ->
        identity = VRHose.Identity.one(world.poster_did)

        if identity == nil do
          %{
            id: world.vrchat_id,
            author_handle: "@" <> world.poster_did,
            author_name: "<unknown>"
          }
        else
          %{
            id: world.vrchat_id,
            author_handle: "@" <> identity.also_known_as,
            author_name: identity.name
          }
        end
      end)
      |> Enum.reverse()

    {:ok,
     %{
       registered_with: register_with,
       worker_id: worker_id,
       storage: handle,
       debug_counters: %__MODULE__.Counters{},
       start_time: System.os_time(:second),
       counters: %__MODULE__.Counters{},
       rates: [],
       monitor_ref: monitor_ref,
       world_ids: %{
         time: System.os_time(:millisecond) / 1000,
         ids: resolved_worlds
       }
     }}
  end

  @impl true
  def handle_continue(:reconnect, state) do
    register_with = state.registered_with
    Logger.info("#{state.worker_id}: reconnecting to #{inspect(register_with)}")
    ingestor_pid = GenServer.whereis(register_with)
    monitor_ref = Process.monitor(ingestor_pid)
    :ok = VRHose.Ingestor.subscribe(register_with)
    {:noreply, put_in(state.monitor_ref, monitor_ref)}
  end

  defp persist_world(world_id, author_did) do
    case VRHose.QuickLeader.acquire() do
      :leader ->
        {:ok, _} = VRHose.World.insert(world_id, author_did)
        :ok

      :not_leader ->
        :ok
    end
  end

  # last 120 seconds worth of counters
  @rate_max_storage 120

  @impl true
  def handle_info(:compute_rates, state) do
    state =
      put_in(
        state.rates,
        if length(state.rates) >= @rate_max_storage do
          state.rates
          |> Enum.drop(-1)
          |> List.insert_at(0, state.counters)
        else
          state.rates
          |> List.insert_at(0, state.counters)
        end
      )

    if state.storage == 0 do
      Logger.info("counters: #{inspect(state.counters)}")
    end

    state = put_in(state.counters, %__MODULE__.Counters{})
    Process.send_after(self(), :compute_rates, 1000)
    {:noreply, state}
  end

  @impl true
  def handle_info({:post, post}, state) do
    state =
      if post.world_id != nil do
        world_ids = state.world_ids.ids |> Enum.map(fn wrld -> wrld.id end)
        IO.inspect(world_ids, label: "world_ids from #{state.storage}")

        put_in(state.world_ids, %{
          time: System.os_time(:millisecond) / 1000,
          ids:
            unless Enum.member?(world_ids, post.world_id) do
              # one of the timeliners must become a leader so it can send this
              # world id to the database
              :ok = persist_world(post.world_id, post.author_did)

              wrld = %{
                id: post.world_id,
                author_handle: post.author_handle,
                author_name: post.author_name
              }

              if length(state.world_ids.ids) > @worlds_in_timeline do
                state.world_ids.ids
                # pop oldest
                |> Enum.drop(1)
                # insert into earliest
                |> List.insert_at(-1, wrld)
              else
                # append
                state.world_ids.ids
                |> List.insert_at(-1, wrld)
              end
              |> IO.inspect(label: "AFTER world_ids from #{state.storage}")
            else
              IO.puts("already a wrld id, not inserting #{state.storage}")
              state.world_ids.ids
            end
        })
      else
        state
      end

    VRHose.TimelinerStorage.insert_post(state.storage, post)

    state =
      put_in(state.counters, %{state.counters | posts: state.counters.posts + 1})

    state =
      put_in(state.debug_counters, %{state.debug_counters | posts: state.debug_counters.posts + 1})

    {:noreply, state}
  end

  @impl true
  def handle_info(entity, state) when entity in [:like, :follow, :block, :repost, :signup] do
    key =
      case entity do
        :like -> :likes
        :follow -> :follows
        :block -> :blocks
        :repost -> :reposts
        :signup -> :signups
      end

    state =
      put_in(
        state.counters,
        Map.put(state.counters, key, Map.get(state.counters, key) + 1)
      )

    state =
      put_in(
        state.debug_counters,
        Map.put(state.debug_counters, key, Map.get(state.debug_counters, key) + 1)
      )

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, down_ref, :process, _pid, reason}, state) do
    if state.monitor_ref == down_ref do
      Logger.warning("ingestor process died, reason: #{inspect(reason)}")
      Logger.warning("waiting 1 second then reconnecting...")
      Process.sleep(1000)
      {:noreply, state, {:continue, :reconnect}}
    else
      Logger.warning(
        "received unknown ref #{inspect(down_ref)}, expected #{inspect(state.monitor_ref)}"
      )

      {:noreply, state}
    end
  end

  @impl true
  def handle_info(unhandled_message, state) do
    Logger.warning("timeliner received unhandled message: #{inspect(unhandled_message)}")
    {:noreply, state}
  end

  @impl true
  def handle_call({:fetch, timestamp, is_delta?}, _, state) do
    timeline =
      VRHose.TimelinerStorage.fetch(state.storage, timestamp * 1.0)
      |> Enum.map(fn post ->
        %{
          t: "p",
          a: post.author_name,
          b: post.author_handle,
          c: post.text |> to_string,
          d: post.timestamp,
          l: post.languages |> to_string,
          h: post.hash |> to_string,
          f: post.flags |> to_string,
          i: post.micro_id |> to_string
        }
      end)

    timeline_length = length(timeline)

    __MODULE__.Metrics.sent_events(
      if is_delta? do
        "delta"
      else
        "init"
      end,
      timeline_length
    )

    {:reply,
     {:ok,
      %{
        time: System.os_time(:millisecond) / 1000,
        batch: timeline,
        worlds: state.world_ids,
        rates: rates(state, timestamp)
      }}, state}
  end

  defp rates(state, timestamp) do
    # calculate how many seconds back this timestamp is
    now = System.os_time(:second)
    seconds_from_now = now - timestamp

    Logger.info("seconds_from_now = #{seconds_from_now}, rate array=#{length(state.rates)}")

    cond do
      Enum.empty?(state.rates) ->
        Logger.warning("sending inexact rates due to no data!")

        state.counters
        |> Map.from_struct()
        |> Map.to_list()
        |> Enum.map(fn {key, counter} ->
          {key,
           %{
             rate: counter,
             inexact: true
           }}
        end)
        |> Map.new()

      seconds_from_now < 1 ->
        Logger.warning("delta too low! reusing last counters delta=#{seconds_from_now}")

        state.rates
        |> Enum.at(-1)
        |> Map.from_struct()
        |> Map.to_list()
        |> Enum.map(fn {key, counter} ->
          {key,
           %{
             rate: counter,
             inexact: true
           }}
        end)
        |> Map.new()

      true ->
        Logger.debug("computing rates from #{seconds_from_now}sec ago")

        rates =
          state.rates
          |> Enum.slice(0..seconds_from_now)
          |> Enum.map(fn counters ->
            Map.from_struct(counters)
          end)

        sums =
          rates
          |> Enum.reduce(%{}, fn counters, acc ->
            Map.merge(acc, counters, fn _k, v1, v2 ->
              v1 + v2
            end)
          end)

        sums
        |> Enum.map(fn {k, v} ->
          {k,
           %{
             rate: v / length(rates),
             inexact: false
           }}
        end)
        |> Map.new()
    end
  end
end
