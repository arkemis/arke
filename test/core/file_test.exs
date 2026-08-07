defmodule Arke.Core.FileTest do
  use Arke.Test.RepoCase

  alias Arke.Boundary.FileManager
  alias Arke.Core.File, as: ArkeFile

  # The no-op stubs of Arke.Utils.FileStorage are overridable, so a storage
  # backend that reports what it was asked to do is a handful of lines.
  defmodule Storage do
    use Arke.Utils.FileStorage

    def upload_file(file_name, _file_data, opts) do
      send(self(), {:upload_file, file_name, opts})
      {:ok, nil}
    end

    def delete_file(file_path, _opts) do
      send(self(), {:delete_file, file_path})
      {:ok, nil}
    end

    def get_public_url(unit, _opts), do: {:ok, %{signed_url: "public/#{unit.data.name}"}}

    def get_bucket_file_signed_url(file_path, _opts) do
      send(self(), {:signed_url, file_path})
      {:ok, %{signed_url: "signed/#{file_path}", expiration: System.os_time(:second) + 3600}}
    end
  end

  defmodule FailingStorage do
    use Arke.Utils.FileStorage

    def upload_file(_file_name, _file_data, _opts), do: {:error, "upload failed"}
    def delete_file(_file_path, _opts), do: {:error, "delete failed"}
    def get_bucket_file_signed_url(_file_path, _opts), do: {:error, "signing failed"}
  end

  setup do
    Application.put_env(:arke, :file_storage_module, Storage)
    on_exit(fn -> Application.delete_env(:arke, :file_storage_module) end)

    arke = ArkeManager.get(:arke_file, :arke_system)

    unit =
      Unit.load(arke, %{
        id: "test_file",
        name: "f.png",
        path: "arke_file/2026",
        binary_data: <<1, 2, 3>>,
        metadata: %{project: :test_schema}
      })

    {:ok, arke: arke, unit: unit}
  end

  describe "get_signed_url/1" do
    test "signs and caches the url", %{unit: unit} do
      assert {:ok, %{signed_url: "signed/arke_file/2026/f.png"}} = ArkeFile.get_signed_url(unit)
      assert_received {:signed_url, "arke_file/2026/f.png"}

      assert FileManager.get(:test_file, :test_schema).signed_url ==
               "signed/arke_file/2026/f.png"
    end

    test "serves a live cache entry without signing again", %{unit: unit} do
      {:ok, first} = ArkeFile.get_signed_url(unit)
      assert_received {:signed_url, _}

      assert ArkeFile.get_signed_url(unit) == {:ok, first}
      refute_received {:signed_url, _}
    end

    test "signs again when the cached url has expired", %{unit: unit} do
      FileManager.add(:test_file, :test_schema, "stale", System.os_time(:second) - 10)

      assert {:ok, %{signed_url: "signed/arke_file/2026/f.png"}} = ArkeFile.get_signed_url(unit)
      assert_received {:signed_url, _}
    end

    test "signs again when the cache entry is malformed", %{unit: unit} do
      :ets.insert(:file_manager_cache, {{:test_file, :test_schema}, %{nonsense: true}})

      assert {:ok, %{signed_url: "signed/arke_file/2026/f.png"}} = ArkeFile.get_signed_url(unit)
      assert_received {:signed_url, _}
    end

    test "reports a signing failure", %{unit: unit} do
      Application.put_env(:arke, :file_storage_module, FailingStorage)

      assert ArkeFile.get_signed_url(unit) == {:error, "signing failed"}
      assert FileManager.get(:test_file, :test_schema) == nil
    end
  end

  describe "get_url/1" do
    test "a public file gets its public url", %{unit: unit} do
      unit = Unit.update(unit, public: true)

      assert ArkeFile.get_url(unit) == {:ok, %{signed_url: "public/f.png"}}
      refute_received {:signed_url, _}
    end

    test "anything else gets signed", %{unit: unit} do
      assert {:ok, %{signed_url: "signed/arke_file/2026/f.png"}} = ArkeFile.get_url(unit)
      assert_received {:signed_url, _}
    end
  end

  describe "before_create/2" do
    test "uploads a private file by default", %{arke: arke, unit: unit} do
      assert {:ok, created} = ArkeFile.before_create(arke, unit)

      assert created.data.public == false
      assert_received {:upload_file, "arke_file/2026/f.png", public: false}
    end

    test "uploads a public file when the link parameter says so", %{arke: arke, unit: unit} do
      unit = %{unit | runtime_data: %{link_parameter: %{data: %{public: true}}}}

      assert {:ok, created} = ArkeFile.before_create(arke, unit)

      assert created.data.public == true
      assert_received {:upload_file, "arke_file/2026/f.png", public: true}
    end

    test "reports an upload failure", %{arke: arke, unit: unit} do
      Application.put_env(:arke, :file_storage_module, FailingStorage)

      assert ArkeFile.before_create(arke, unit) == {:error, "upload failed"}
    end
  end

  describe "before_update/2" do
    test "uploads the new binary", %{arke: arke, unit: unit} do
      assert ArkeFile.before_update(arke, unit) == {:ok, unit}
      assert_received {:upload_file, "arke_file/2026/f.png", []}
    end

    test "reports an upload failure", %{arke: arke, unit: unit} do
      Application.put_env(:arke, :file_storage_module, FailingStorage)

      assert ArkeFile.before_update(arke, unit) == {:error, "upload failed"}
    end

    test "skips the upload when there is no binary" do
      # the clause reads :binary_data off the top level, not off unit.data, so
      # only a bare map reaches it. Pinned, not endorsed.
      assert ArkeFile.before_update(nil, %{binary_data: nil}) == {:ok, %{binary_data: nil}}
      refute_received {:upload_file, _, _}
    end
  end

  describe "before_delete/2" do
    test "deletes the stored object", %{arke: arke, unit: unit} do
      assert ArkeFile.before_delete(arke, unit) == {:ok, unit}
      assert_received {:delete_file, "arke_file/2026/f.png"}
    end

    test "reports a delete failure", %{arke: arke, unit: unit} do
      Application.put_env(:arke, :file_storage_module, FailingStorage)

      assert ArkeFile.before_delete(arke, unit) == {:error, "delete failed"}
    end
  end

  describe "on_delete/2" do
    test "drops the cached url", %{arke: arke, unit: unit} do
      {:ok, _} = ArkeFile.get_signed_url(unit)
      assert FileManager.get(:test_file, :test_schema) != nil

      assert ArkeFile.on_delete(arke, unit) == {:ok, unit}
      assert FileManager.get(:test_file, :test_schema) == nil
    end
  end

  describe "on_struct_encode/4" do
    test "adds the signed url when load_files is set", %{arke: arke, unit: unit} do
      assert {:ok, data} = ArkeFile.on_struct_encode(arke, unit, %{}, load_files: true)
      assert data.signed_url == "signed/arke_file/2026/f.png"
    end

    test "leaves the data alone by default", %{arke: arke, unit: unit} do
      assert ArkeFile.on_struct_encode(arke, unit, %{name: "f.png"}, []) ==
               {:ok, %{name: "f.png"}}

      refute_received {:signed_url, _}
    end

    test "leaves the data alone when signing fails", %{arke: arke, unit: unit} do
      Application.put_env(:arke, :file_storage_module, FailingStorage)

      assert ArkeFile.on_struct_encode(arke, unit, %{name: "f.png"}, load_files: true) ==
               {:ok, %{name: "f.png"}}
    end
  end
end
