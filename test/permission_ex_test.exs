defmodule PermissionExTest do
  use ExUnit.Case, async: true

  import Plug.Test

  defmodule OwnerPolicy do
    @behaviour PermissionEx.Policy

    def authorize(scope, resource, _opts), do: scope.user_id == resource.owner_id
  end

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

  describe "allowed?/4" do
    test "combines RBAC and resource policy checks" do
      scope = %{user_id: "user-1", permissions: ["orders:manage"]}

      assert PermissionEx.allowed?(scope, "orders:manage", %{owner_id: "user-1"},
               policy: OwnerPolicy
             )

      refute PermissionEx.allowed?(scope, "orders:manage", %{owner_id: "user-2"},
               policy: OwnerPolicy
             )
    end
  end

  describe "Plug guards" do
    test "allows authorized connections" do
      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:current_scope, %{permissions: ["orders:manage"]})

      result = PermissionEx.Plug.RequirePermission.call(conn, permission: "orders:manage")

      refute result.halted
    end

    test "halts unauthorized connections" do
      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:current_scope, %{permissions: []})

      result = PermissionEx.Plug.RequirePermission.call(conn, permission: "orders:manage")

      assert result.halted
      assert result.status == 403
      assert result.resp_body == ~s({"error":"forbidden"})
    end
  end

  describe "LiveView guards" do
    test "continues authorized sockets" do
      socket = %Phoenix.LiveView.Socket{assigns: %{current_scope: %{roles: ["admin"]}}}

      assert {:cont, ^socket} =
               PermissionEx.LiveView.RequireRole.on_mount("admin", %{}, %{}, socket)
    end

    test "halts unauthorized sockets" do
      socket = %Phoenix.LiveView.Socket{assigns: %{current_scope: %{roles: []}}}

      assert {:halt, ^socket} =
               PermissionEx.LiveView.RequireRole.on_mount("admin", %{}, %{}, socket)
    end
  end
end
