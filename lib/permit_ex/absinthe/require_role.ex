if Code.ensure_loaded?(Absinthe.Resolution) do
  defmodule PermitEx.Absinthe.RequireRole do
    @moduledoc """
    Absinthe middleware that requires a single role.

        middleware PermitEx.Absinthe.RequireRole, "admin"
    """

    @behaviour Absinthe.Middleware

    @impl Absinthe.Middleware
    def call(resolution, role) when is_binary(role) or is_atom(role) do
      PermitEx.Absinthe.RequireAuthorization.call(resolution, role: role)
    end
  end
end
