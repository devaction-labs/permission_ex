defmodule PermissionEx do
  @moduledoc """
  Role and permission management for Ecto and Phoenix applications.

  `PermissionEx` keeps the core authorization model intentionally small:
  users receive roles globally or inside an optional context, roles receive
  permissions, and permissions are checked against the current scope.
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

  @doc "Creates a global role or a context role when `context_id` is present."
  def create_role(attrs, opts \\ []) do
    repo(opts).insert(Role.changeset(%Role{}, stringify_keys(attrs)))
  end

  @doc "Creates or updates a global role by name."
  def upsert_role(name, attrs \\ %{}, opts \\ []) when is_binary(name) do
    attrs = attrs |> stringify_keys() |> Map.put("name", name)

    repo(opts).insert(
      Role.changeset(%Role{}, attrs),
      on_conflict: {:replace, [:description, :locked, :updated_at]},
      conflict_target: {:unsafe_fragment, "(name) WHERE context_id IS NULL"}
    )
  end

  @doc "Creates or updates a context role by name."
  def upsert_context_role(name, context_id, attrs \\ %{}, opts \\ [])
      when is_binary(name) and is_binary(context_id) do
    attrs =
      attrs |> stringify_keys() |> Map.put("name", name) |> Map.put("context_id", context_id)

    repo(opts).insert(
      Role.changeset(%Role{}, attrs),
      on_conflict: {:replace, [:description, :locked, :updated_at]},
      conflict_target: {:unsafe_fragment, "(context_id, name) WHERE context_id IS NOT NULL"}
    )
  end

  @doc "Lists permissions ordered by name."
  def list_permissions(opts \\ []) do
    repo(opts).all(from(p in Permission, order_by: p.name))
  end

  @doc "Lists global roles and roles for the given context."
  def list_roles(context_id \\ nil, opts \\ []) do
    Role
    |> scope_roles(context_id)
    |> order_by([r], asc: r.name)
    |> preload([:role_permissions])
    |> repo(opts).all()
  end

  @doc """
  Replaces all permissions assigned to a role.

  Accepts a role struct, role id, or role name. Permissions can be names, ids,
  atoms, or `%PermissionEx.Permission{}` structs. Missing permissions return
  `{:error, {:permissions_not_found, missing}}` unless `allow_missing?: true`
  is passed.
  """
  def sync_role_permissions(role_ref, permissions, opts \\ []) when is_list(permissions) do
    repo = repo(opts)

    with %Role{} = role <- get_role(role_ref, repo, context_from_opts(opts)) do
      case resolve_permission_ids(permissions, repo, opts) do
        {:ok, permission_ids} ->
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

        {:error, _reason} = error ->
          error
      end
    else
      nil -> {:error, :role_not_found}
    end
  end

  @doc "Alias for `sync_role_permissions/3`."
  def sync_permissions(role_ref, permissions, opts \\ []),
    do: sync_role_permissions(role_ref, permissions, opts)

  @doc "Assigns one role to a user in a context."
  def assign_role(user_id, role_or_id, context_id \\ nil, opts \\ []) do
    repo = repo(opts)

    case resolve_role_ids([role_or_id], context_id, repo, opts) do
      {:ok, [role_id]} ->
        %UserRole{}
        |> UserRole.changeset(%{user_id: user_id, role_id: role_id, context_id: context_id})
        |> repo.insert(
          on_conflict: :nothing,
          conflict_target: user_role_conflict_target(context_id)
        )

      {:error, {:roles_not_found, _missing}} = error ->
        error
    end
  end

  @doc "Assigns many roles to a user without removing existing roles."
  def assign_roles(user_id, roles, context_id \\ nil, opts \\ []) when is_list(roles) do
    repo = repo(opts)

    case resolve_role_ids(roles, context_id, repo, opts) do
      {:ok, role_ids} ->
        entries =
          Enum.map(role_ids, fn role_id ->
            %{user_id: user_id, context_id: context_id, role_id: role_id, inserted_at: now()}
          end)

        {count, _} =
          insert_all_if_any(repo, UserRole, entries,
            on_conflict: :nothing,
            conflict_target: user_role_conflict_target(context_id)
          )

        {:ok, count}

      {:error, {:roles_not_found, _missing}} = error ->
        error
    end
  end

  @doc "Removes one role from a user in a context."
  def revoke_role(user_id, role_or_id, context_id \\ nil, opts \\ []) do
    repo = repo(opts)

    case resolve_role_ids([role_or_id], context_id, repo, opts) do
      {:ok, [role_id]} ->
        {count, _} =
          UserRole
          |> where([ur], ur.user_id == ^user_id and ur.role_id == ^role_id)
          |> scope_user_roles(context_id)
          |> repo.delete_all()

        {:ok, count}

      {:error, {:roles_not_found, _missing}} = error ->
        error
    end
  end

  @doc """
  Replaces all roles assigned to a user in a context.

  This is the Spatie-style `syncRoles` equivalent. It accepts role structs, ids
  or names and leaves the user with exactly the resolved roles.
  """
  def sync_user_roles(user_id, roles, context_id \\ nil, opts \\ []) when is_list(roles) do
    repo = repo(opts)

    case resolve_role_ids(roles, context_id, repo, opts) do
      {:ok, role_ids} ->
        repo.transaction(fn ->
          UserRole
          |> where([ur], ur.user_id == ^user_id)
          |> scope_user_roles(context_id)
          |> repo.delete_all()

          entries =
            Enum.map(role_ids, fn role_id ->
              %{user_id: user_id, context_id: context_id, role_id: role_id, inserted_at: now()}
            end)

          {count, _} =
            insert_all_if_any(repo, UserRole, entries,
              on_conflict: :nothing,
              conflict_target: user_role_conflict_target(context_id)
            )

          count
        end)

      {:error, {:roles_not_found, _missing}} = error ->
        error
    end
  end

  @doc "Alias for `sync_user_roles/4`."
  def sync_roles(user_id, roles, context_id \\ nil, opts \\ []),
    do: sync_user_roles(user_id, roles, context_id, opts)

  @doc "Loads roles assigned to a user in a context."
  def roles_for(user_id, context_id \\ nil, opts \\ []) do
    from(ur in UserRole,
      join: r in Role,
      on: r.id == ur.role_id,
      where: ur.user_id == ^user_id,
      order_by: r.name,
      select: r
    )
    |> scope_user_roles(context_id)
    |> repo(opts).all()
  end

  @doc "Loads permission names for the user in a context."
  def permissions_for(user_id, context_id \\ nil, opts \\ []) do
    from(ur in UserRole,
      join: rp in RolePermission,
      on: rp.role_id == ur.role_id,
      join: p in Permission,
      on: p.id == rp.permission_id,
      where: ur.user_id == ^user_id,
      select: p.name
    )
    |> scope_user_roles(context_id)
    |> repo(opts).all()
    |> MapSet.new()
  end

  @doc """
  Clones global role templates into a context.

  A global role is any role with `context_id == nil`. The cloned context role
  receives the same name, description, locked flag, and permissions. Existing
  context roles are updated idempotently.

      PermissionEx.clone_roles_to_context(workspace.id)
      PermissionEx.clone_roles_to_context(workspace.id, roles: ["admin", "viewer"])
  """
  def clone_roles_to_context(context_id, opts \\ []) when is_binary(context_id) do
    repo = repo(opts)
    role_names = Keyword.get(opts, :roles)

    repo.transaction(fn ->
      list_global_role_templates(repo, role_names)
      |> Enum.map(fn role ->
        permission_names = permission_names_for_role(role.id, repo)

        {:ok, context_role} =
          upsert_context_role(
            role.name,
            context_id,
            %{description: role.description, locked: role.locked},
            repo: repo
          )

        {:ok, _role} = sync_role_permissions(context_role, permission_names, repo: repo)
        context_role
      end)
    end)
  end

  @doc "Alias for `clone_roles_to_context/2`."
  def sync_context_roles_from_templates(context_id, opts \\ []),
    do: clone_roles_to_context(context_id, opts)

  @doc """
  Seeds permissions and roles in one transaction.

  Expected shape:

      PermissionEx.seed!(
        permissions: [
          {"orders:view", "View orders"},
          {"orders:manage", "Manage orders"}
        ],
        roles: [
          {"admin", "Context admin", ["orders:view", "orders:manage"]},
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

  defp context_from_opts(opts), do: Keyword.get(opts, :context_id, Keyword.get(opts, :tenant_id))

  defp scope_roles(query, nil), do: where(query, [r], is_nil(r.context_id))

  defp scope_roles(query, context_id) do
    where(query, [r], is_nil(r.context_id) or r.context_id == ^context_id)
  end

  defp scope_user_roles(query, nil), do: where(query, [ur], is_nil(ur.context_id))

  defp scope_user_roles(query, context_id) do
    where(query, [ur], ur.context_id == ^context_id)
  end

  defp user_role_conflict_target(nil) do
    {:unsafe_fragment, "(user_id, role_id) WHERE context_id IS NULL"}
  end

  defp user_role_conflict_target(_context_id) do
    {:unsafe_fragment, "(user_id, context_id, role_id) WHERE context_id IS NOT NULL"}
  end

  defp get_role(%Role{} = role, _repo, _context_id), do: role

  defp get_role(role_ref, repo, context_id) when is_binary(role_ref) do
    case resolve_role_ids([role_ref], context_id, repo, []) do
      {:ok, [role_id]} -> repo.get(Role, role_id)
      {:error, _reason} -> nil
    end
  end

  defp resolve_permission_ids(permissions, repo, opts) do
    permissions
    |> Enum.map(&permission_lookup/1)
    |> resolve_permission_lookups(repo, Keyword.get(opts, :allow_missing?, false))
  end

  defp resolve_role_ids(roles, context_id, repo, opts) do
    roles
    |> Enum.map(&role_lookup/1)
    |> resolve_role_lookups(repo, context_id, Keyword.get(opts, :allow_missing?, false))
  end

  defp permission_lookup(%Permission{id: id}), do: {:id, id, id}
  defp permission_lookup(value) when is_atom(value), do: {:name, Atom.to_string(value), value}

  defp permission_lookup(value) when is_binary(value) do
    {kind, resolved} = lookup_value(value)
    {kind, resolved, value}
  end

  defp role_lookup(%Role{id: id}), do: {:id, id, id}
  defp role_lookup(value) when is_atom(value), do: {:name, Atom.to_string(value), value}

  defp role_lookup(value) when is_binary(value) do
    {kind, resolved} = lookup_value(value)
    {kind, resolved, value}
  end

  defp lookup_value(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:id, uuid}
      :error -> {:name, value}
    end
  end

  defp resolve_permission_lookups(lookups, repo, allow_missing?) do
    {ids, missing} =
      Enum.reduce(lookups, {[], []}, fn lookup, {ids, missing} ->
        case find_permission_id(lookup, repo) do
          nil -> {ids, [lookup_label(lookup) | missing]}
          id -> {[id | ids], missing}
        end
      end)

    resolved_or_missing(ids, missing, :permissions_not_found, allow_missing?)
  end

  defp resolve_role_lookups(lookups, repo, context_id, allow_missing?) do
    {ids, missing} =
      Enum.reduce(lookups, {[], []}, fn lookup, {ids, missing} ->
        case find_role_id(lookup, repo, context_id) do
          nil -> {ids, [lookup_label(lookup) | missing]}
          id -> {[id | ids], missing}
        end
      end)

    resolved_or_missing(ids, missing, :roles_not_found, allow_missing?)
  end

  defp find_permission_id({:id, id, _label}, repo) do
    Permission
    |> where([p], p.id == ^id)
    |> select([p], p.id)
    |> repo.one()
  end

  defp find_permission_id({:name, name, _label}, repo) do
    Permission
    |> where([p], p.name == ^name)
    |> select([p], p.id)
    |> repo.one()
  end

  defp find_role_id({:id, id, _label}, repo, _context_id) do
    Role
    |> where([r], r.id == ^id)
    |> select([r], r.id)
    |> repo.one()
  end

  defp find_role_id({:name, name, _label}, repo, nil) do
    Role
    |> where([r], r.name == ^name and is_nil(r.context_id))
    |> select([r], r.id)
    |> repo.one()
  end

  defp find_role_id({:name, name, _label}, repo, context_id) do
    Role
    |> where([r], r.name == ^name and (r.context_id == ^context_id or is_nil(r.context_id)))
    |> order_by([r], asc: is_nil(r.context_id))
    |> limit(1)
    |> select([r], r.id)
    |> repo.one()
  end

  defp list_global_role_templates(repo, nil) do
    Role
    |> where([r], is_nil(r.context_id))
    |> order_by([r], asc: r.name)
    |> repo.all()
  end

  defp list_global_role_templates(repo, role_names) when is_list(role_names) do
    normalized_names = Enum.map(role_names, &normalize_role/1)

    Role
    |> where([r], is_nil(r.context_id) and r.name in ^normalized_names)
    |> order_by([r], asc: r.name)
    |> repo.all()
  end

  defp permission_names_for_role(role_id, repo) do
    from(rp in RolePermission,
      join: p in Permission,
      on: p.id == rp.permission_id,
      where: rp.role_id == ^role_id,
      select: p.name
    )
    |> repo.all()
  end

  defp resolved_or_missing(ids, [], _reason, _allow_missing?),
    do: {:ok, ids |> Enum.reverse() |> Enum.uniq()}

  defp resolved_or_missing(ids, _missing, _reason, true),
    do: {:ok, ids |> Enum.reverse() |> Enum.uniq()}

  defp resolved_or_missing(_ids, missing, reason, false) do
    {:error, {reason, missing |> Enum.reverse() |> Enum.uniq()}}
  end

  defp lookup_label({_kind, _value, label}), do: label

  defp insert_all_if_any(_repo, _schema, [], _opts), do: {0, nil}
  defp insert_all_if_any(repo, schema, entries, opts), do: repo.insert_all(schema, entries, opts)

  defp now, do: DateTime.utc_now(:microsecond)

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
