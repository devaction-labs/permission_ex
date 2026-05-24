# use_nexus Migration Notes

These notes map the current `use_nexus` authorization model to PermitEx.

`use_nexus` already has the right concepts:

- roles
- permissions
- role permissions
- user roles
- tenant-scoped role catalogs
- `current_scope`

PermitEx should replace the shared RBAC mechanics, not the app-specific
business rules.

## Suggested Mapping

| use_nexus concept | PermitEx concept |
| --- | --- |
| `UseNexus.Authorization` | `PermitEx` |
| `UseNexus.Accounts.Scope.permissions` | `PermitEx.Scope.permissions` |
| `tenant_id` | `context_id` |
| tenant role catalog | context roles cloned from global templates |
| `"settings:manage"` | `"settings:manage"` |

## Migration Strategy

1. Keep the existing tables in place.
2. Install PermitEx migrations.
3. Seed PermitEx with the same permission names used by `use_nexus`.
4. Clone global role templates into each tenant context.
5. Migrate user role assignments tenant by tenant.
6. Update `UseNexus.Accounts.Scope` to load PermitEx roles and permissions.
7. Replace direct calls to `UseNexus.Authorization.has_permission?/2` with
   `PermitEx.can?/2`.
8. Replace route guards incrementally.
9. Remove old RBAC tables only after production verification.

## Example Seed

```elixir
PermitEx.seed!(
  permissions: [
    {"admin:view", "Access to the admin area"},
    {"tenants:view", "See tenants"},
    {"tenants:manage", "Manage tenants"},
    {"users:view", "See users"},
    {"users:manage", "Manage users"},
    {"app:view", "Access the application"},
    {"operations:view", "See operations"},
    {"operations:manage", "Manage operational records"},
    {"settings:view", "View settings"},
    {"settings:manage", "Manage settings"}
  ],
  roles: [
    {"admin", "Tenant administrator",
     ["app:view", "users:view", "users:manage", "operations:view", "operations:manage",
      "settings:view", "settings:manage"]},
    {"user", "Regular application user", ["app:view", "operations:view", "settings:view"]}
  ]
)
```

## Scope Loading

```elixir
def for_user(user, tenant) do
  permission_scope = PermitEx.Scope.for_user(user, tenant)

  %UseNexus.Accounts.Scope{
    user: user,
    tenant: tenant,
    roles: permission_scope.roles,
    permissions: permission_scope.permissions
  }
end
```

## Route Guards

For Phoenix controllers:

```elixir
plug PermitEx.Plug.RequirePermission, "settings:manage"
```

For LiveView:

```elixir
{PermitEx.LiveView.RequirePermission, "settings:manage"}
```

## Important Caution

Do not delete the existing `use_nexus` authorization code until the new
PermitEx-backed scope has been verified in development and staging. The app
currently mixes user type checks with permission checks, so migration should be
incremental.
