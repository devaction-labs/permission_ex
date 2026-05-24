defmodule PermitEx.Policy do
  @moduledoc """
  Behaviour for optional resource-level policy checks.

  RBAC answers whether a scope has a permission. A policy can answer whether
  that scope may use the permission against a specific resource.
  """

  @callback authorize(scope :: term(), resource :: term(), opts :: keyword()) ::
              :ok | true | false | {:error, term()}
end
