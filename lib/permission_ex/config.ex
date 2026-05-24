defmodule PermissionEx.Config do
  @moduledoc false

  @app :permission_ex

  def repo do
    Application.get_env(@app, :repo)
  end

  def repo! do
    repo() || raise ArgumentError, "configure :permission_ex, repo: MyApp.Repo"
  end

  def context_key do
    Application.get_env(@app, :context_key, :context_id)
  end

  def user_key do
    Application.get_env(@app, :user_key, :user_id)
  end
end
