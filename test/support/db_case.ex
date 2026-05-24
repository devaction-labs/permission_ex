defmodule PermitEx.DbCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query

      alias PermitEx.TestRepo
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(PermitEx.TestRepo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(PermitEx.TestRepo, {:shared, self()})
    end

    :ok
  end
end
