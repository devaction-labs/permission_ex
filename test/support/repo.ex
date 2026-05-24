defmodule PermissionEx.TestRepo do
  use Ecto.Repo,
    otp_app: :permission_ex,
    adapter: Ecto.Adapters.Postgres
end
