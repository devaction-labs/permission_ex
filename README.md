# PermissionEx

Role and permission management for Ecto and Phoenix applications.

PermissionEx is intentionally close to Laravel Spatie Permission: permissions live
in the database, roles collect permissions, users receive roles inside a
tenant/workspace, and your app checks permissions from the current scope.

## Status

Early extraction. The public API is small on purpose while the Ecto model and
Phoenix integration settle.

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

Install the migration:

```bash
mix permission_ex.install
mix ecto.migrate
```

The installer publishes a migration with these tables:

- `permission_ex_permissions`
- `permission_ex_roles`
- `permission_ex_role_permissions`
- `permission_ex_user_roles`

## Usage

Seed permissions and global role templates:

```elixir
PermissionEx.seed!(
  permissions: [
    {"orders:view", "View orders"},
    {"orders:manage", "Create, edit and delete orders"},
    {"settings:manage", "Manage workspace settings"}
  ],
  roles: [
    {"admin", "Workspace administrator", ["orders:view", "orders:manage", "settings:manage"]},
    {"viewer", "Read-only user", ["orders:view"]}
  ]
)
```

Assign a role to a user inside a tenant/workspace:

```elixir
{:ok, role} = PermissionEx.upsert_role("admin", %{description: "Workspace admin"})
{:ok, _user_role} = PermissionEx.assign_role(user.id, role, tenant.id)
```

Create tenant/workspace-specific roles when you want each tenant to customize
permissions independently:

```elixir
{:ok, role} = PermissionEx.upsert_tenant_role("admin", tenant.id)
```

Sync all permissions for a role:

```elixir
{:ok, _role} =
  PermissionEx.sync_permissions(role, [
    "orders:view",
    "orders:manage",
    "settings:manage"
  ])
```

Sync all roles for a user in a tenant/workspace:

```elixir
{:ok, _count} = PermissionEx.sync_roles(user.id, ["admin", "billing"], tenant.id)
```

Load permissions into your Phoenix scope:

```elixir
permissions = PermissionEx.permissions_for(user.id, tenant.id)
roles = PermissionEx.roles_for(user.id, tenant.id)

%MyApp.Accounts.Scope{
  user: user,
  tenant: tenant,
  roles: roles,
  permissions: permissions
}
```

Check permissions:

```elixir
PermissionEx.can?(scope, "orders:manage")
PermissionEx.has_role?(scope, "admin")
PermissionEx.authorize(scope, "settings:manage")
```

## Naming

Permission names should use `resource:action` strings:

```text
orders:view
orders:manage
settings:manage
```

Strings are used instead of atoms so permissions can be seeded, edited in admin
screens and exposed through APIs without creating atoms at runtime.

## Roadmap

- Phoenix Plug and LiveView `on_mount` guards.
- Tenant role cloning from global templates.
- Cache and invalidation hooks for long-lived LiveViews.
- Policy callbacks for resource-level checks.
- Igniter installer.
