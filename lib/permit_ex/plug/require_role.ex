if Code.ensure_loaded?(Plug) do
  defmodule PermitEx.Plug.RequireRole do
    @moduledoc """
    Plug shortcut for requiring one role.

        plug PermitEx.Plug.RequireRole, "admin"
    """

    @behaviour Plug

    @impl Plug
    def init(role) when is_binary(role) or is_atom(role), do: [role: role]
    def init(opts) when is_list(opts), do: opts

    @impl Plug
    def call(conn, opts), do: PermitEx.Plug.RequireAuthorization.call(conn, opts)
  end
end
