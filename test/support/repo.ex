defmodule PermitEx.TestRepo do
  use Ecto.Repo,
    otp_app: :permit_ex,
    adapter: Ecto.Adapters.Postgres
end
