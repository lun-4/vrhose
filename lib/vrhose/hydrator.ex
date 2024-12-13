defmodule VRHose.Hydrator do
  require Logger
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def submit_post(pid, data) do
    GenServer.cast(pid, {:post, data})
  end

  @impl true
  def init(_opts) do
    Logger.info("Initializing hydrator #{inspect(self())}")
    ExHashRing.Ring.add_node(VRHose.Hydrator.Ring, self() |> :erlang.pid_to_list() |> to_string)
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:post, event}, state) do
    process(event)
    {:noreply, state}
  end

  defp hydrate_with(post_data, %VRHose.Identity{} = identity) do
    post_data
    |> Map.put(:author_name, identity.name)
    |> Map.put(:author_handle, "@" <> identity.also_known_as)
    # recompute timestamp because we did some processing before making post ready to go
    |> Map.put(
      :timestamp,
      System.os_time(:millisecond) / 1000
    )
  end

  defp process({did, post_data, subscribers} = event) do
    identity = VRHose.Identity.one(did)

    post_data =
      if identity != nil do
        post_data
        |> hydrate_with(identity)
      else
        process_without_cache(event)
      end

    subscribers
    |> Enum.each(fn pid ->
      send(
        pid,
        {:post, post_data}
      )
    end)
  end

  defp process_without_cache({did, post_data, _}) do
    case Req.get("https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=#{did}") do
      {:ok, resp} ->
        aka = resp.body["handle"] || did

        display_name =
          (resp.body["displayName"] || aka)
          |> String.trim()
          |> then(fn
            "" -> aka
            v -> v
          end)

        {:ok, identity} = VRHose.Identity.insert(did, aka || did, "nil", display_name)

        post_data
        |> hydrate_with(identity)

      {:error, v} ->
        Logger.error("Error fetching profile for did #{did}: #{inspect(v)}")

        post_data
        |> hydrate_with(VRHose.Identity.fake(did))
    end
  end
end
