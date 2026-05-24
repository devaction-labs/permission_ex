defmodule PermitExDbTest do
  use PermitEx.DbCase, async: false

  alias PermitEx.{Permission, Role, UserRole}

  describe "global scope" do
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

    test "missing roles return explicit error" do
      assert PermitEx.sync_roles(Ecto.UUID.generate(), ["missing_role"]) ==
               {:error, {:roles_not_found, ["missing_role"]}}
    end

    test "missing permissions return explicit error" do
      {:ok, role} = PermitEx.upsert_role("admin")

      assert PermitEx.sync_permissions(role, ["missing:permission"]) ==
               {:error, {:permissions_not_found, ["missing:permission"]}}
    end
  end

  describe "context roles" do
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
  end

  describe "clone_roles_to_context/2" do
    test "clones permissions from global roles into a context" do
      user_id = Ecto.UUID.generate()
      context_id = Ecto.UUID.generate()

      {:ok, _} = PermitEx.upsert_permission("orders:view")
      {:ok, viewer} = PermitEx.upsert_role("viewer")
      {:ok, _} = PermitEx.sync_permissions(viewer, ["orders:view"])

      {:ok, [context_viewer]} = PermitEx.clone_roles_to_context(context_id)

      assert context_viewer.name == "viewer"
      assert context_viewer.context_id == context_id

      {:ok, _} = PermitEx.assign_role(user_id, "viewer", context_id)

      assert PermitEx.permissions_for(user_id, context_id) == MapSet.new(["orders:view"])
    end

    test "is idempotent — cloning the same context twice does not duplicate roles" do
      context_id = Ecto.UUID.generate()

      {:ok, _} = PermitEx.upsert_permission("orders:view")
      {:ok, viewer} = PermitEx.upsert_role("viewer")
      {:ok, _} = PermitEx.sync_permissions(viewer, ["orders:view"])

      {:ok, _first} = PermitEx.clone_roles_to_context(context_id)
      {:ok, _second} = PermitEx.clone_roles_to_context(context_id)

      context_roles = PermitEx.roles_for_context(context_id)

      assert length(context_roles) == 1
    end

    test "accepts :roles filter to clone only specific roles" do
      context_id = Ecto.UUID.generate()

      {:ok, _} = PermitEx.upsert_role("admin")
      {:ok, _} = PermitEx.upsert_role("viewer")

      {:ok, cloned} = PermitEx.clone_roles_to_context(context_id, roles: ["viewer"])

      assert length(cloned) == 1
      assert hd(cloned).name == "viewer"
    end
  end

  describe "role_matrix/2" do
    test "returns permission names grouped by role name" do
      {:ok, _} = PermitEx.upsert_permission("orders:view")
      {:ok, _} = PermitEx.upsert_permission("orders:manage")
      {:ok, admin} = PermitEx.upsert_role("admin")
      {:ok, viewer} = PermitEx.upsert_role("viewer")
      {:ok, _} = PermitEx.sync_permissions(admin, ["orders:view", "orders:manage"])
      {:ok, _} = PermitEx.sync_permissions(viewer, ["orders:view"])

      matrix = PermitEx.role_matrix()

      assert Enum.sort(matrix["admin"]) == ["orders:manage", "orders:view"]
      assert matrix["viewer"] == ["orders:view"]
    end

    test "role with no permissions appears with empty list" do
      {:ok, _} = PermitEx.upsert_role("empty_role")

      matrix = PermitEx.role_matrix()

      assert matrix["empty_role"] == []
    end

    test "context-scoped matrix returns only context roles" do
      context_id = Ecto.UUID.generate()

      {:ok, _} = PermitEx.upsert_permission("settings:manage")
      {:ok, _} = PermitEx.upsert_permission("orders:view")

      {:ok, global_admin} = PermitEx.upsert_role("admin")
      {:ok, _} = PermitEx.sync_permissions(global_admin, ["orders:view"])

      {:ok, ctx_admin} = PermitEx.upsert_context_role("admin", context_id)
      {:ok, _} = PermitEx.sync_permissions(ctx_admin, ["settings:manage"])

      matrix = PermitEx.role_matrix(context_id)

      assert "settings:manage" in matrix["admin"]
    end
  end

  describe "scope_data_for/3" do
    test "returns roles and permissions in a single query" do
      user_id = Ecto.UUID.generate()

      {:ok, _} = PermitEx.upsert_permission("orders:view")
      {:ok, admin} = PermitEx.upsert_role("admin")
      {:ok, _} = PermitEx.sync_permissions(admin, ["orders:view"])
      {:ok, _} = PermitEx.sync_roles(user_id, ["admin"])

      {roles, permissions} = PermitEx.scope_data_for(user_id)

      assert Enum.any?(roles, &(&1.name == "admin"))
      assert MapSet.member?(permissions, "orders:view")
    end

    test "user with no roles returns empty collections" do
      {roles, permissions} = PermitEx.scope_data_for(Ecto.UUID.generate())

      assert roles == []
      assert permissions == MapSet.new()
    end

    test "user with roles but no permissions returns roles and empty permission set" do
      user_id = Ecto.UUID.generate()

      {:ok, _} = PermitEx.upsert_role("bare_role")
      {:ok, _} = PermitEx.sync_roles(user_id, ["bare_role"])

      {roles, permissions} = PermitEx.scope_data_for(user_id)

      assert Enum.any?(roles, &(&1.name == "bare_role"))
      assert permissions == MapSet.new()
    end
  end

  describe "assign_roles/3" do
    test "assigns multiple roles in a single call" do
      user_id = Ecto.UUID.generate()

      {:ok, _} = PermitEx.upsert_role("admin")
      {:ok, _} = PermitEx.upsert_role("viewer")

      {:ok, count} = PermitEx.assign_roles(user_id, ["admin", "viewer"])

      assert count == 2
      roles = PermitEx.roles_for(user_id)
      assert length(roles) == 2
    end

    test "is idempotent — assigning the same roles twice does not duplicate" do
      user_id = Ecto.UUID.generate()

      {:ok, _} = PermitEx.upsert_role("admin")
      {:ok, _} = PermitEx.assign_roles(user_id, ["admin"])
      {:ok, _} = PermitEx.assign_roles(user_id, ["admin"])

      assert length(PermitEx.roles_for(user_id)) == 1
    end

    test "returns error when a role name does not exist" do
      assert PermitEx.assign_roles(Ecto.UUID.generate(), ["ghost_role"]) ==
               {:error, {:roles_not_found, ["ghost_role"]}}
    end
  end

  describe "revoke_role/4" do
    test "removes a role from a user and returns the deleted count" do
      user_id = Ecto.UUID.generate()

      {:ok, _} = PermitEx.upsert_role("admin")
      {:ok, _} = PermitEx.assign_role(user_id, "admin")

      {:ok, 1} = PermitEx.revoke_role(user_id, "admin")

      assert PermitEx.roles_for(user_id) == []
    end

    test "returns zero when the user does not have the role" do
      user_id = Ecto.UUID.generate()
      {:ok, _} = PermitEx.upsert_role("admin")

      {:ok, 0} = PermitEx.revoke_role(user_id, "admin")
    end

    test "returns error when role does not exist" do
      assert PermitEx.revoke_role(Ecto.UUID.generate(), "nonexistent") ==
               {:error, {:roles_not_found, ["nonexistent"]}}
    end
  end

  describe "allow_missing?: true" do
    test "sync_role_permissions silently drops unrecognized permissions" do
      {:ok, _} = PermitEx.upsert_permission("orders:view")
      {:ok, role} = PermitEx.upsert_role("admin")

      {:ok, _} =
        PermitEx.sync_role_permissions(role, ["orders:view", "missing:perm"],
          allow_missing?: true
        )

      assert [%Permission{name: "orders:view"}] = PermitEx.list_role_permissions(role)
    end

    test "sync_user_roles silently drops unrecognized roles" do
      user_id = Ecto.UUID.generate()
      {:ok, _} = PermitEx.upsert_role("viewer")

      {:ok, _} = PermitEx.sync_user_roles(user_id, ["viewer", "ghost"], nil, allow_missing?: true)

      roles = PermitEx.roles_for(user_id)
      assert length(roles) == 1
      assert hd(roles).name == "viewer"
    end
  end

  describe "seed!/2" do
    test "creates permissions and roles in a single transaction" do
      {:ok, :ok} =
        PermitEx.seed!(
          permissions: [
            {"orders:view", "View orders"},
            {"orders:manage", "Manage orders"}
          ],
          roles: [
            {"admin", "Administrator", ["orders:view", "orders:manage"]},
            {"viewer", "Read-only", ["orders:view"]}
          ]
        )

      assert PermitEx.get_permission_by_name("orders:view") != nil
      assert PermitEx.get_permission_by_name("orders:manage") != nil

      assert [_, _] = PermitEx.list_role_permissions(PermitEx.get_role_by_name("admin"))
      assert [_] = PermitEx.list_role_permissions(PermitEx.get_role_by_name("viewer"))
    end

    test "is idempotent when called twice with the same definitions" do
      definitions = [
        permissions: [{"orders:view", "View orders"}],
        roles: [{"admin", "Admin", ["orders:view"]}]
      ]

      {:ok, :ok} = PermitEx.seed!(definitions)
      {:ok, :ok} = PermitEx.seed!(definitions)

      assert length(PermitEx.list_permissions()) == 1
    end
  end

  describe "list_roles/1 with preloaded permissions" do
    test "returns permissions preloaded on each role" do
      {:ok, _} = PermitEx.upsert_permission("orders:view")
      {:ok, admin} = PermitEx.upsert_role("admin")
      {:ok, _} = PermitEx.sync_permissions(admin, ["orders:view"])

      [role] = PermitEx.list_roles()

      assert [%Permission{name: "orders:view"}] = role.permissions
    end
  end

  describe "admin lookup APIs" do
    test "return expected records" do
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
end
