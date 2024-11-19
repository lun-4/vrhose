defmodule VRHose.Timeliner do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    IO.inspect(opts)
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def fetch_all(pid) do
    GenServer.call(pid, {:fetch, 0})
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

    {:ok,
     %{
       worker_id: worker_id,
       posts: []
     }}
  end

  @impl true
  def handle_info({:post, post}, state) do
    if Enum.count(state.posts) > 1000 do
      {:noreply, put_in(state.posts, Enum.drop(state.posts, 1) ++ [post])}
    else
      {:noreply, put_in(state.posts, state.posts ++ [post])}
    end
  end

  @impl true
  def handle_call({:fetch, timestamp}, _, state) do
    timeline =
      state.posts
      |> Enum.filter(fn post ->
        IO.inspect(post.timestamp)
        IO.inspect(timestamp)
        post.timestamp > timestamp
      end)
      |> Enum.map(fn post ->
        %{
          t: "p",
          a: "<TODO name resolution>",
          b: post.author_handle,
          c: post.text,
          d: post.timestamp,
          l: post.languages,
          h: post.hash |> to_string
        }
      end)

    {:reply,
     {:ok,
      %{
        time: DateTime.utc_now() |> DateTime.to_unix(),
        batch: timeline
      }}, state}
  end
end
