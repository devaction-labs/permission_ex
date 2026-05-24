defmodule PermissionEx.DbCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query

      alias PermissionEx.TestRepo
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(PermissionEx.TestRepo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(PermissionEx.TestRepo, {:shared, self()})
    end

    :ok
  end
end
