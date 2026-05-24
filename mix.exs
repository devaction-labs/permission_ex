defmodule PermissionEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :permission_ex,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      source_url: "https://github.com/devaction-labs/permission_ex",
      homepage_url: "https://github.com/devaction-labs/permission_ex",
      docs: docs(),
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
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0", only: :test},
      {:plug, "~> 1.18", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp description do
    "Role and permission management for Ecto and Phoenix applications."
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md docs),
      links: %{"GitHub" => "https://github.com/devaction-labs/permission_ex"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "docs/phoenix.md",
        "docs/api.md",
        "docs/testing.md",
        "docs/use-nexus.md"
      ],
      groups_for_extras: [
        Guides: ~r/docs\/.*/
      ],
      source_ref: "v0.1.0",
      source_url: "https://github.com/devaction-labs/permission_ex"
    ]
  end
end
