defmodule VRHose.Repo do
  use VRHose.Repo.Base,
    primary: VRHose.Repo,
    read_replicas: [
      VRHose.Repo.Replica1,
      VRHose.Repo.Replica2,
      VRHose.Repo.Replica3,
      VRHose.Repo.Replica4
    ],
    dedicated_replicas: [
      VRHose.Repo.JanitorReplica
    ]

  # use Ecto.Repo,
  #   otp_app: :vrhose,
  #   adapter: Ecto.Adapters.SQLite3,
  #   pool_size: 1,
  #   loggers: [VRHose.Repo.Instrumenter, Ecto.LogEntry]

  defmodule Instrumenter do
    use Prometheus.EctoInstrumenter

    def label_value(:repo, log_entry) do
      log_entry[:repo] |> to_string
    end

    def label_value(:query, log_entry) do
      log_entry[:query]
    end
  end
end
