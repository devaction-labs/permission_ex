defmodule PermissionEx.Role do
  @moduledoc """
  Ecto schema for system and tenant roles.

  Roles with `tenant_id == nil` are global templates. Roles with `tenant_id`
  belong to one tenant/workspace and can be customized independently.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "permission_ex_roles" do
    field(:name, :string)
    field(:description, :string)
    field(:tenant_id, Ecto.UUID)
    field(:locked, :boolean, default: false)

    has_many(:role_permissions, PermissionEx.RolePermission)
    has_many(:permissions, through: [:role_permissions, :permission])
    has_many(:user_roles, PermissionEx.UserRole)

    timestamps()
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :tenant_id, :locked])
    |> validate_required([:name])
    |> validate_format(:name, ~r/\A[a-z0-9_]+\z/, message: "must use slug format")
    |> validate_length(:name, max: 80)
    |> unique_constraint(:name, name: :permission_ex_roles_global_name_index)
    |> unique_constraint([:name, :tenant_id], name: :permission_ex_roles_tenant_name_index)
  end
end
