defmodule PermissionEx.Plug.RequireRole do
  @moduledoc """
  Plug shortcut for requiring one role.

      plug PermissionEx.Plug.RequireRole, "admin"
  """

  @behaviour Plug

  @impl Plug
  def init(role) when is_binary(role) or is_atom(role), do: [role: role]
  def init(opts) when is_list(opts), do: opts

  @impl Plug
  def call(conn, opts), do: PermissionEx.Plug.RequireAuthorization.call(conn, opts)
end
