defmodule PermissionEx.RolePermission do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "permission_ex_role_permissions" do
    belongs_to(:role, PermissionEx.Role, primary_key: true)
    belongs_to(:permission, PermissionEx.Permission, primary_key: true)

    timestamps(updated_at: false)
  end

  def changeset(role_permission, attrs) do
    role_permission
    |> cast(attrs, [:role_id, :permission_id])
    |> validate_required([:role_id, :permission_id])
    |> unique_constraint([:role_id, :permission_id])
  end
end
