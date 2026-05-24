defmodule PermitEx.RolePermission do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "permit_ex_role_permissions" do
    belongs_to(:role, PermitEx.Role, primary_key: true)
    belongs_to(:permission, PermitEx.Permission, primary_key: true)

    timestamps(updated_at: false)
  end

  def changeset(role_permission, attrs) do
    role_permission
    |> cast(attrs, [:role_id, :permission_id])
    |> validate_required([:role_id, :permission_id])
    |> unique_constraint([:role_id, :permission_id])
  end
end
