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
    |> Map.put(:author_handle, identity.also_known_as)
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
        aka = resp.body["handle"]

        display_name =
          case resp.body["displayName"] do
            nil -> "<unknown>"
            "" -> aka || did
            v -> v |> String.trim()
          end

        {:ok, identity} = VRHose.Identity.insert(did, aka || did, "nil", display_name)

        post_data
        |> hydrate_with(identity)

      {:error, v} ->
        Logger.error("Error fetching profile for did #{did}: #{inspect(v)}")

        post_data
        |> hydrate_with(VRHose.Identity.fake(did))
    end
  end

  defp process_without_cache_old({did, post_data, _}) do
    plc_url = Application.fetch_env!(:vrhose, :atproto)[:did_plc_endpoint]
    {:ok, resp} = Req.get("#{plc_url}/#{did}", finch: VRHose.Finch)
    rbody = Jason.decode!(resp.body)
    # IO.inspect(rbody, label: "did")

    has_did_context =
      rbody["@context"]
      |> then(fn
        v when is_bitstring(v) -> [v]
        v when is_list(v) -> v
      end)
      |> Enum.any?(fn v ->
        v == "https://www.w3.org/ns/did/v1"
      end)

    {aka, pds} =
      if has_did_context do
        {rbody["alsoKnownAs"] |> Enum.at(0),
         rbody["service"]
         |> Enum.filter(fn service ->
           service["type"] == "AtprotoPersonalDataServer" and
             service["id"] == "#atproto_pds"
         end)
         |> Enum.at(0)
         |> then(fn
           nil -> nil
           v -> v["serviceEndpoint"]
         end)}
      else
        {nil, nil}
      end

    # {:ok, _} = VRHose.Identity.insert(did, aka, pds, nil)

    # we have the pds url, we need to go there to get the bsky actor profile
    {:ok, profile} =
      XRPC.Client.new(pds)
      |> XRPC.query("com.atproto.repo.getRecord",
        params: [repo: did, collection: "app.bsky.actor.profile", rkey: "self"]
      )

    # IO.inspect(profile)

    display_name =
      case (profile["value"] || %{})["displayName"] do
        nil -> "<unknown>"
        "" -> aka
        v -> v
      end

    {:ok, identity} = VRHose.Identity.insert(did, aka, pds, display_name)

    post_data
    |> hydrate_with(identity)
  end
end
