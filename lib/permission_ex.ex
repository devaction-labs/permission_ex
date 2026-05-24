defmodule PermissionEx do
  @moduledoc """
  Role and permission management for Ecto and Phoenix applications.

  `PermissionEx` keeps the core authorization model intentionally small:
  users receive roles in a tenant/workspace, roles receive permissions, and
  permissions are checked against the current scope.
  """

  import Ecto.Query

  alias PermissionEx.{Config, Permission, Role, RolePermission, UserRole}

  @type permission :: String.t() | atom()
  @type role :: Role.t() | Ecto.UUID.t() | String.t()
  @type scope :: %{optional(:permissions) => Enumerable.t()}

  @doc """
  Returns true when the given scope or permission collection includes `permission`.
  """
  def can?(scope_or_permissions, permission)

  def can?(%{permissions: permissions}, permission), do: can?(permissions, permission)

  def can?(%MapSet{} = permissions, permission) do
    MapSet.member?(permissions, normalize_permission(permission))
  end

  def can?(permissions, permission) when is_list(permissions) do
    normalized = normalize_permission(permission)
    Enum.any?(permissions, &(normalize_permission(&1) == normalized))
  end

  def can?(_scope_or_permissions, _permission), do: false

  @doc "Alias for `can?/2`."
  def has_permission?(scope_or_permissions, permission),
    do: can?(scope_or_permissions, permission)

  @doc "Returns true when the given scope or role collection includes `role`."
  def has_role?(scope_or_roles, role)

  def has_role?(%{roles: roles}, role), do: has_role?(roles, role)

  def has_role?(roles, role) when is_list(roles) do
    normalized = normalize_role(role)

    Enum.any?(roles, fn
      %Role{name: name} -> name == normalized
      value -> normalize_role(value) == normalized
    end)
  end

  def has_role?(%MapSet{} = roles, role), do: MapSet.member?(roles, normalize_role(role))
  def has_role?(_scope_or_roles, _role), do: false

  @doc "Returns `:ok` or `{:error, :unauthorized}` for command-style flows."
  def authorize(scope_or_permissions, permission) do
    if can?(scope_or_permissions, permission), do: :ok, else: {:error, :unauthorized}
  end

  @doc "Creates a permission."
  def create_permission(attrs, opts \\ []) do
    repo(opts).insert(Permission.changeset(%Permission{}, stringify_keys(attrs)))
  end

  @doc "Creates or updates a permission by name."
  def upsert_permission(name, attrs \\ %{}, opts \\ []) when is_binary(name) do
    attrs = attrs |> stringify_keys() |> Map.put("name", name)

    repo(opts).insert(
      Permission.changeset(%Permission{}, attrs),
      on_conflict: {:replace, [:description, :updated_at]},
      conflict_target: :name
    )
  end

  @doc "Creates a global role or a tenant role when `tenant_id` is present."
  def create_role(attrs, opts \\ []) do
    repo(opts).insert(Role.changeset(%Role{}, stringify_keys(attrs)))
  end

  @doc "Creates or updates a global role by name."
  def upsert_role(name, attrs \\ %{}, opts \\ []) when is_binary(name) do
    attrs = attrs |> stringify_keys() |> Map.put("name", name)

    repo(opts).insert(
      Role.changeset(%Role{}, attrs),
      on_conflict: {:replace, [:description, :locked, :updated_at]},
      conflict_target: {:unsafe_fragment, "(name) WHERE tenant_id IS NULL"}
    )
  end

  @doc "Creates or updates a tenant/workspace role by name."
  def upsert_tenant_role(name, tenant_id, attrs \\ %{}, opts \\ [])
      when is_binary(name) and is_binary(tenant_id) do
    attrs = attrs |> stringify_keys() |> Map.put("name", name) |> Map.put("tenant_id", tenant_id)

    repo(opts).insert(
      Role.changeset(%Role{}, attrs),
      on_conflict: {:replace, [:description, :locked, :updated_at]},
      conflict_target: {:unsafe_fragment, "(tenant_id, name) WHERE tenant_id IS NOT NULL"}
    )
  end

  @doc "Lists permissions ordered by name."
  def list_permissions(opts \\ []) do
    repo(opts).all(from(p in Permission, order_by: p.name))
  end

  @doc "Lists global roles and roles for the given tenant."
  def list_roles(tenant_id \\ nil, opts \\ []) do
    Role
    |> where([r], is_nil(r.tenant_id) or r.tenant_id == ^tenant_id)
    |> order_by([r], asc: r.name)
    |> preload([:role_permissions])
    |> repo(opts).all()
  end

  @doc """
  Replaces all permissions assigned to a role.

  Accepts a role struct, role id, or role name. Permissions can be names, ids,
  atoms, or `%PermissionEx.Permission{}` structs.
  """
  def sync_role_permissions(role_ref, permissions, opts \\ []) when is_list(permissions) do
    repo = repo(opts)

    with %Role{} = role <- get_role(role_ref, repo, Keyword.get(opts, :tenant_id)) do
      permission_ids = resolve_permission_ids(permissions, repo)

      repo.transaction(fn ->
        repo.delete_all(from(rp in RolePermission, where: rp.role_id == ^role.id))

        entries =
          Enum.map(permission_ids, fn permission_id ->
            %{role_id: role.id, permission_id: permission_id, inserted_at: now()}
          end)

        insert_all_if_any(repo, RolePermission, entries,
          on_conflict: :nothing,
          conflict_target: [:role_id, :permission_id]
        )

        role
      end)
    else
      nil -> {:error, :role_not_found}
    end
  end

  @doc "Alias for `sync_role_permissions/3`."
  def sync_permissions(role_ref, permissions, opts \\ []),
    do: sync_role_permissions(role_ref, permissions, opts)

  @doc "Assigns one role to a user in a tenant/workspace."
  def assign_role(user_id, role_or_id, tenant_id, opts \\ []) do
    repo = repo(opts)

    case resolve_role_ids([role_or_id], tenant_id, repo) do
      [role_id] ->
        %UserRole{}
        |> UserRole.changeset(%{user_id: user_id, role_id: role_id, tenant_id: tenant_id})
        |> repo.insert(
          on_conflict: :nothing,
          conflict_target: [:user_id, :tenant_id, :role_id]
        )

      [] ->
        {:error, :role_not_found}
    end
  end

  @doc "Assigns many roles to a user without removing existing roles."
  def assign_roles(user_id, roles, tenant_id, opts \\ []) when is_list(roles) do
    repo = repo(opts)
    role_ids = resolve_role_ids(roles, tenant_id, repo)

    entries =
      Enum.map(role_ids, fn role_id ->
        %{user_id: user_id, tenant_id: tenant_id, role_id: role_id, inserted_at: now()}
      end)

    {count, _} =
      insert_all_if_any(repo, UserRole, entries,
        on_conflict: :nothing,
        conflict_target: [:user_id, :tenant_id, :role_id]
      )

    {:ok, count}
  end

  @doc "Removes one role from a user in a tenant/workspace."
  def revoke_role(user_id, role_or_id, tenant_id, opts \\ []) do
    repo = repo(opts)

    case resolve_role_ids([role_or_id], tenant_id, repo) do
      [role_id] ->
        {count, _} =
          repo.delete_all(
            from(ur in UserRole,
              where:
                ur.user_id == ^user_id and ur.tenant_id == ^tenant_id and ur.role_id == ^role_id
            )
          )

        {:ok, count}

      [] ->
        {:error, :role_not_found}
    end
  end

  @doc """
  Replaces all roles assigned to a user in a tenant/workspace.

  This is the Spatie-style `syncRoles` equivalent. It accepts role structs, ids
  or names and leaves the user with exactly the resolved roles.
  """
  def sync_user_roles(user_id, roles, tenant_id, opts \\ []) when is_list(roles) do
    repo = repo(opts)
    role_ids = resolve_role_ids(roles, tenant_id, repo)

    repo.transaction(fn ->
      repo.delete_all(
        from(ur in UserRole, where: ur.user_id == ^user_id and ur.tenant_id == ^tenant_id)
      )

      entries =
        Enum.map(role_ids, fn role_id ->
          %{user_id: user_id, tenant_id: tenant_id, role_id: role_id, inserted_at: now()}
        end)

      {count, _} =
        insert_all_if_any(repo, UserRole, entries,
          on_conflict: :nothing,
          conflict_target: [:user_id, :tenant_id, :role_id]
        )

      count
    end)
  end

  @doc "Alias for `sync_user_roles/4`."
  def sync_roles(user_id, roles, tenant_id, opts \\ []),
    do: sync_user_roles(user_id, roles, tenant_id, opts)

  @doc "Loads roles assigned to a user in a tenant/workspace."
  def roles_for(user_id, tenant_id, opts \\ []) do
    from(ur in UserRole,
      join: r in Role,
      on: r.id == ur.role_id,
      where: ur.user_id == ^user_id and ur.tenant_id == ^tenant_id,
      order_by: r.name,
      select: r
    )
    |> repo(opts).all()
  end

  @doc "Loads permission names for the user in a tenant/workspace."
  def permissions_for(user_id, tenant_id, opts \\ []) do
    from(ur in UserRole,
      join: rp in RolePermission,
      on: rp.role_id == ur.role_id,
      join: p in Permission,
      on: p.id == rp.permission_id,
      where: ur.user_id == ^user_id and ur.tenant_id == ^tenant_id,
      select: p.name
    )
    |> repo(opts).all()
    |> MapSet.new()
  end

  @doc """
  Seeds permissions and roles in one transaction.

  Expected shape:

      PermissionEx.seed!(
        permissions: [
          {"orders:view", "View orders"},
          {"orders:manage", "Manage orders"}
        ],
        roles: [
          {"admin", "Tenant admin", ["orders:view", "orders:manage"]},
          {"viewer", "Read-only user", ["orders:view"]}
        ]
      )
  """
  def seed!(definitions, opts \\ []) when is_list(definitions) do
    repo = repo(opts)

    repo.transaction(fn ->
      definitions
      |> Keyword.get(:permissions, [])
      |> Enum.each(fn {name, description} ->
        {:ok, _permission} = upsert_permission(name, %{description: description}, repo: repo)
      end)

      definitions
      |> Keyword.get(:roles, [])
      |> Enum.each(fn {name, description, permissions} ->
        {:ok, role} = upsert_role(name, %{description: description}, repo: repo)
        {:ok, _role} = sync_role_permissions(role, permissions, repo: repo)
      end)

      :ok
    end)
  end

  def normalize_permission(permission) when is_atom(permission), do: Atom.to_string(permission)
  def normalize_permission(permission) when is_binary(permission), do: permission
  def normalize_permission(permission), do: to_string(permission)

  def normalize_role(%Role{name: name}), do: name
  def normalize_role(role) when is_atom(role), do: Atom.to_string(role)
  def normalize_role(role) when is_binary(role), do: role
  def normalize_role(role), do: to_string(role)

  defp repo(opts), do: Keyword.get(opts, :repo) || Config.repo!()

  defp get_role(%Role{} = role, _repo, _tenant_id), do: role

  defp get_role(role_ref, repo, tenant_id) when is_binary(role_ref) do
    case resolve_role_ids([role_ref], tenant_id, repo) do
      [role_id] -> repo.get(Role, role_id)
      [] -> nil
    end
  end

  defp resolve_permission_ids(permissions, repo) do
    permissions
    |> Enum.map(&permission_lookup_value/1)
    |> resolve_lookup_values(Permission, repo)
  end

  defp resolve_role_ids(roles, tenant_id, repo) do
    roles
    |> Enum.map(&role_lookup_value/1)
    |> resolve_lookup_values(Role, repo, tenant_id)
  end

  defp permission_lookup_value(%Permission{id: id}), do: {:id, id}
  defp permission_lookup_value(value) when is_atom(value), do: {:name, Atom.to_string(value)}
  defp permission_lookup_value(value) when is_binary(value), do: lookup_value(value)

  defp role_lookup_value(%Role{id: id}), do: {:id, id}
  defp role_lookup_value(value) when is_atom(value), do: {:name, Atom.to_string(value)}
  defp role_lookup_value(value) when is_binary(value), do: lookup_value(value)

  defp lookup_value(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:id, uuid}
      :error -> {:name, value}
    end
  end

  defp resolve_lookup_values(values, schema, repo, tenant_id \\ nil) do
    ids = values |> Enum.filter(&match?({:id, _}, &1)) |> Enum.map(fn {:id, id} -> id end)

    names =
      values |> Enum.filter(&match?({:name, _}, &1)) |> Enum.map(fn {:name, name} -> name end)

    ids_from_names =
      schema
      |> where([s], s.name in ^names)
      |> maybe_scope_roles(schema, tenant_id)
      |> select([s], s.id)
      |> repo.all()

    Enum.uniq(ids ++ ids_from_names)
  end

  defp maybe_scope_roles(query, Role, nil), do: where(query, [r], is_nil(r.tenant_id))

  defp maybe_scope_roles(query, Role, tenant_id) do
    where(query, [r], is_nil(r.tenant_id) or r.tenant_id == ^tenant_id)
  end

  defp maybe_scope_roles(query, _schema, _tenant_id), do: query

  defp insert_all_if_any(_repo, _schema, [], _opts), do: {0, nil}
  defp insert_all_if_any(repo, schema, entries, opts), do: repo.insert_all(schema, entries, opts)

  defp now, do: DateTime.utc_now(:microsecond)

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
