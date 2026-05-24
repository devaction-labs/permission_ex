defmodule PermissionEx.UserRole do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "permission_ex_user_roles" do
    field(:user_id, Ecto.UUID, primary_key: true)
    field(:tenant_id, Ecto.UUID, primary_key: true)

    belongs_to(:role, PermissionEx.Role, primary_key: true)

    timestamps(updated_at: false)
  end

  def changeset(user_role, attrs) do
    user_role
    |> cast(attrs, [:user_id, :tenant_id, :role_id])
    |> validate_required([:user_id, :tenant_id, :role_id])
    |> unique_constraint([:user_id, :tenant_id, :role_id])
  end
end
