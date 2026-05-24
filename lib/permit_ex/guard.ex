defmodule PermitEx.Guard do
  @moduledoc """
  Shared authorization checks used by Plug and LiveView adapters.
  """

  @doc """
  Returns true when all configured role and permission checks pass.

  Supported options:

  - `:permission` - one required permission
  - `:role` - one required role
  - `:any_permissions` - at least one permission must match
  - `:all_permissions` - every permission must match
  - `:any_roles` - at least one role must match
  - `:all_roles` - every role must match
  """
  def authorized?(scope, opts) when is_list(opts) do
    permissions = all_values(opts, :permission, :all_permissions)
    any_permissions = List.wrap(Keyword.get(opts, :any_permissions, []))
    roles = all_values(opts, :role, :all_roles)
    any_roles = List.wrap(Keyword.get(opts, :any_roles, []))

    all_permissions?(scope, permissions) and
      any_permissions?(scope, any_permissions) and
      all_roles?(scope, roles) and
      any_roles?(scope, any_roles)
  end

  def authorized?(scope, permission) when is_binary(permission) or is_atom(permission) do
    PermitEx.can?(scope, permission)
  end

  defp all_values(opts, single_key, many_key) do
    opts
    |> Keyword.get_values(single_key)
    |> Kernel.++(List.wrap(Keyword.get(opts, many_key, [])))
  end

  defp all_permissions?(_scope, []), do: true

  defp all_permissions?(scope, permissions),
    do: Enum.all?(permissions, &PermitEx.can?(scope, &1))

  defp any_permissions?(_scope, []), do: true

  defp any_permissions?(scope, permissions),
    do: Enum.any?(permissions, &PermitEx.can?(scope, &1))

  defp all_roles?(_scope, []), do: true
  defp all_roles?(scope, roles), do: Enum.all?(roles, &PermitEx.has_role?(scope, &1))

  defp any_roles?(_scope, []), do: true
  defp any_roles?(scope, roles), do: Enum.any?(roles, &PermitEx.has_role?(scope, &1))
end
