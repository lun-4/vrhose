defmodule VRHose.Repo.Base do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use Ecto.Repo,
        otp_app: :vrhose,
        adapter: Ecto.Adapters.SQLite3,

        # sqlite does not do multi-writer. pool_size is effectively one,
        # if it's larger than one, then Database Busy errors haunt you
        # the trick to make concurrency happen is to create "read replicas"
        # that are effectively a pool of readers. this works because we're in WAL mode
        pool_size: 1,
        loggers: [VRHose.Repo.Instrumenter, Ecto.LogEntry]

      @read_replicas opts[:read_replicas]
      @dedicated_replicas opts[:dedicated_replicas]

      def repo_spec do
        %{read_replicas: @read_replicas, dedicated_replicas: @dedicated_replicas}
      end

      def replica() do
        Enum.random(@read_replicas)
      end

      def replica(identifier)
          when is_number(identifier) or is_bitstring(identifier) or is_atom(identifier) do
        @read_replicas |> Enum.at(rem(identifier |> :erlang.phash2(), length(@read_replicas)))
      end

      for repo <- @read_replicas ++ @dedicated_replicas do
        default_dynamic_repo =
          if Mix.env() == :test do
            opts[:primary]
          else
            repo
          end

        defmodule repo do
          use Ecto.Repo,
            otp_app: :vrhose,
            adapter: Ecto.Adapters.SQLite3,
            pool_size: 1,
            loggers: [VRHose.Repo.Instrumenter, Ecto.LogEntry],
            read_only: true,
            default_dynamic_repo: default_dynamic_repo
        end
      end
    end
  end
end
