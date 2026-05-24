Application.put_env(:permission_ex, PermissionEx.TestRepo,
  url:
    System.get_env(
      "DATABASE_URL",
      "postgres://postgres:postgres@localhost:5432/permission_ex_test"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  log: false
)

Application.put_env(:permission_ex, :repo, PermissionEx.TestRepo)

Mix.Task.run("ecto.create", ["--quiet", "-r", "PermissionEx.TestRepo"])
{:ok, _pid} = PermissionEx.TestRepo.start_link()
Ecto.Migrator.up(PermissionEx.TestRepo, 0, PermissionEx.TestMigration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(PermissionEx.TestRepo, :manual)

ExUnit.start()
