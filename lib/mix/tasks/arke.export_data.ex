defmodule Mix.Tasks.Arke.ExportData do
  @moduledoc """
  Export data from a given project in the database and save them in json file.
    It exports, by default, all the arkes,groups, parameters and permissions

  ## Examples

      $ mix arke.export_data --project my_project1 --p myproject2
      $ mix arke.export_data --project my_project --arke

  ## Command line options

  * `--project` - The id of the project used to export data.
  * `--arke` - Export only the arkes
  * `--group` - Export only the groups
  * `--parameter` - Export only the parameters
  * `--split_file` - Write different files for arkes,groups,parameters and links
  * `--persistence` - The persistence to use. One of:
      * `arke_postgres` - via https://github.com/elixir-ecto/postgrex (Default)
  """

  use Mix.Task
  alias Arke.QueryManager
  alias Arke.LinkManager
  alias Arke.Utils.ErrorGenerator, as: Error
  alias Arke.Boundary.{ArkeManager}

  alias Arke.Core.Unit
  @decode_keys [:arke, :parameter, :group, :link]
  @shortdoc "Export data from a project"
  @persistence_repo ["arke_postgres"]

  @switches [
    project: :string,
    arke: :boolean,
    parameter: :boolean,
    splitfile: :boolean,
    group: :boolean,
    persistence: :string
  ]
  @aliases [
    p: :project,
    a: :arke,
    g: :group,
    sf: :splitfile,
    pr: :parameter,
    ps: :persistence
  ]

  @impl true
  def run(args) do
    case OptionParser.parse!(args, strict: @switches, aliases: @aliases) do
      {[], _opts} ->
        Mix.Tasks.Help.run(["arke.export_data"])

      {opts, []} ->
        persistence = parse_persistence!(opts[:persistence] || "arke_postgres")

        (app_to_start(persistence) ++ [:arke])
        |> Enum.each(&Application.ensure_all_started/1)

        repo_module = Application.get_env(:arke, :persistence)[String.to_atom(persistence)][:repo]
        Mix.shell().info("--- Starting repo --- ")

        case start_repo!(repo_module) do
          {:ok, pid} ->
            opts |> export_data(persistence)
            Process.exit(pid, :normal)
            :ok

          {:error, _} ->
            opts |> export_data(persistence)
            :ok
        end
    end
  end

  defp app_to_start("arke_postgres"), do: [:ecto_sql, :postgrex]
  defp parse_persistence!(ps) when ps in @persistence_repo, do: ps

  defp parse_persistence!(ps),
    do:
      Mix.raise(
        "Invalid persistence: `#{ps}`\nSupported persistence are: #{Enum.join(@persistence_repo, " | ")}"
      )

  defp write_to_file(project, arke_id, data) do
    {:ok, datetime} =
      Arke.Utils.DatetimeHandler.now(:datetime)
      |> Arke.Utils.DatetimeHandler.format("{ISO:Basic:Z}")

    dir_path = "export/arke_export_data/#{project}/#{datetime}"
    arke_id_str = to_string(arke_id)
    path = "#{dir_path}/#{arke_id_str}.json"
    Mix.shell().info("--- Writing data to #{path} for #{arke_id_str}  --- ")
    File.mkdir_p!(dir_path)
    {:ok, body} = Jason.encode(data)
    {:ok, file} = File.open(path, [:append, :utf8])
    IO.write(file, body)
    File.close(file)
  end

  defp start_repo!(nil),
    do:
      Mix.raise(
        "Invalid repo module in arke configuration. Please provide a valid module accordingly to the persistence supported"
      )

  # this is for arke_postgres
  defp start_repo!(repo_module) do
    repo_module.start_link()
  end

  defp start_manager!(nil),
    do:
      Mix.raise(
        "Missing `init` function in arke.persistence configuration. Please provide a valid function accordingly to the persistence supported"
      )

  # this is for arke_postgres
  defp start_manager!(function), do: function.()

  defp export_data(opts, persistence) do
    start_manager!(Application.get_env(:arke, :persistence)[String.to_atom(persistence)][:init])
    project = String.to_atom(opts[:project]) || :arke_system
    split_file = opts[:splitfile] || false
    export_data = Arke.Utils.Export.get_db_structure(project, opts)

    if split_file do
      write_to_file(project, :arke, %{arke: export_data.arke})
      write_to_file(project, :group, %{group: export_data.group})
      write_to_file(project, :parameter, %{parameter: export_data.parameter})
      write_to_file(project, :link, %{link: export_data.link})
    else
      write_to_file(project, :all, export_data)
    end

    Mix.shell().info(
      "--- All data has been exported. Keep in mind that if you want to use them in the `arke.seed_project` task
       you must move them under the `registry` folder --- "
    )
  end
end
