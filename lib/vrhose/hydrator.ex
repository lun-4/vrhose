defmodule VRHose.Hydrator do
  @moduledoc """
  hydrate posts with their respective usernames by querying did:plc's AlsoKnownAs
  """

  defmodule Producer do
    use GenStage

    def start_link(_opts) do
      GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
    end

    def submit(work) do
      GenStage.cast(__MODULE__, {:submit, work})
    end

    # Initialize with empty queue
    def init(:ok) do
      {:producer, :queue.new()}
    end

    # Handle submitted work by adding to queue
    def handle_cast({:submit, work}, queue) do
      {:noreply, [work], :queue.in(work, queue)}
    end

    # Handle demand from consumers
    def handle_demand(demand, queue) when demand > 0 do
      # Take up to 'demand' number of items from queue
      {items, new_queue} = take_from_queue(queue, demand, [])
      {:noreply, items, new_queue}
    end

    defp take_from_queue(queue, 0, items) do
      # IO.inspect("0 items: #{inspect(items)}")
      {Enum.reverse(items), queue}
    end

    defp take_from_queue(queue, demand, items) do
      # IO.inspect("demand: #{demand} items: #{inspect(items)}")

      case :queue.out(queue) do
        {{:value, item}, new_queue} ->
          take_from_queue(new_queue, demand - 1, [item | items])

        {:empty, queue} ->
          {Enum.reverse(items), queue}
      end
    end
  end

  defmodule Worker do
    require Logger
    use GenStage

    def start_link(_opts) do
      GenStage.start_link(__MODULE__, :ok)
    end

    def init(:ok) do
      # Subscribe to producer with max_demand of 10
      # min_demand will be 5 (half of max_demand by default)
      {:consumer, :ok, subscribe_to: [{VRHose.Hydrator.Producer, max_demand: 2, min_demand: 1}]}
    end

    def handle_events(events, _from, state) do
      # Logger.info("Hydrating: #{length(events)}")

      Task.async_stream(
        events,
        fn event ->
          process(event)
        end,
        max_concurrency: 1
      )
      |> Stream.run()

      {:noreply, [], state}
    end

    defp hydrate_with(post_data, %VRHose.Identity{} = identity) do
      post_data
      |> Map.put(:author_name, identity.name)
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
      {:ok, resp} =
        Req.get("https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=#{did}")

      aka = resp.body["handle"]

      display_name =
        case resp.body["displayName"] do
          nil -> "<unknown>"
          "" -> aka
          v -> v
        end

      {:ok, identity} = VRHose.Identity.insert(did, aka || did, "nil", display_name)

      post_data
      |> hydrate_with(identity)
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

  defmodule Pipeline do
    use Supervisor

    def start_link(opts) do
      Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def init(_opts) do
      children = [
        {VRHose.Hydrator.Producer, []},
        {VRHose.Hydrator.Worker, []}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end
end
