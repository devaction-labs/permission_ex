# Phoenix Guide

This guide shows how to use PermissionEx with Phoenix controllers and LiveView.

## Configure the Repo

```elixir
config :permission_ex, repo: MyApp.Repo
```

## Load Permission Data into Your Scope

PermissionEx does not replace your authentication system. Use `phx.gen.auth`,
Guardian, Pow, OAuth, or your existing session flow to identify the current
user. After authentication, load roles and permissions into your app scope.

For an app without tenants or workspaces:

```elixir
scope = PermissionEx.Scope.for_user(user)
```

For a SaaS app:

```elixir
scope = PermissionEx.Scope.for_user(user, workspace)
```

To enrich your own scope struct:

```elixir
%MyApp.Accounts.Scope{user: user, workspace: workspace}
|> PermissionEx.Scope.put_permission_data(user, workspace)
```

Your scope must be assigned to `:current_scope` by default:

```elixir
assign(conn, :current_scope, scope)
```

## Controllers

Require one permission:

```elixir
plug PermissionEx.Plug.RequirePermission, "orders:manage"
```

Require one role:

```elixir
plug PermissionEx.Plug.RequireRole, "admin"
```

Use the general guard for richer checks:

```elixir
plug PermissionEx.Plug.RequireAuthorization,
  any_permissions: ["orders:manage", "settings:manage"],
  role: "admin"
```

If your scope is stored under another assign:

```elixir
plug PermissionEx.Plug.RequirePermission,
  "orders:manage",
  assign_key: :auth_scope
```

## LiveView

Add guards to a `live_session`:

```elixir
live_session :app,
  on_mount: [
    {MyAppWeb.UserAuth, :require_authenticated},
    {PermissionEx.LiveView.RequirePermission, "orders:view"}
  ] do
  live "/orders", OrderLive.Index, :index
end
```

Use `RequireAuthorization` for redirects and flash messages:

```elixir
{PermissionEx.LiveView.RequireAuthorization,
 permission: "settings:manage",
 redirect_to: "/app",
 flash: {:error, "You cannot access that page."}}
```

## Event Handlers

Route guards protect page access. For mutations, check again inside event
handlers:

```elixir
def handle_event("delete", %{"id" => id}, socket) do
  with :ok <- PermissionEx.authorize(socket.assigns.current_scope, "orders:manage") do
    # delete order
    {:noreply, socket}
  else
    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Not allowed.")}
  end
end
```

## Notes

- PermissionEx is authorization, not authentication.
- Use contexts only when your app needs scoped roles.
- For long-lived LiveViews, reload the scope after changing a user's roles.
