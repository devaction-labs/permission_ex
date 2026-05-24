defmodule PermissionEx.Plug.RequireAuthorization do
  @moduledoc """
  Plug for enforcing PermissionEx roles and permissions in controllers or APIs.

      plug PermissionEx.Plug.RequireAuthorization, permission: "orders:manage"
      plug PermissionEx.Plug.RequireAuthorization, role: "admin"
      plug PermissionEx.Plug.RequireAuthorization,
        any_permissions: ["orders:manage", "settings:manage"]
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts) when is_list(opts), do: opts

  def init(permission) when is_binary(permission) or is_atom(permission),
    do: [permission: permission]

  @impl Plug
  def call(conn, opts) do
    assign_key = Keyword.get(opts, :assign_key, :current_scope)
    scope = conn.assigns[assign_key]

    if PermissionEx.Guard.authorized?(scope, opts) do
      conn
    else
      reject(conn, opts)
    end
  end

  defp reject(conn, opts) do
    status = Keyword.get(opts, :status, 403)
    body = Keyword.get(opts, :body, default_body(conn, opts))
    content_type = Keyword.get(opts, :content_type, default_content_type(conn, opts))

    conn
    |> put_resp_content_type(content_type)
    |> send_resp(status, body)
    |> halt()
  end

  defp default_body(conn, opts) do
    case response_format(conn, opts) do
      :json -> ~s({"error":"forbidden"})
      :text -> "Forbidden"
    end
  end

  defp default_content_type(conn, opts) do
    case response_format(conn, opts) do
      :json -> "application/json"
      :text -> "text/plain"
    end
  end

  defp response_format(_conn, opts) do
    Keyword.get(opts, :format, :json)
  end
end
