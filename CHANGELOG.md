# Changelog

## 0.1.0

Initial public release.

### Added

- Ecto schemas for permissions, roles, role permissions, and user roles.
- Install task for copying migrations into host applications.
- Global roles for apps without tenants or workspaces.
- Optional context-specific roles for tenants, workspaces, organizations,
  projects, or accounts.
- Role and permission sync APIs.
- Permission and role checks for map/struct scopes.
- Optional Plug guards for controllers and JSON APIs.
- Optional LiveView `on_mount` guards.
- Context role cloning from global templates.
- Documentation for Phoenix, API, and `use_nexus` migration.
