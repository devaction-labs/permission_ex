defmodule PermissionEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :permission_ex,
      version: "0.1.0",
      elixir: "~> 1.19",
      description: description(),
      package: package(),
      source_url: "https://github.com/devaction-labs/permission_ex",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PermissionEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.13"}
    ]
  end

  defp description do
    "Role and permission management for Ecto and Phoenix applications."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/devaction-labs/permission_ex"}
    ]
  end
end
