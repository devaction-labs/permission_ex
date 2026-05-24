if Code.ensure_loaded?(Absinthe.Resolution) do
  defmodule PermitEx.Absinthe.RequirePermission do
    @moduledoc """
    Absinthe middleware that requires a single permission.

        middleware PermitEx.Absinthe.RequirePermission, "orders:manage"
    """

    @behaviour Absinthe.Middleware

    @impl Absinthe.Middleware
    def call(resolution, permission) when is_binary(permission) or is_atom(permission) do
      PermitEx.Absinthe.RequireAuthorization.call(resolution, permission: permission)
    end
  end
end
