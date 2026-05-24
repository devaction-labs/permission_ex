Application.put_env(:permit_ex, PermitEx.TestRepo,
  url:
    System.get_env(
      "DATABASE_URL",
      "postgres://postgres:postgres@localhost:5432/permit_ex_test"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  log: false
)

Application.put_env(:permit_ex, :repo, PermitEx.TestRepo)

Mix.Task.run("ecto.create", ["--quiet", "-r", "PermitEx.TestRepo"])
{:ok, _pid} = PermitEx.TestRepo.start_link()
Ecto.Migrator.up(PermitEx.TestRepo, 0, PermitEx.TestMigration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(PermitEx.TestRepo, :manual)

ExUnit.start()
