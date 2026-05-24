if Code.ensure_loaded?(Absinthe.Resolution) do
  defmodule PermitEx.Absinthe.RequireAuthorization do
    @moduledoc """
    Absinthe middleware for enforcing PermitEx roles and permissions.

        object :orders do
          field :create_order, :order do
            middleware PermitEx.Absinthe.RequireAuthorization, permission: "orders:manage"
            resolve &OrderResolver.create/2
          end
        end

    Options:

    - `:permission` - one required permission
    - `:role` - one required role
    - `:any_permissions` - at least one permission must match
    - `:all_permissions` - every permission must match
    - `:any_roles` - at least one role must match
    - `:all_roles` - every role must match
    - `:assign_key` - key in `resolution.context` holding the scope. Defaults to `:current_scope`.
    - `:message` - error message returned on denial. Defaults to `"forbidden"`.
    """

    @behaviour Absinthe.Middleware

    @impl Absinthe.Middleware
    def call(resolution, opts) do
      assign_key = Keyword.get(opts, :assign_key, :current_scope)
      scope = Map.get(resolution.context, assign_key)

      case PermitEx.Guard.authorized?(scope, opts) do
        true ->
          resolution

        false ->
          message = Keyword.get(opts, :message, "forbidden")
          Absinthe.Resolution.put_result(resolution, {:error, message})
      end
    end
  end
end
