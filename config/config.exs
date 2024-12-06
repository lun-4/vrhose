# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :vrhose,
  namespace: VRHose,
  generators: [timestamp_type: :utc_datetime]

config :vrhose,
  ecto_repos: [VRHose.Repo]

repos = [
  VRHose.Repo,
  VRHose.Repo.Replica1,
  VRHose.Repo.Replica2,
  VRHose.Repo.Replica3,
  VRHose.Repo.Replica4,
  VRHose.Repo.JanitorReplica
]

for repo <- repos do
  config :vrhose, repo,
    cache_size: -8_000,
    pool_size: 1,
    auto_vacuum: :incremental,
    telemetry_prefix: [:vrhose, :repo],
    telemetry_event: [VRHose.Repo.Instrumenter],
    queue_target: 500,
    queue_interval: 2000,
    database: "vrhose_#{Mix.env()}.db"
end

# Configures the endpoint
config :vrhose, VRHoseWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: VRHoseWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: VRHose.PubSub,
  live_view: [signing_salt: "10KBJgAB"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :vrhose, :atproto, did_plc_endpoint: "https://plc.directory"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
