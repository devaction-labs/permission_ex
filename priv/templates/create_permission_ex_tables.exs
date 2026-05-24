defmodule <%= module %> do
  use Ecto.Migration

  def change do
    create table(:permission_ex_permissions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:permission_ex_permissions, [:name])

    create table(:permission_ex_roles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :tenant_id, :uuid
      add :locked, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:permission_ex_roles, [:name],
             where: "tenant_id IS NULL",
             name: :permission_ex_roles_global_name_index
           )

    create unique_index(:permission_ex_roles, [:tenant_id, :name],
             where: "tenant_id IS NOT NULL",
             name: :permission_ex_roles_tenant_name_index
           )

    create table(:permission_ex_role_permissions, primary_key: false) do
      add :role_id, references(:permission_ex_roles, type: :uuid, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :permission_id,
          references(:permission_ex_permissions, type: :uuid, on_delete: :delete_all),
          null: false,
          primary_key: true

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:permission_ex_role_permissions, [:permission_id])

    create table(:permission_ex_user_roles, primary_key: false) do
      add :user_id, :uuid, null: false, primary_key: true
      add :tenant_id, :uuid, null: false, primary_key: true

      add :role_id, references(:permission_ex_roles, type: :uuid, on_delete: :delete_all),
        null: false,
        primary_key: true

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:permission_ex_user_roles, [:user_id, :tenant_id, :role_id])
    create index(:permission_ex_user_roles, [:role_id])
    create index(:permission_ex_user_roles, [:tenant_id])
  end
end
