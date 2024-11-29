defmodule VRHose.Repo do
  use Ecto.Repo,
    otp_app: :vrhose,
    adapter: Ecto.Adapters.SQLite3,
    pool_size: 1,
    loggers: [VRHose.Repo.Instrumenter, Ecto.LogEntry]

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
