defmodule Mix.Tasks.PermitEx.Install do
  @moduledoc """
  Installs PermitEx migrations into the host application.

      mix permit_ex.install
      mix permit_ex.install --migrations-path priv/repo/migrations
  """

  use Mix.Task

  @shortdoc "Copies PermitEx migrations"

  @switches [migrations_path: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Project.get!()

    {opts, _} = OptionParser.parse!(args, strict: @switches)
    target_dir = Keyword.get(opts, :migrations_path, Path.join(["priv", "repo", "migrations"]))

    File.mkdir_p!(target_dir)

    case existing_migration(target_dir) do
      {:ok, path} ->
        Mix.shell().info("Migration already exists: #{path}")

      :none ->
        path = write_migration(target_dir)
        Mix.shell().info("Created #{path}")
        Mix.shell().info("Run `mix ecto.migrate` to apply it.")
    end
  end

  defp existing_migration(dir) do
    case Path.wildcard(Path.join(dir, "*_create_permit_ex_tables.exs")) do
      [path | _] -> {:ok, path}
      [] -> :none
    end
  end

  defp write_migration(dir) do
    filename = "#{timestamp()}_create_permit_ex_tables.exs"
    path = Path.join(dir, filename)
    module = "CreatePermitExTables"

    contents =
      template_path()
      |> File.read!()
      |> EEx.eval_string(module: module)

    File.write!(path, contents)
    Mix.Task.run("format", [path])
    path
  end

  defp template_path do
    :permit_ex
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("templates/create_permit_ex_tables.exs")
  end

  defp timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()

    [year, month, day, hour, minute, second]
    |> Enum.map_join(&(&1 |> Integer.to_string() |> String.pad_leading(2, "0")))
  end
end
