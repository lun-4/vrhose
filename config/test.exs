import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :vrhose, VRHoseWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "QrZ1l8Qns/Zzs56F+5T+RKPNwD1sn4Wx8H8J5Jl701ShIdPgicXgxL+4SEdscdQu",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :vrhose, VRHose.Repo,
  pool_size: 1,
  queue_target: 10000,
  queue_timeout: 10000

# pool: Ecto.Adapters.SQL.Sandbox
