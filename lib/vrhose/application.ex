defmodule VRHose.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @jetstream "wss://jetstream2.us-east.bsky.network/subscribe" <>
               "?wantedCollections=app.bsky.feed.post" <>
               "&wantedCollections=app.bsky.feed.like" <>
               "&wantedCollections=app.bsky.graph.follow" <>
               "&wantedCollections=app.bsky.graph.block" <>
               "&wantedCollections=app.bsky.feed.repost" <>
               "&wantedCollections=app.bsky.actor.profile" <>
               "&compress=true"

  @impl true
  def start(_type, _args) do
    VRHose.TimelinerStorage.init(System.schedulers_online())

    children =
      [
        VRHoseWeb.Telemetry
      ] ++
        repos() ++
        [
          {VRHose.QuickLeader, name: VRHose.QuickLeader},
          {Finch,
           name: VRHose.Finch,
           pools: %{
             :default => [size: 50, count: 50]
           }},
          {DNSCluster, query: Application.get_env(:vrhose, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: VRHose.PubSub},
          {
            Registry,
            # , partitions: System.schedulers_online()},
            keys: :duplicate, name: Registry.Timeliners
          },
          {ExHashRing.Ring, name: VRHose.Hydrator.Ring}
        ] ++
        hydration_workers() ++
        [
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
        ] ++ timeliner_workers() ++ janitor_workers()

    start_telemetry()
    IO.inspect(children, label: "application tree")

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VRHose.Supervisor, max_restarts: 10]
    Supervisor.start_link(children, opts)
  end

  def primaries() do
    Application.fetch_env!(:vrhose, :ecto_repos)
  end

  defp repos() do
    Application.fetch_env!(:vrhose, :ecto_repos)
    |> Enum.map(fn primary ->
      primary
      |> to_string
      |> then(fn
        "Elixir.VRHose.Repo" <> _ ->
          spec = primary.repo_spec()
          [primary] ++ spec.read_replicas ++ spec.dedicated_replicas

        _ ->
          []
      end)
    end)
    |> Enum.reduce(fn x, acc -> x ++ acc end)
    |> Enum.map(fn repo ->
      case Application.fetch_env(:vrhose, repo) do
        :error ->
          raise RuntimeError, "Repo #{repo} not configured"

        {:ok, cfg} ->
          if Access.get(cfg, :database) == nil do
            raise RuntimeError, "Repo #{repo} not configured. missing database"
          end

          repo
      end
    end)
  end

  def hydration_workers() do
    1..20
    |> Enum.map(fn i ->
      %{
        id: "worker_#{i}",
        start: {
          VRHose.Hydrator,
          :start_link,
          [
            [
              worker_id: "worker_#{i}"
            ]
          ]
        }
      }
    end)
  end

  def timeliner_workers() do
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

  defp start_telemetry do
    require Prometheus.Registry

    if Application.get_env(:prometheus, VRHose.Repo.Instrumenter) do
      Logger.info("starting db telemetry...")

      :ok =
        :telemetry.attach(
          "prometheus-ecto",
          [:vrhose, :repo, :query],
          &VRHose.Repo.Instrumenter.handle_event/4,
          %{}
        )

      VRHose.Repo.Instrumenter.setup()
    end

    VRHoseWeb.Endpoint.MetricsExporter.setup()
    VRHoseWeb.Endpoint.PipelineInstrumenter.setup()
    VRHose.Ingestor.Metrics.setup()
    VRHose.Timeliner.Metrics.setup()

    # Note: disabled until prometheus-phx is integrated into prometheus-phoenix:
    # YtSearchWeb.Endpoint.Instrumenter.setup()
    PrometheusPhx.setup()
    Logger.info("telemetry started!")
  end

  defp janitor_specs do
    [
      [VRHose.Identity.Janitor, [every: 8 * 60, jitter: -60..60]]
    ]
  end

  defp janitor_workers do
    janitor_specs()
    |> Enum.map(fn [module, opts] ->
      VRHose.Tinycron.new(module, opts)
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
