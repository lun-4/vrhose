defmodule VRHose.Timeliner do
  use GenServer
  require Logger

  defmodule Counters do
    defstruct posts: 0,
              likes: 0,
              reposts: 0,
              follows: 0,
              blocks: 0
  end

  def start_link(opts \\ []) do
    IO.inspect(opts)
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def fetch_all(pid) do
    now = DateTime.utc_now() |> DateTime.to_unix(:second)
    GenServer.call(pid, {:fetch, now - 30})
  end

  def fetch(pid, timestamp) do
    GenServer.call(pid, {:fetch, timestamp})
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

    :ok = VRHose.Ingestor.subscribe(register_with)
    handle = VRHose.TimelinerStorage.create()

    # computers have at least 1 core... right?
    if handle == 0 do
      Process.send_after(self(), :print_stats, 1000)
    end

    Process.send_after(self(), :compute_rates, 60000)

    {:ok,
     %{
       worker_id: worker_id,
       storage: handle,
       debug_counters: %__MODULE__.Counters{},
       start_time: System.os_time(:second),
       counters: %__MODULE__.Counters{},
       rates: nil
     }}
  end

  @impl true
  def handle_info(:print_stats, state) do
    Process.send_after(self(), :print_stats, 1000)

    Logger.info(
      "posts: #{state.debug_counters.posts}, likes: #{state.debug_counters.likes}, reposts: #{state.debug_counters.reposts}, follows: #{state.debug_counters.follows}"
    )

    {:noreply, put_in(state.debug_counters, %__MODULE__.Counters{})}
  end

  @impl true
  def handle_info(:compute_rates, state) do
    Process.send_after(self(), :compute_rates, 60000)
    # promote rates data we have right now (computed every minute)
    # also reset the counters so we can actually change every minute rather than having a massively global average
    rates = immediate_rates(state)
    state = put_in(state.rates, rates)
    state = put_in(state.counters, %__MODULE__.Counters{})
    state = put_in(state.start_time, System.os_time(:second))
    {:noreply, state}
  end

  @impl true
  def handle_info({:post, post}, state) do
    VRHose.TimelinerStorage.insert_post(state.storage, post)

    state =
      put_in(state.counters, %{state.counters | posts: state.counters.posts + 1})

    state =
      put_in(state.debug_counters, %{state.debug_counters | posts: state.debug_counters.posts + 1})

    {:noreply, state}
  end

  @impl true
  def handle_call({:fetch, timestamp}, _, state) do
    timeline =
      VRHose.TimelinerStorage.fetch(state.storage, timestamp * 1.0)
      |> Enum.map(fn post ->
        %{
          t: "p",
          a: "<TODO name resolution>",
          b: post.author_handle,
          c: post.text |> to_string,
          d: post.timestamp,
          l: post.languages |> to_string,
          h: post.hash |> to_string
        }
      end)

    {:reply,
     {:ok,
      %{
        time: System.os_time(:millisecond) / 1000,
        batch: timeline,
        rates: rates(state)
      }}, state}
  end

  defp rates(state) do
    if state.rates != nil do
      state.rates
    else
      immediate_rates(state)
    end
  end

  defp immediate_rates(state) do
    fields = [:posts, :likes, :reposts, :follows, :blocks]

    fields
    |> Enum.map(fn field ->
      # TODO use precomputed rate value from previous minute
      count = Map.get(state.counters, field) || 0
      time_horizon = System.os_time(:second) - state.start_time

      inexact? = time_horizon < 55

      rate =
        cond do
          # we're still inexact, but we didn't get any data yet
          # this most likely happens because the user requested before any events arrived
          # (very improbable lol)
          # at least give them something
          count == 0 and inexact? -> 30
          # no events means no events
          count == 0 -> 0
          # we have events, compute rate
          true -> count / time_horizon
        end

      {field,
       %{
         rate: rate,
         inexact: inexact?
       }}
    end)
    |> Map.new()
  end
end
