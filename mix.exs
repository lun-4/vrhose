defmodule VRHose.MixProject do
  use Mix.Project

  def project do
    [
      app: :vrhose,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {VRHose.Application, []},
      extra_applications: [:logger, :runtime_tools, :inets]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.14"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:certifi, "~> 2.13"},
      {:recon, "~> 2.3"},
      {:mint, "~> 1.0"},
      {:mint_web_socket, "~> 1.0"},
      {:ezstd, "~> 1.1"},
      {:zigler, "~> 0.13.2", runtime: false},
      {:gen_stage, "~> 1.0"},
      {:req, "~> 0.5.0"},
      {:xrpc, git: "https://github.com/moomerman/xrpc", branch: "main"},
      {:ex_hash_ring, "~> 6.0"},
      {:prometheus, "~> 4.6"},
      {:prometheus_ex,
       git: "https://github.com/lanodan/prometheus.ex.git",
       branch: "fix/elixir-1.14",
       override: true},
      {:prometheus_plugs, "~> 1.1"},
      {:prometheus_phoenix, "~> 1.3"},
      # Note: once `prometheus_phx` is integrated into `prometheus_phoenix`, remove the former:
      {:prometheus_phx,
       git: "https://git.pleroma.social/pleroma/elixir-libraries/prometheus-phx.git",
       branch: "no-logging"},
      {:prometheus_ecto, "~> 1.4"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      setup: ["deps.get", "zig.get"]
    ]
  end
end
