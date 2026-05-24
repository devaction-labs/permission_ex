defmodule PermissionEx.Scope do
  @moduledoc """
  Authorization scope loaded from PermissionEx role assignments.

  Use this struct directly or merge its `roles` and `permissions` into your
  application's own Phoenix scope.
  """

  alias PermissionEx.Role

  defstruct user_id: nil, context_id: nil, roles: [], permissions: MapSet.new(), assigns: %{}

  @type t :: %__MODULE__{
          user_id: Ecto.UUID.t() | nil,
          context_id: Ecto.UUID.t() | nil,
          roles: [Role.t()],
          permissions: MapSet.t(String.t()),
          assigns: map()
        }

  @doc """
  Builds a `%PermissionEx.Scope{}` for the user and optional context.

  Accepts ids, structs with an `:id` field, or maps with an `"id"` key.
  """
  def for_user(user, context \\ nil, opts \\ []) do
    user_id = id_from(user)
    context_id = id_from(context)

    roles = PermissionEx.roles_for(user_id, context_id, opts)
    permissions = PermissionEx.permissions_for(user_id, context_id, opts)

    %__MODULE__{
      user_id: user_id,
      context_id: context_id,
      roles: roles,
      permissions: permissions
    }
  end

  @doc """
  Merges PermissionEx authorization data into an existing map or struct.
  """
  def put_permission_data(scope, user, context \\ nil, opts \\ []) do
    permission_scope = for_user(user, context, opts)

    scope
    |> put_value(:roles, permission_scope.roles)
    |> put_value(:permissions, permission_scope.permissions)
  end

  defp id_from(%{id: id}), do: id
  defp id_from(%{"id" => id}), do: id
  defp id_from(id) when is_binary(id), do: id
  defp id_from(nil), do: nil

  defp put_value(%_struct{} = scope, key, value) do
    struct(scope, %{key => value})
  end

  defp put_value(scope, key, value) when is_map(scope) do
    Map.put(scope, key, value)
  end
end
