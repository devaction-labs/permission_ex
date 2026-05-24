if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule PermissionEx.LiveView.RequireAuthorization do
    @moduledoc """
    LiveView `on_mount` hook for enforcing PermissionEx roles and permissions.

        live_session :app,
          on_mount: [
            {PermissionEx.LiveView.RequireAuthorization, permission: "orders:view"}
          ]

    Options:

    - `:assign_key` - socket assign containing the authorization scope. Defaults to `:current_scope`.
    - `:redirect_to` - optional path to redirect unauthorized users to.
    - `:flash` - optional `{kind, message}` tuple.
    """

    @doc false
    def on_mount(opts, _params, _session, socket) do
      assign_key = Keyword.get(opts, :assign_key, :current_scope)
      scope = socket.assigns[assign_key]

      if PermissionEx.Guard.authorized?(scope, opts) do
        {:cont, socket}
      else
        {:halt, reject(socket, opts)}
      end
    end

    defp reject(socket, opts) do
      socket
      |> maybe_put_flash(Keyword.get(opts, :flash))
      |> maybe_redirect(Keyword.get(opts, :redirect_to))
    end

    defp maybe_put_flash(socket, nil), do: socket

    defp maybe_put_flash(socket, {kind, message}),
      do: Phoenix.LiveView.put_flash(socket, kind, message)

    defp maybe_redirect(socket, nil), do: socket
    defp maybe_redirect(socket, to), do: Phoenix.LiveView.redirect(socket, to: to)
  end
end
