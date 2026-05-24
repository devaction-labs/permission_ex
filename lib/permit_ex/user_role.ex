defmodule PermitEx.UserRole do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "permit_ex_user_roles" do
    field(:user_id, Ecto.UUID)
    field(:context_id, Ecto.UUID)

    belongs_to(:role, PermitEx.Role)

    timestamps(updated_at: false)
  end

  def changeset(user_role, attrs) do
    user_role
    |> cast(attrs, [:user_id, :context_id, :role_id])
    |> validate_required([:user_id, :role_id])
    |> unique_constraint([:user_id, :role_id],
      name: :permit_ex_user_roles_global_role_index
    )
    |> unique_constraint([:user_id, :context_id, :role_id],
      name: :permit_ex_user_roles_context_role_index
    )
  end
end
