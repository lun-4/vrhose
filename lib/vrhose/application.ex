defmodule VRHose.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      VRHoseWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:vrhose, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: VRHose.PubSub},
      # Start a worker by calling: VRHose.Worker.start_link(arg)
      # {VRHose.Worker, arg},
      # Start to serve requests, typically the last entry
      VRHose.Ingestor,
      VRHoseWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VRHose.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VRHoseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
