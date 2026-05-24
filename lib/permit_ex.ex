defmodule PermitEx do
  @moduledoc """
  Role and permission management for Ecto and Phoenix applications.

  `PermitEx` keeps the core authorization model intentionally small:
  users receive roles globally or inside an optional context, roles receive
  permissions, and permissions are checked against the current scope.
  """

  import Ecto.Query

  alias PermitEx.{Config, Permission, Role, RolePermission, UserRole}

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
    case can?(scope_or_permissions, permission) do
      true -> :ok
      false -> {:error, :unauthorized}
    end
  end

  @doc """
  Checks a permission and an optional resource policy.

  Pass a policy module with `:policy`. The policy module must implement
  `c:PermitEx.Policy.authorize/3`.
  """
  def allowed?(scope, permission, resource \\ nil, opts \\ []) do
    with true <- can?(scope, permission),
         :ok <- authorize_policy(scope, resource, Keyword.get(opts, :policy)) do
      true
    else
      _ -> false
    end
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

  @doc """
  Returns a map of role name to permission names for the given context.

  Useful for rendering admin permission matrices and exposing role definitions
  via API. Roles with no permissions appear with an empty list.

      PermitEx.role_matrix()
      #=> %{"admin" => ["orders:manage", "orders:view"], "viewer" => ["orders:view"]}

      PermitEx.role_matrix(workspace.id)
  """
  def role_matrix(context_id \\ nil, opts \\ []) do
    from(r in Role,
      left_join: rp in RolePermission,
      on: rp.role_id == r.id,
      left_join: p in Permission,
      on: p.id == rp.permission_id,
      order_by: [asc: r.name, asc: p.name],
      select: {r.name, p.name}
    )
    |> scope_roles(context_id)
    |> repo(opts).all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {role, perms} -> {role, Enum.reject(perms, &is_nil/1)} end)
  end

  @doc "Gets a permission by name."
  def get_permission_by_name(name, opts \\ []) when is_binary(name) do
    repo(opts).get_by(Permission, name: name)
  end

  @doc "Deletes a permission."
  def delete_permission(%Permission{} = permission, opts \\ []) do
    repo(opts).delete(permission)
  end

  @doc "Lists global roles and roles for the given context."
  def list_roles(context_id \\ nil, opts \\ []) do
    Role
    |> scope_roles(context_id)
    |> order_by([r], asc: r.name)
    |> preload([:role_permissions])
    |> repo(opts).all()
  end

  @doc "Gets a global or context-specific role by name."
  def get_role_by_name(name, context_id \\ nil, opts \\ []) when is_binary(name) do
    repo = repo(opts)

    case find_role_id({:name, name, name}, repo, context_id) do
      nil -> nil
      role_id -> repo.get(Role, role_id)
    end
  end

  @doc "Lists roles that belong to one context."
  def roles_for_context(context_id, opts \\ []) when is_binary(context_id) do
    Role
    |> where([r], r.context_id == ^context_id)
    |> order_by([r], asc: r.name)
    |> repo(opts).all()
  end

  @doc "Deletes a role."
  def delete_role(%Role{} = role, opts \\ []) do
    repo(opts).delete(role)
  end

  @doc "Lists permissions assigned to a role."
  def list_role_permissions(role_ref, opts \\ []) do
    repo = repo(opts)

    with %Role{} = role <- get_role(role_ref, repo, context_from_opts(opts)) do
      from(rp in RolePermission,
        join: p in Permission,
        on: p.id == rp.permission_id,
        where: rp.role_id == ^role.id,
        order_by: p.name,
        select: p
      )
      |> repo.all()
    else
      nil -> []
    end
  end

  @doc """
  Replaces all permissions assigned to a role.

  Accepts a role struct, role id, or role name. Permissions can be names, ids,
  atoms, or `%PermitEx.Permission{}` structs. Missing permissions return
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

  @doc "Lists user ids assigned to a role."
  def users_with_role(role_ref, context_id \\ nil, opts \\ []) do
    repo = repo(opts)

    with %Role{} = role <- get_role(role_ref, repo, context_id) do
      UserRole
      |> where([ur], ur.role_id == ^role.id)
      |> scope_user_roles(context_id)
      |> order_by([ur], asc: ur.user_id)
      |> select([ur], ur.user_id)
      |> repo.all()
    else
      nil -> []
    end
  end

  @doc "Lists role assignments for a user."
  def list_user_roles(user_id, context_id \\ nil, opts \\ []) do
    UserRole
    |> where([ur], ur.user_id == ^user_id)
    |> scope_user_roles(context_id)
    |> order_by([ur], asc: ur.role_id)
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

  @doc "Loads roles and permissions for a user in a single query."
  def scope_data_for(user_id, context_id \\ nil, opts \\ []) do
    rows =
      from(ur in UserRole,
        join: r in Role,
        on: r.id == ur.role_id,
        left_join: rp in RolePermission,
        on: rp.role_id == r.id,
        left_join: p in Permission,
        on: p.id == rp.permission_id,
        where: ur.user_id == ^user_id,
        select: {r, p.name}
      )
      |> scope_user_roles(context_id)
      |> repo(opts).all()

    roles = rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq_by(& &1.id)
    permissions = rows |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> MapSet.new()

    {roles, permissions}
  end

  @doc """
  Clones global role templates into a context.

  A global role is any role with `context_id == nil`. The cloned context role
  receives the same name, description, locked flag, and permissions. Existing
  context roles are updated idempotently.

      PermitEx.clone_roles_to_context(workspace.id)
      PermitEx.clone_roles_to_context(workspace.id, roles: ["admin", "viewer"])
  """
  def clone_roles_to_context(context_id, opts \\ []) when is_binary(context_id) do
    repo = repo(opts)
    role_names = Keyword.get(opts, :roles)

    repo.transaction(fn ->
      roles = list_global_role_templates(repo, role_names)
      permissions_by_role_id = batch_permission_names_for_roles(Enum.map(roles, & &1.id), repo)

      Enum.map(roles, fn role ->
        permission_names = Map.get(permissions_by_role_id, role.id, [])

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

      PermitEx.seed!(
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
    {id_lookups, name_lookups} = Enum.split_with(lookups, &match?({:id, _, _}, &1))

    found =
      Map.merge(
        batch_find_permissions_by_id(id_lookups, repo),
        batch_find_permissions_by_name(name_lookups, repo)
      )

    {ids, missing} =
      Enum.reduce(lookups, {[], []}, fn {kind, value, label}, {ids, missing} ->
        case Map.fetch(found, {kind, value}) do
          {:ok, id} -> {[id | ids], missing}
          :error -> {ids, [label | missing]}
        end
      end)

    resolved_or_missing(ids, missing, :permissions_not_found, allow_missing?)
  end

  defp resolve_role_lookups(lookups, repo, context_id, allow_missing?) do
    {id_lookups, name_lookups} = Enum.split_with(lookups, &match?({:id, _, _}, &1))

    found =
      Map.merge(
        batch_find_roles_by_id(id_lookups, repo),
        batch_find_roles_by_name(name_lookups, repo, context_id)
      )

    {ids, missing} =
      Enum.reduce(lookups, {[], []}, fn {kind, value, label}, {ids, missing} ->
        case Map.fetch(found, {kind, value}) do
          {:ok, id} -> {[id | ids], missing}
          :error -> {ids, [label | missing]}
        end
      end)

    resolved_or_missing(ids, missing, :roles_not_found, allow_missing?)
  end

  defp batch_find_permissions_by_id([], _repo), do: %{}

  defp batch_find_permissions_by_id(lookups, repo) do
    ids = Enum.map(lookups, fn {:id, id, _} -> id end)

    Permission
    |> where([p], p.id in ^ids)
    |> select([p], p.id)
    |> repo.all()
    |> Map.new(&{{:id, &1}, &1})
  end

  defp batch_find_permissions_by_name([], _repo), do: %{}

  defp batch_find_permissions_by_name(lookups, repo) do
    names = Enum.map(lookups, fn {:name, name, _} -> name end)

    Permission
    |> where([p], p.name in ^names)
    |> select([p], {p.name, p.id})
    |> repo.all()
    |> Map.new(fn {name, id} -> {{:name, name}, id} end)
  end

  defp batch_find_roles_by_id([], _repo), do: %{}

  defp batch_find_roles_by_id(lookups, repo) do
    ids = Enum.map(lookups, fn {:id, id, _} -> id end)

    Role
    |> where([r], r.id in ^ids)
    |> select([r], r.id)
    |> repo.all()
    |> Map.new(&{{:id, &1}, &1})
  end

  defp batch_find_roles_by_name([], _repo, _context_id), do: %{}

  defp batch_find_roles_by_name(lookups, repo, nil) do
    names = Enum.map(lookups, fn {:name, name, _} -> name end)

    Role
    |> where([r], r.name in ^names and is_nil(r.context_id))
    |> select([r], {r.name, r.id})
    |> repo.all()
    |> Map.new(fn {name, id} -> {{:name, name}, id} end)
  end

  defp batch_find_roles_by_name(lookups, repo, context_id) do
    names = Enum.map(lookups, fn {:name, name, _} -> name end)

    Role
    |> where([r], r.name in ^names and (r.context_id == ^context_id or is_nil(r.context_id)))
    |> select([r], {r.name, r.id, r.context_id})
    |> repo.all()
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {name, entries} ->
      {_, id, _} =
        Enum.min_by(entries, fn {_, _, ctx} ->
          case ctx do
            nil -> 1
            _ -> 0
          end
        end)

      {{:name, name}, id}
    end)
  end

  defp batch_permission_names_for_roles([], _repo), do: %{}

  defp batch_permission_names_for_roles(role_ids, repo) do
    from(rp in RolePermission,
      join: p in Permission,
      on: p.id == rp.permission_id,
      where: rp.role_id in ^role_ids,
      select: {rp.role_id, p.name}
    )
    |> repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
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

  defp authorize_policy(_scope, _resource, nil), do: :ok

  defp authorize_policy(scope, resource, policy) when is_atom(policy) do
    case policy.authorize(scope, resource, []) do
      :ok -> :ok
      true -> :ok
      false -> {:error, :unauthorized}
      {:error, _reason} = error -> error
    end
  end

  defp resolved_or_missing(ids, [], _reason, _allow_missing?),
    do: {:ok, ids |> Enum.reverse() |> Enum.uniq()}

  defp resolved_or_missing(ids, _missing, _reason, true),
    do: {:ok, ids |> Enum.reverse() |> Enum.uniq()}

  defp resolved_or_missing(_ids, missing, reason, false) do
    {:error, {reason, missing |> Enum.reverse() |> Enum.uniq()}}
  end

  defp insert_all_if_any(_repo, _schema, [], _opts), do: {0, nil}
  defp insert_all_if_any(repo, schema, entries, opts), do: repo.insert_all(schema, entries, opts)

  defp now, do: DateTime.utc_now(:microsecond)

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
