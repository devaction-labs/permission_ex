defmodule Mix.Tasks.PermissionEx.Install do
  @moduledoc """
  Installs PermissionEx migrations into the host application.

      mix permission_ex.install
  """

  use Mix.Task

  @shortdoc "Copies PermissionEx migrations"

  @impl Mix.Task
  def run(_args) do
    Mix.Project.get!()

    target_dir = Path.join(["priv", "repo", "migrations"])
    File.mkdir_p!(target_dir)

    timestamp = timestamp()
    filename = "#{timestamp}_create_permission_ex_tables.exs"
    target = Path.join(target_dir, filename)

    if File.exists?(target) do
      Mix.shell().info("Migration already exists: #{target}")
    else
      template = template_path()
      module = "CreatePermissionExTables"
      contents = template |> File.read!() |> EEx.eval_string(module: module)
      File.write!(target, contents)
      Mix.shell().info("Created #{target}")
    end
  end

  defp template_path do
    :permission_ex
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("templates/create_permission_ex_tables.exs")
  end

  defp timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()

    [year, month, day, hour, minute, second]
    |> Enum.map_join(&(&1 |> Integer.to_string() |> String.pad_leading(2, "0")))
  end
end
