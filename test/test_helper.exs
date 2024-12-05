Code.put_compiler_option(:warnings_as_errors, true)
ExUnit.start()

# for repo <-
#      Application.fetch_env!(:vrhose, :ecto_repos) do
#  Ecto.Adapters.SQL.Sandbox.mode(repo, :auto)
# end
