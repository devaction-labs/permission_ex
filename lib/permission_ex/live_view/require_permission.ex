defmodule PermissionEx.LiveView.RequirePermission do
  @moduledoc """
  LiveView `on_mount` shortcut for requiring one permission.

      on_mount {PermissionEx.LiveView.RequirePermission, "orders:view"}
  """

  def on_mount(permission, params, session, socket)
      when is_binary(permission) or is_atom(permission) do
    PermissionEx.LiveView.RequireAuthorization.on_mount(
      [permission: permission],
      params,
      session,
      socket
    )
  end

  def on_mount(opts, params, session, socket) when is_list(opts) do
    PermissionEx.LiveView.RequireAuthorization.on_mount(opts, params, session, socket)
  end
end
