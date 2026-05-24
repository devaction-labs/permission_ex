defmodule PermissionExTest do
  use ExUnit.Case, async: true

  describe "can?/2" do
    test "checks map scopes with MapSet permissions" do
      scope = %{permissions: MapSet.new(["orders:view", "orders:manage"])}

      assert PermissionEx.can?(scope, "orders:view")
      refute PermissionEx.can?(scope, "settings:manage")
    end

    test "checks list permissions and normalizes atoms" do
      assert PermissionEx.can?(["manage_members"], :manage_members)
      assert PermissionEx.can?([:manage_members], "manage_members")
    end
  end

  describe "authorize/2" do
    test "returns tagged authorization results" do
      assert PermissionEx.authorize(["orders:view"], "orders:view") == :ok
      assert PermissionEx.authorize([], "orders:view") == {:error, :unauthorized}
    end
  end

  describe "has_role?/2" do
    test "checks scopes with role names" do
      scope = %{roles: ["admin", "billing"]}

      assert PermissionEx.has_role?(scope, :admin)
      refute PermissionEx.has_role?(scope, "viewer")
    end
  end

  describe "normalize helpers" do
    test "normalizes permission and role inputs" do
      assert PermissionEx.normalize_permission(:orders_manage) == "orders_manage"
      assert PermissionEx.normalize_role(:admin) == "admin"
    end
  end

  describe "guard checks" do
    test "supports role and permission combinations" do
      scope = %{roles: ["admin"], permissions: MapSet.new(["orders:view", "orders:manage"])}

      assert PermissionEx.Guard.authorized?(scope,
               role: "admin",
               all_permissions: ["orders:view", "orders:manage"]
             )

      refute PermissionEx.Guard.authorized?(scope,
               role: "admin",
               all_permissions: ["settings:manage"]
             )
    end
  end
end
