defmodule PermitExDbTest do
  use PermitEx.DbCase, async: false

  alias PermitEx.{Permission, Role, UserRole}

  test "syncs global roles and permissions for a user" do
    user_id = Ecto.UUID.generate()

    {:ok, _} = PermitEx.upsert_permission("orders:view", %{description: "View orders"})
    {:ok, _} = PermitEx.upsert_permission("orders:manage", %{description: "Manage orders"})
    {:ok, admin} = PermitEx.upsert_role("admin")
    {:ok, _} = PermitEx.sync_permissions(admin, ["orders:view", "orders:manage"])
    {:ok, 1} = PermitEx.sync_roles(user_id, ["admin"])

    scope = PermitEx.Scope.for_user(user_id)

    assert PermitEx.can?(scope, "orders:view")
    assert PermitEx.can?(scope, "orders:manage")
    assert PermitEx.has_role?(scope, "admin")
  end

  test "context roles take precedence over global roles with the same name" do
    user_id = Ecto.UUID.generate()
    context_id = Ecto.UUID.generate()

    {:ok, _} = PermitEx.upsert_permission("orders:view")
    {:ok, _} = PermitEx.upsert_permission("orders:manage")

    {:ok, global_admin} = PermitEx.upsert_role("admin")
    {:ok, _} = PermitEx.sync_permissions(global_admin, ["orders:view"])

    {:ok, context_admin} = PermitEx.upsert_context_role("admin", context_id)
    {:ok, _} = PermitEx.sync_permissions(context_admin, ["orders:manage"])

    {:ok, _} = PermitEx.sync_roles(user_id, ["admin"], context_id)

    scope = PermitEx.Scope.for_user(user_id, context_id)

    assert PermitEx.can?(scope, "orders:manage")
    refute PermitEx.can?(scope, "orders:view")
  end

  test "missing roles and permissions return explicit errors" do
    {:ok, role} = PermitEx.upsert_role("admin")

    assert PermitEx.sync_permissions(role, ["missing:permission"]) ==
             {:error, {:permissions_not_found, ["missing:permission"]}}

    assert PermitEx.sync_roles(Ecto.UUID.generate(), ["missing_role"]) ==
             {:error, {:roles_not_found, ["missing_role"]}}
  end

  test "clones global role templates into a context" do
    context_id = Ecto.UUID.generate()

    {:ok, _} = PermitEx.upsert_permission("orders:view")
    {:ok, viewer} = PermitEx.upsert_role("viewer")
    {:ok, _} = PermitEx.sync_permissions(viewer, ["orders:view"])

    {:ok, [context_viewer]} = PermitEx.clone_roles_to_context(context_id)

    assert context_viewer.name == "viewer"
    assert context_viewer.context_id == context_id
    assert PermitEx.permissions_for(Ecto.UUID.generate(), context_id) == MapSet.new()
  end

  test "admin lookup APIs return expected records" do
    user_id = Ecto.UUID.generate()

    {:ok, permission} = PermitEx.upsert_permission("settings:manage")
    {:ok, role} = PermitEx.upsert_role("owner")
    {:ok, _} = PermitEx.sync_permissions(role, ["settings:manage"])
    {:ok, _} = PermitEx.assign_role(user_id, "owner")

    assert %Permission{id: permission_id} = PermitEx.get_permission_by_name("settings:manage")
    assert permission_id == permission.id

    assert %Role{id: role_id} = PermitEx.get_role_by_name("owner")
    assert role_id == role.id

    assert [%Permission{name: "settings:manage"}] = PermitEx.list_role_permissions(role)
    assert [^user_id] = PermitEx.users_with_role("owner")
    assert [%UserRole{user_id: ^user_id}] = PermitEx.list_user_roles(user_id)
  end
end
