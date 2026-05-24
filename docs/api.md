# API Guide

PermissionEx can protect JSON APIs through Plug.

## Scope Setup

Your authentication plug should assign a scope before PermissionEx guards run:

```elixir
def call(conn, _opts) do
  user = load_user_from_token(conn)
  scope = PermissionEx.Scope.for_user(user)

  assign(conn, :current_scope, scope)
end
```

For scoped SaaS APIs:

```elixir
workspace = load_workspace(conn)
scope = PermissionEx.Scope.for_user(user, workspace)

assign(conn, :current_scope, scope)
```

## Router Usage

```elixir
pipeline :api_auth do
  plug MyAppWeb.ApiAuth
end

pipeline :orders_write do
  plug PermissionEx.Plug.RequirePermission, "orders:manage"
end

scope "/api", MyAppWeb do
  pipe_through [:api_auth, :orders_write]

  post "/orders", OrderController, :create
end
```

## JSON Errors

By default, unauthorized API requests return:

```json
{"error":"forbidden"}
```

with status `403`.

Customize the response:

```elixir
plug PermissionEx.Plug.RequireAuthorization,
  permission: "orders:manage",
  status: 403,
  body: ~s({"code":"forbidden","message":"Missing permission"}),
  content_type: "application/json"
```

## Role Checks

```elixir
plug PermissionEx.Plug.RequireRole, "admin"
```

## Multiple Checks

Require all permissions:

```elixir
plug PermissionEx.Plug.RequireAuthorization,
  all_permissions: ["orders:view", "orders:manage"]
```

Require any permission:

```elixir
plug PermissionEx.Plug.RequireAuthorization,
  any_permissions: ["orders:manage", "settings:manage"]
```

Combine roles and permissions:

```elixir
plug PermissionEx.Plug.RequireAuthorization,
  role: "admin",
  permission: "orders:manage"
```
