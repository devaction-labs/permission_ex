if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule PermitEx.LiveView.RequireRole do
    @moduledoc """
    LiveView `on_mount` shortcut for requiring one role.

        on_mount {PermitEx.LiveView.RequireRole, "admin"}
    """

    def on_mount(role, params, session, socket) when is_binary(role) or is_atom(role) do
      PermitEx.LiveView.RequireAuthorization.on_mount([role: role], params, session, socket)
    end

    def on_mount(opts, params, session, socket) when is_list(opts) do
      PermitEx.LiveView.RequireAuthorization.on_mount(opts, params, session, socket)
    end
  end
end
