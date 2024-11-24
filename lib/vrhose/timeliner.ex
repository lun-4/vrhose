defmodule VRHose.Timeliner do
  use GenServer
  require Logger

  defmodule Counters do
    defstruct posts: 0, likes: 0, reposts: 0, follows: 0
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

    {:ok,
     %{
       worker_id: worker_id,
       storage: handle,
       counters: %__MODULE__.Counters{},
       debug_counters: %__MODULE__.Counters{}
     }}
  end

  @batch_limit 10000
  @total_memory_limit 10000

  @impl true
  def handle_info(:print_stats, state) do
    Process.send_after(self(), :print_stats, 1000)

    Logger.info(
      "posts: #{state.debug_counters.posts}, likes: #{state.debug_counters.likes}, reposts: #{state.debug_counters.reposts}, follows: #{state.debug_counters.follows}"
    )

    {:noreply, put_in(state.debug_counters, %__MODULE__.Counters{})}
  end

  @impl true
  def handle_info({:post, post}, state) do
    VRHose.TimelinerStorage.insert_post(state.storage, post)

    """
    last_post = Enum.at(state.posts, -1)

    delta =
    if last_post != nil do
      now = DateTime.utc_now() |> DateTime.to_unix(:second)
      now - last_post.timestamp
    else
      0
    end

    # TODO better eviction
    posts =
    if delta > 30 do
      IO.puts("drop by delta")
      Enum.drop(state.posts, 1)
    else
      overfill = Enum.count(state.posts) - @total_memory_limit

      if overfill > 0 do
        IO.puts("drop by overfill")
        Enum.drop(state.posts, overfill)
      else
        state.posts
      end
    end

    """

    #    {:noreply, put_in(state.posts, posts ++ [post])}
    # state = put_in(state.counters, %{state.counters | posts: state.posts + 1})
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
        batch: timeline
      }}, state}
  end
end
