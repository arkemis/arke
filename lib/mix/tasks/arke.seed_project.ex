defmodule Mix.Tasks.Arke.SeedProject do
  @moduledoc """
  Seed a given project in the database using file data.

  ## Examples

      $ mix arke.seed_project --project my_project1 --p myproject2
      $ mix arke.seed_project --all

  ## Command line options

  * `--project` - The id of the project to seed. It could be passed multiple times
  * `--all` - Seed all the project found in the database
  * `--format` -The format of the file used to import the data.One of:
      * `json` Default
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
  @supported_format ["json", "yml", "yaml"]
  @shortdoc "Seed a project"
  @persistence_repo ["arke_postgres"]

  @switches [
    project: :string,
    all: :boolean,
    format: :string,
    persistence: :string
  ]
  @aliases [
    p: :project,
    A: :all,
    f: :format,
    ps: :persistence
  ]

  @impl true
  def run(args) do
    case OptionParser.parse!(args, strict: @switches, aliases: @aliases) do
      {[], _opts} ->
        Mix.Tasks.Help.run(["arke.seed_project"])

      {opts, []} ->
        persistence = parse_persistence!(opts[:persistence] || "arke_postgres")

        (app_to_start(persistence) ++ [:arke])
        |> Enum.each(&Application.ensure_all_started/1)

        repo_module = Application.get_env(:arke, :persistence)[String.to_atom(persistence)][:repo]
        Mix.shell().info("--- Starting repo --- ")

        case start_repo(repo_module) do
          {:ok, pid} ->
            opts |> parse_file()
            Process.exit(pid, :normal)
            :ok

          {:error, _} ->
            opts |> parse_file()
            :ok
        end
    end
  end

  defp app_to_start("arke_postgres"), do: [:ecto_sql, :postgrex, :arke_postgres]
  defp parse_persistence!(ps) when ps in @persistence_repo, do: ps

  defp parse_persistence!(ps),
    do:
      Mix.raise(
        "Invalid persistence: `#{ps}`\nSupported persistence are: #{Enum.join(@persistence_repo, " | ")}"
      )

  defp check_file(_arke_id, _project, []), do: nil

  defp check_file(arke_id, project, data) do
    unless Mix.env() == :test do
      {:ok, datetime} =
        Arke.Utils.DatetimeHandler.now(:datetime)
        |> Arke.Utils.DatetimeHandler.format("{ISO:Basic:Z}")

      dir_path = "log/arke_seed_project/#{project}"
      path = "#{dir_path}/#{datetime}_#{to_string(arke_id)}.log"
      Mix.shell().info("--- Writing errors to #{path} --- ")

      File.mkdir_p!(dir_path)
      write_log_to_file(path, data)
    end
  end

  defp write_log_to_file(path, data) do
    {:ok, body} = Jason.encode(data)
    {:ok, file} = File.open(path, [:append])
    IO.write(file, body)
    File.close(file)
  end

  defp start_repo(nil),
    do:
      Mix.raise(
        "Invalid repo module in arke configuration. Please provide a valid module accordingly to the persistence supported"
      )

  # this is for arke_postgres
  defp start_repo(repo_module) do
    repo_module.start_link()
  end

  defp parse_file(opts) do
    Mix.shell().info("--- Parsing registry files --- ")
    format = opts[:format] || "json"
    check_format!(format)
    all = opts[:all] || false

    # get core file to decode (arke) and append all other arke_deps registry files
    core_registry = arke_registry("arke", format, "all")
    core_data = parse(core_registry, format)

    arke_deps_registry = get_arke_deps_registry(format, "all")
    arke_deps_data = parse(arke_deps_registry, format)
    Mix.shell().info("--- Get core data ---")
    core_parameter = Map.get(core_data, :parameter, []) ++ Map.get(arke_deps_data, :parameter, [])
    core_arke = Map.get(core_data, :arke, []) ++ Map.get(arke_deps_data, :arke, [])
    core_group = Map.get(core_data, :group, []) ++ Map.get(arke_deps_data, :group, [])
    core_link = Map.get(core_data, :link, []) ++ Map.get(arke_deps_data, :link, [])

    # start core manager before create everything
    Mix.shell().info("--- Starting core managers --- ")
    error_parameter_manager = Arke.handle_manager(core_parameter, :arke_system, :parameter)
    error_arke_manager = Arke.handle_manager(core_arke, :arke_system, :arke)
    error_group_manager = Arke.handle_manager(core_group, :arke_system, :group)

    check_file("parameter_manager", "arke_system", error_parameter_manager)
    check_file("arke_manager", "arke_system", error_arke_manager)
    check_file("group_manager", "arke_system", error_group_manager)

    input_project = String.to_atom(opts[:project]) || :arke_system

    project_list = get_project(input_project, all)

    Enum.each(project_list, fn project ->
      if to_string(project) == "arke_system" do
        write_data(project, core_data, core_parameter, core_arke, core_group, core_link)
      else
        file_list = Path.wildcard("./lib/registry/*.#{format}")
        shared_arke_list = arke_registry("arke", format, "shared")
        shared_arke_deps_list = get_arke_deps_registry(format, "shared")

        raw_data = parse(shared_arke_list ++ shared_arke_deps_list ++ file_list, format)
        parameter_list = Map.get(raw_data, :parameter, [])
        arke_list = Map.get(raw_data, :arke, [])
        group_list = Map.get(raw_data, :group, [])
        link_list = Map.get(raw_data, :link, [])
        write_data(project, core_data, parameter_list, arke_list, group_list, link_list)
      end
    end)
  end

  defp write_data(input_project, core_data, parameter_list, arke_list, group_list, link_list) do
    project_key = to_string(input_project)
    # if the project is arke_system the managers have already been started so skip
    if project_key != "arke_system" do
      Mix.shell().info("--- Parsing registry files --- ")

      error_parameter_manager =
        Arke.handle_manager(Map.get(core_data, :parameter, []), input_project, :parameter)

      error_arke_manager =
        Arke.handle_manager(Map.get(core_data, :arke, []), input_project, :arke)

      error_group_manager =
        Arke.handle_manager(Map.get(core_data, :group, []), input_project, :group)

      check_file("parameter_manager", project_key, error_parameter_manager)
      check_file("arke_manager", project_key, error_arke_manager)
      check_file("group_manager", project_key, error_group_manager)
    end

    error_parameter = handle_parameter(parameter_list, input_project, [])
    error_arke = handle_arke(arke_list, input_project, [])
    error_group = handle_group(group_list, input_project, [])
    error_link = handle_link(link_list, input_project, [])
    check_file("parameter", project_key, error_parameter)
    check_file("arke", project_key, error_arke)
    check_file("group", project_key, error_group)
    check_file("link", project_key, error_link)
  end

  defp arke_registry(package_name, format, type) do
    # Get arke's dependecies based on the env path.
    env_var = System.get_env()
    folder_path = get_folder(type, format)

    case Enum.find(env_var, fn {k, _v} ->
           String.contains?(String.downcase(k), "ex_dep_#{package_name}_path")
         end) do
      {_package_name, ""} ->
        Path.wildcard("./**/arke*/**/registry/#{folder_path}")

      {_package_name, local_path} ->
        Path.wildcard("#{local_path}/lib/registry/#{folder_path}")

      nil ->
        Path.wildcard("./**/arke*/**/registry/#{folder_path}")
    end
  end

  defp get_folder("shared", format), do: "shared/*.#{format}"
  defp get_folder("system", format), do: "system/*.#{format}"
  defp get_folder("all", format), do: "**/*.#{format}"

  defp get_project(_input_project, true) do
    QueryManager.filter_by(arke_id: :arke_project, project: :arke_system)
    |> Enum.map(fn unit -> to_string(unit.id) end)
  end

  defp get_project(input_project, _all), do: [input_project]

  defp check_format!(format) when format in @supported_format, do: format

  defp check_format!(format),
    do:
      Mix.raise(
        "Invalid format: `#{format}`\nSupported format are: #{Enum.join(@supported_format, " | ")}"
      )

  # get all the registry file for all the arke_deps except arke itself which is used alone
  defp get_arke_deps_registry(format, type) do
    Enum.reduce(Mix.Project.config() |> Keyword.get(:deps, []), [], fn tuple, acc ->
      name = List.first(Tuple.to_list(tuple))

      if name != :arke and String.contains?(to_string(name), "arke") do
        arke_registry(to_string(name), format, type) ++ acc
      else
        acc
      end
    end)
  end

  defp parse(file_list, format, file_data \\ %{})

  defp parse([filename | t], "json" = format, data) do
    try do
      body = File.read!(filename)
      json = Jason.decode!(body, keys: :atoms)

      new_data =
        Enum.reduce(@decode_keys, %{}, fn key, acc ->
          Map.get(data, key, [])
          |> Enum.concat(Map.get(json, key, []))
          |> Enum.reduce(%{}, fn
            %{id: id} = map, acc ->
              Map.update(acc, id, map, fn existing ->
                Map.merge(existing, map)
              end)

            %{type: type, parent: parent, child: child} = map, acc ->
              Map.update(acc, "#{type}_#{parent}_#{child}", map, fn existing ->
                Map.merge(existing, map)
              end)
          end)
          |> Map.values()
          |> then(&Map.put(acc, key, &1))
        end)

      parse(t, format, new_data)
    rescue
      err in Jason.DecodeError ->
        %{data: data, token: token, position: position} = err

        Mix.raise(
          "Json error in: #{filename}.\n Position: #{position}\n token: #{token}\n data: #{data}"
        )

      err in File.Error ->
        %{reason: reason} = err
        Mix.raise("Error open file: #{filename}. \n Reason: #{reason}")
    end
  end

  # tutti i file parsati quindi proseguire
  defp parse([], _format, data), do: data

  defp handle_parameter([%{id: id, label: nil} = current | t], project, error),
    do: handle_parameter([Map.put(current, :label, String.capitalize(id)) | t], project, error)

  defp handle_parameter(
         [%{id: id, type: type} = current | t],
         project,
         error
       ) do
    Mix.shell().info("--- Creating parameter #{id} --- ")

    with {:ok, model} <- get_manager(:parameter, String.to_atom(type), project),
         {:ok, _unit} <- QueryManager.create(project, model, current) do
      handle_parameter(t, project, error)
    else
      %Unit{} ->
        handle_parameter(
          t,
          project,
          parse_error(Error.create(:parameter, "Record already exists in db for: `#{id}`"), error)
        )

      {:error, _} = err ->
        handle_parameter(t, project, parse_error(err, error, id))

      _err ->
        handle_parameter(
          t,
          project,
          parse_error(Error.create(:parameter, "Something went wrong for: `#{id}`"), error)
        )
    end
  end

  defp handle_parameter([_current | t], project, error) do
    handle_parameter(
      t,
      project,
      parse_error(Error.create(:parameter, "Missing parameter `id` or `type`"), error)
    )
  end

  defp handle_parameter([], _project, error), do: error

  defp handle_arke([%{id: id, label: nil} = current | t], project, error),
    do: handle_arke([Map.put(current, "label", String.capitalize(id)) | t], project, error)

  defp handle_arke(
         [%{id: id} = current | t],
         project,
         error
       ) do
    Mix.shell().info("--- Creating arke #{id} --- ")
    {parameter, new_data} = Map.pop(current, :parameters, [])
    parameter_error_msg = "#{id}_parameter_association"

    # error means manager not found, create
    with {:error, _} <- get_manager(:arke, String.to_atom(id), project),
         {:ok, model} <- get_manager(:arke, :arke, project),
         {:ok, unit} <- QueryManager.create(project, model, new_data),
         normalized_parameter <- normalize_parameter_list(parameter, unit),
         _ <- Mix.shell().info("--- Adding parameters to arke #{id} --- "),
         link_parameter_error <- handle_link(normalized_parameter, project, [], :add) do
           parameter_errors = handle_parameter_errors(link_parameter_error,parameter_error_msg, error)
           handle_arke(t, project, parameter_errors)
    else
      {:ok, %Unit{} = unit} ->
        Mix.shell().info("--- Updating parameters for arke #{id} --- ")

        parameter_errors = handle_arke_parameters(unit, parameter)
        |>  handle_parameter_errors(parameter_error_msg,error)
        |> then(&handle_arke(t, project, &1))

      {:error, _} = err ->
        handle_arke(t, project, [err | error])
    end
  end

  defp handle_arke([], _project, error), do: error

  defp handle_group(
         [%{id: id} = current | t],
         project,
         error
       ) do
    Mix.shell().info("--- Creating group #{id} --- ")

    # error means manager not found, create
    with {:error, _} <- get_manager(:group, String.to_atom(id), project),
         {:ok, model} <- get_manager(:group, :group, project),
         {:ok, unit} <- QueryManager.create(project, model, current),
         error_group <- add_arke_to_group(unit, project) do
      handle_group(t, project, error ++ error_group)
    else
      {:ok, %Unit{} = unit} ->
        # remove old arke
        # add missing arke
        handle_group(
          t,
          project,
          parse_error(Error.create(:group, "Record already exists in db for: `#{id}`"), error)
        )

      {:error, _} = err ->
        handle_group(t, project, [err | error])
    end
  end

  defp handle_group([], _project, error), do: error

  defp handle_link(link_list, project, error, action \\ :add)

  defp handle_link(
         [%{type: type, parent: parent, child: child} = current | t],
         project,
         error,
         action
       ) do
    {link_manager_fn, msg} = get_link_manager_fn(action, parent, child)

    Mix.shell().info(msg)

    case link_manager_fn.(
           project,
           parent,
           child,
           type,
           Map.get(current, :metadata, %{})
         ) do
      {:ok, _unit} ->
        handle_link(t, project, error, action)

      {:error, link_error} ->
        handle_link(
          t,
          project,
          [link_error | error],
          action
        )
    end
  end

  defp handle_link([current | t], project, error, action),
    do:
      handle_link(
        t,
        project,
        parse_error(Error.create(:link, "invalid parameters for #{current}}"), error),
        action
      )

  defp handle_link([], _project, error, _action), do: error

  defp get_link_manager_fn(:add, parent, child),
    do: {&LinkManager.add_node/5, "--- Creating link from #{parent} to #{child} --- "}

  defp get_link_manager_fn(:delete, parent, child),
    do: {&LinkManager.delete_node/5, "--- Deleting link from #{parent} to #{child} --- "}

  defp handle_arke_parameters(
         current_arke_model,
         parameter_list
       ) do
    current_linked_parameters =
      ArkeManager.get_parameters(current_arke_model)
      |> Enum.reduce([], fn
        %{id: parameter_id, data: %{persistence: "arke_parameter"}}, acc ->
          [to_string(parameter_id) | acc]

        # exclude table_columns which can not be removed without proper migrations
        _parameter, acc ->
          acc
      end)

    right_parameter_list = Enum.map(parameter_list, &(Map.get(&1, :id) |> to_string()))

    parameter_to_remove =
      (current_linked_parameters -- right_parameter_list)
      |> normalize_parameter_list(current_arke_model)

    ids_to_add = right_parameter_list -- current_linked_parameters

    parameter_to_add = Enum.filter(parameter_list, &Enum.member?(ids_to_add, to_string(&1.id))) |> normalize_parameter_list(current_arke_model)

    Mix.shell().info("--- Adding parameters to arke #{current_arke_model.id} --- ")
    add_parameter_error = handle_link(parameter_to_add, current_arke_model, [], :add)
    Mix.shell().info("--- Removing parameters from arke #{current_arke_model.id} --- ")
    delete_parameter_error = handle_link(parameter_to_remove, current_arke_model, [], :delete)

  end

  defp normalize_parameter_list(p_list, %{id: parent_id} = arke_parent) do
    Enum.map(p_list, fn parameter ->
      {parameter_id, metadata} = get_parameter_data(parameter)
      %{
        child: parameter_id,
        parent: to_string(parent_id),
        metadata: metadata,
        type: "parameter"
      }
    end)
  end

  defp get_parameter_data(%{id: p_id} = parameter), do: {to_string(p_id), Map.get(parameter, :metadata, %{})}
  defp get_parameter_data(parameter_id), do: {to_string(parameter_id), %{}}

  defp add_arke_to_group(group, project) do
    Mix.shell().info("--- Adding arkes to group #{group.id} --- ")
    arke_list = Map.get(group, :arke_list, [])

    group_link =
      Enum.reduce(arke_list, [], fn arke, acc ->
        [
          %{
            parent: to_string(group.id),
            child: to_string(Map.get(arke, :id)),
            metadata: Map.get(arke, :metadata, %{}),
            type: "group"
          }
          | acc
        ]
      end)

    handle_link(group_link, project, [])
  end

  defp parse_error({:error, error_message}, error_accumulator) when is_list(error_message),
    do: error_message ++ error_accumulator

  defp parse_error({:error, error_message}, error_accumulator),
    do: [error_message | error_accumulator]

  defp parse_error({:error, error_message}, error_accumulator, id),
    do: [%{create: id, error: error_message} | error_accumulator]

  defp get_manager(context, id, project) do
    case ArkeManager.get(id, project) do
      %Unit{} = model -> {:ok, model}
      nil -> Error.create(context, "manager does not exists for: `#{id}`")
    end
  end

  defp handle_parameter_errors([],_msg, error), do: error
  defp handle_parameter_errors(new_list_error, msg, error), do: [%{ msg => new_list_error} | error]

end
