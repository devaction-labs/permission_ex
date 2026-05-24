# PermissionEx

Role and permission management for Ecto and Phoenix applications.

PermissionEx is a small RBAC toolkit inspired by Laravel Spatie Permission:
permissions live in the database, roles collect permissions, users receive
roles globally or inside an optional context, and your application checks the
current scope.

Use it for:

- Ecto applications that need database-backed roles and permissions.
- Phoenix controllers and JSON APIs.
- Phoenix LiveView routes and events.
- SaaS applications with tenants, workspaces, organizations, projects, or accounts.
- Regular applications without tenants.

## Status

`0.1.0` is the first public release. The core API is usable, but you should test
it in your app before relying on it in production. The migration is part of the
public contract, so review the table names and indexes before publishing or
installing it in an existing system.

## Concepts

### Permission

A permission is a string such as:

```text
orders:view
orders:manage
settings:manage
```

PermissionEx stores permissions as strings instead of atoms so they can be
seeded, edited in admin screens, and exposed through APIs without creating atoms
at runtime.

### Role

A role groups permissions:

```elixir
PermissionEx.seed!(
  permissions: [
    {"orders:view", "View orders"},
    {"orders:manage", "Create, edit, and delete orders"}
  ],
  roles: [
    {"admin", "Administrator", ["orders:view", "orders:manage"]},
    {"viewer", "Read-only user", ["orders:view"]}
  ]
)
```

### Context

Contexts are optional.

In a regular app, assign roles globally:

```elixir
{:ok, role} = PermissionEx.upsert_role("admin")
{:ok, _user_role} = PermissionEx.assign_role(user.id, role)
```

In a SaaS app, pass your tenant, workspace, organization, project, or account id
as the context:

```elixir
{:ok, role} = PermissionEx.upsert_context_role("admin", workspace.id)
{:ok, _user_role} = PermissionEx.assign_role(user.id, role, workspace.id)
```

## Installation

Add the dependency:

```elixir
def deps do
  [
    {:permission_ex, "~> 0.1.0"}
  ]
end
```

Configure your repo:

```elixir
config :permission_ex, repo: MyApp.Repo
```

Install and run the migration:

```bash
mix permission_ex.install
mix ecto.migrate
```

The installer copies a migration with these tables:

- `permission_ex_permissions`
- `permission_ex_roles`
- `permission_ex_role_permissions`
- `permission_ex_user_roles`

## Quick Start

Seed global permissions and role templates:

```elixir
PermissionEx.seed!(
  permissions: [
    {"orders:view", "View orders"},
    {"orders:manage", "Create, edit, and delete orders"},
    {"settings:manage", "Manage settings"}
  ],
  roles: [
    {"admin", "Administrator", ["orders:view", "orders:manage", "settings:manage"]},
    {"viewer", "Read-only user", ["orders:view"]}
  ]
)
```

Assign roles:

```elixir
{:ok, _count} = PermissionEx.sync_roles(user.id, ["admin"])
```

Load a scope:

```elixir
scope = PermissionEx.Scope.for_user(user)
```

Check permissions and roles:

```elixir
PermissionEx.can?(scope, "orders:manage")
PermissionEx.has_role?(scope, "admin")
PermissionEx.authorize(scope, "settings:manage")
```

## Context-Specific Roles

Clone global role templates into a context:

```elixir
{:ok, roles} = PermissionEx.clone_roles_to_context(workspace.id)
```

Then assign roles inside that context:

```elixir
{:ok, _count} = PermissionEx.sync_roles(user.id, ["admin"], workspace.id)
scope = PermissionEx.Scope.for_user(user, workspace)
```

When a role name exists globally and inside the context, PermissionEx resolves
the context-specific role first.

## Sync APIs

Replace all permissions for a role:

```elixir
{:ok, _role} =
  PermissionEx.sync_permissions(role, [
    "orders:view",
    "orders:manage"
  ])
```

Replace all roles for a user:

```elixir
{:ok, _count} = PermissionEx.sync_roles(user.id, ["admin", "billing"], workspace.id)
```

Add or remove roles without replacing the full set:

```elixir
{:ok, _user_role} = PermissionEx.assign_role(user.id, "viewer", workspace.id)
{:ok, _count} = PermissionEx.assign_roles(user.id, ["viewer", "support"], workspace.id)
{:ok, _count} = PermissionEx.revoke_role(user.id, "viewer", workspace.id)
```

By default, sync APIs return an error for missing names:

```elixir
{:error, {:roles_not_found, ["missing_role"]}}
{:error, {:permissions_not_found, ["orders:delete"]}}
```

Pass `allow_missing?: true` only for intentionally partial imports.

## Phoenix and APIs

PermissionEx includes optional Plug and LiveView adapters. They are compiled
only when the corresponding dependency is available.

For controllers or JSON APIs:

```elixir
plug PermissionEx.Plug.RequirePermission, "orders:manage"
plug PermissionEx.Plug.RequireRole, "admin"
```

For LiveView:

```elixir
on_mount {PermissionEx.LiveView.RequirePermission, "orders:view"}
on_mount {PermissionEx.LiveView.RequireRole, "admin"}
```

More examples:

- [Phoenix Guide](docs/phoenix.md)
- [API Guide](docs/api.md)
- [use_nexus Migration Notes](docs/use-nexus.md)

## Publishing

Before publishing:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs
mix hex.build
```

Publish with:

```bash
mix hex.publish
```

## License

MIT. See [LICENSE](LICENSE).
