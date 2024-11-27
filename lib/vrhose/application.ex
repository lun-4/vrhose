defmodule VRHose.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @jetstream "wss://jetstream2.us-east.bsky.network/subscribe?wantedCollections=app.bsky.feed.post" <>
               "&wantedCollections=app.bsky.feed.like" <>
               "&wantedCollections=app.bsky.graph.follow" <>
               "&wantedCollections=app.bsky.graph.block" <>
               "&wantedCollections=app.bsky.feed.repost" <>
               "&compress=true"

  @impl true
  def start(_type, _args) do
    VRHose.TimelinerStorage.init(System.schedulers_online())

    children =
      [
        VRHose.Repo,
        VRHoseWeb.Telemetry,
        {Finch,
         name: VRHose.Finch,
         pools: %{
           :default => [size: 50, count: 50]
         }},
        {DNSCluster, query: Application.get_env(:vrhose, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: VRHose.PubSub},
        # Start a worker by calling: VRHose.Worker.start_link(arg)
        # {VRHose.Worker, arg},
        # Start to serve requests, typically the last entry
        {
          Registry,
          # , partitions: System.schedulers_online()},
          keys: :duplicate, name: Registry.Timeliners
        },
        {VRHose.Hydrator.Producer, name: {:global, VRHose.Hydrator.Producer}},
        {VRHose.Ingestor, name: {:global, VRHose.Ingestor}},
        %{
          start:
            {VRHose.Websocket, :start_and_connect,
             [
               [
                 url: @jetstream,
                 send_to: VRHose.Ingestor
               ]
             ]},
          id: "websocket"
        },
        VRHoseWeb.Endpoint
      ] ++ workers() ++ hydration_workers()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VRHose.Supervisor, max_restarts: 10]
    Supervisor.start_link(children, opts)
  end

  def hydration_workers() do
    1..200
    |> Enum.map(fn i ->
      %{
        id: "worker_#{i}",
        start: {
          VRHose.Hydrator.Worker,
          :start_link,
          [
            [
              worker_id: "worker_#{i}",
              subscribe_to: {:global, VRHose.Hydrator.Producer}
            ]
          ]
        }
      }
    end)
  end

  def workers() do
    1..System.schedulers_online()
    |> Enum.map(fn i ->
      worker_id = "timeliner_#{i}"

      %{
        start:
          {VRHose.Timeliner, :start_link,
           [
             [
               register_with: VRHose.Ingestor,
               worker_id: worker_id
               # name: {:via, Registry, {Registry.Timeliners, "timeliner", :awoo}}
             ]
           ]},
        id: worker_id |> String.to_atom()
      }
    end)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VRHoseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
