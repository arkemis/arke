defmodule Arke.Core.FileTest do
  use Arke.Test.RepoCase

  defmodule Storage do
    use Arke.Utils.FileStorage

    def upload_file(file_name, _file_data, opts) do
      send(self(), {:upload, file_name, opts})
      {:ok, %{}}
    end

    def delete_file(file_path, opts) do
      send(self(), {:delete, file_path, opts})
      {:ok, %{}}
    end

    def get_bucket_file_signed_url(file_path, opts) do
      send(self(), {:signed_url, file_path, opts})

      {:ok,
       %{
         signed_url: "https://signed",
         expiration: DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(3600)
       }}
    end
  end

  @project :file_test_project

  setup do
    Application.put_env(:arke, :file_storage_module, Storage)
    on_exit(fn -> Application.delete_env(:arke, :file_storage_module) end)
    :ok
  end

  defp project_with_bucket(bucket) do
    {:ok, _} =
      QueryManager.create(:arke_system, ArkeManager.get(:arke_project, :arke_system),
        id: to_string(@project),
        label: "File test project",
        type: "postgres_schema",
        bucket: bucket
      )

    :ok
  end

  defp create_file(opts \\ []) do
    source = Path.join(System.tmp_dir!(), "arke_file_#{System.unique_integer([:positive])}")
    File.write!(source, "content")

    QueryManager.create(
      @project,
      ArkeManager.get(:arke_file, @project),
      [
        metadata: %{project: @project},
        path: source,
        content_type: "text/plain",
        filename: "doc.txt"
      ] ++ opts
    )
  end

  describe "upload" do
    test "stamps the project bucket and project-prefixed path, and passes them to the storage" do
      project_with_bucket("project-bucket")

      {:ok, unit} = create_file()

      assert unit.data.bucket == "project-bucket"
      assert String.starts_with?(unit.data.path, "#{@project}/arke_file/")

      assert_received {:upload, name, opts}
      assert opts[:bucket] == "project-bucket"
      assert name == "#{unit.data.path}/doc.txt"
    end

    test "a link_parameter bucket wins over the project bucket" do
      project_with_bucket("project-bucket")

      {:ok, unit} =
        create_file(runtime_data: %{link_parameter: %{data: %{bucket: "override-bucket"}}})

      assert unit.data.bucket == "override-bucket"
      assert_received {:upload, _name, opts}
      assert opts[:bucket] == "override-bucket"
    end

    test "no project bucket falls through to nil" do
      {:ok, unit} = create_file()

      assert unit.data.bucket == nil
      assert_received {:upload, _name, opts}
      assert opts[:bucket] == nil
    end
  end

  describe "stored bucket" do
    test "delete passes the stamped bucket" do
      project_with_bucket("project-bucket")
      {:ok, unit} = create_file()

      {:ok, nil} = QueryManager.delete(@project, unit)

      assert_received {:delete, path, opts}
      assert path == "#{unit.data.path}/doc.txt"
      assert opts[:bucket] == "project-bucket"
    end

    test "signed url passes the stamped bucket" do
      project_with_bucket("project-bucket")
      {:ok, unit} = create_file()

      assert {:ok, %{signed_url: "https://signed"}} = Arke.Core.File.get_signed_url(unit)

      assert_received {:signed_url, _path, opts}
      assert opts[:bucket] == "project-bucket"
    end

    test "a legacy unit with no stamped bucket signs against nil" do
      {:ok, unit} = create_file()
      legacy = %{unit | id: :legacy_file, data: Map.delete(unit.data, :bucket)}

      assert {:ok, _} = Arke.Core.File.get_signed_url(legacy)

      assert_received {:signed_url, _path, opts}
      assert opts[:bucket] == nil
    end
  end
end
