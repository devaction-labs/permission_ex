if Code.ensure_loaded?(Plug) do
  defmodule PermitEx.Plug.RequirePermission do
    @moduledoc """
    Plug shortcut for requiring one permission.

        plug PermitEx.Plug.RequirePermission, "orders:manage"
    """

    @behaviour Plug

    @impl Plug
    def init(permission) when is_binary(permission) or is_atom(permission),
      do: [permission: permission]

    def init(opts) when is_list(opts), do: opts

    @impl Plug
    def call(conn, opts), do: PermitEx.Plug.RequireAuthorization.call(conn, opts)
  end
end
