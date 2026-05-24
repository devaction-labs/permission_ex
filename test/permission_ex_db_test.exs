defmodule PermissionExDbTest do
  use PermissionEx.DbCase, async: false

  alias PermissionEx.{Permission, Role, UserRole}

  test "syncs global roles and permissions for a user" do
    user_id = Ecto.UUID.generate()

    {:ok, _} = PermissionEx.upsert_permission("orders:view", %{description: "View orders"})
    {:ok, _} = PermissionEx.upsert_permission("orders:manage", %{description: "Manage orders"})
    {:ok, admin} = PermissionEx.upsert_role("admin")
    {:ok, _} = PermissionEx.sync_permissions(admin, ["orders:view", "orders:manage"])
    {:ok, 1} = PermissionEx.sync_roles(user_id, ["admin"])

    scope = PermissionEx.Scope.for_user(user_id)

    assert PermissionEx.can?(scope, "orders:view")
    assert PermissionEx.can?(scope, "orders:manage")
    assert PermissionEx.has_role?(scope, "admin")
  end

  test "context roles take precedence over global roles with the same name" do
    user_id = Ecto.UUID.generate()
    context_id = Ecto.UUID.generate()

    {:ok, _} = PermissionEx.upsert_permission("orders:view")
    {:ok, _} = PermissionEx.upsert_permission("orders:manage")

    {:ok, global_admin} = PermissionEx.upsert_role("admin")
    {:ok, _} = PermissionEx.sync_permissions(global_admin, ["orders:view"])

    {:ok, context_admin} = PermissionEx.upsert_context_role("admin", context_id)
    {:ok, _} = PermissionEx.sync_permissions(context_admin, ["orders:manage"])

    {:ok, _} = PermissionEx.sync_roles(user_id, ["admin"], context_id)

    scope = PermissionEx.Scope.for_user(user_id, context_id)

    assert PermissionEx.can?(scope, "orders:manage")
    refute PermissionEx.can?(scope, "orders:view")
  end

  test "missing roles and permissions return explicit errors" do
    {:ok, role} = PermissionEx.upsert_role("admin")

    assert PermissionEx.sync_permissions(role, ["missing:permission"]) ==
             {:error, {:permissions_not_found, ["missing:permission"]}}

    assert PermissionEx.sync_roles(Ecto.UUID.generate(), ["missing_role"]) ==
             {:error, {:roles_not_found, ["missing_role"]}}
  end

  test "clones global role templates into a context" do
    context_id = Ecto.UUID.generate()

    {:ok, _} = PermissionEx.upsert_permission("orders:view")
    {:ok, viewer} = PermissionEx.upsert_role("viewer")
    {:ok, _} = PermissionEx.sync_permissions(viewer, ["orders:view"])

    {:ok, [context_viewer]} = PermissionEx.clone_roles_to_context(context_id)

    assert context_viewer.name == "viewer"
    assert context_viewer.context_id == context_id
    assert PermissionEx.permissions_for(Ecto.UUID.generate(), context_id) == MapSet.new()
  end

  test "admin lookup APIs return expected records" do
    user_id = Ecto.UUID.generate()

    {:ok, permission} = PermissionEx.upsert_permission("settings:manage")
    {:ok, role} = PermissionEx.upsert_role("owner")
    {:ok, _} = PermissionEx.sync_permissions(role, ["settings:manage"])
    {:ok, _} = PermissionEx.assign_role(user_id, "owner")

    assert %Permission{id: permission_id} = PermissionEx.get_permission_by_name("settings:manage")
    assert permission_id == permission.id

    assert %Role{id: role_id} = PermissionEx.get_role_by_name("owner")
    assert role_id == role.id

    assert [%Permission{name: "settings:manage"}] = PermissionEx.list_role_permissions(role)
    assert [^user_id] = PermissionEx.users_with_role("owner")
    assert [%UserRole{user_id: ^user_id}] = PermissionEx.list_user_roles(user_id)
  end
end
