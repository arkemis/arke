defmodule Arke.Security.LinkAndFileTest do
  use Arke.Test.RepoCase

  alias Arke.Core.File, as: ArkeFile
  alias Arke.Validator

  @project :test_schema

  defp create_arke(id) do
    arke_model = ArkeManager.get(:arke, :arke_system)
    {:ok, _} = QueryManager.create(@project, arke_model, %{id: id, label: id})
    ArkeManager.get(String.to_atom(id), @project)
  end

  defp create_link_parameter(id, target, opts \\ []) do
    parameter_model = ArkeManager.get(:link, :arke_system)

    unit =
      Unit.load(
        parameter_model,
        [id: id, label: to_string(id), arke_or_group_id: target] ++ opts
      )

    ParameterManager.create(unit, @project)
    ParameterManager.get(id, @project)
  end

  defp create_unit(arke, id) do
    {:ok, unit} = QueryManager.create(@project, arke, %{id: id, label: id})
    unit
  end

  defp setup_links(_context) do
    target_arke = create_arke("sec_target_arke")
    other_arke = create_arke("sec_other_arke")
    holder_arke = create_arke("sec_holder_arke")

    param = create_link_parameter(:sec_link, "sec_target_arke")
    LinkManager.add_node(@project, holder_arke, param, "parameter", %{})
    holder_arke = ArkeManager.get(:sec_holder_arke, @project)

    target = create_unit(target_arke, "sec_target_unit")
    other = create_unit(other_arke, "sec_other_unit")

    {:ok,
     param: param,
     holder_arke: holder_arke,
     target_arke: target_arke,
     target: target,
     other: other}
  end

  describe "link target validation (C4)" do
    setup [:setup_links]

    test "accepts a unit of the declared arke", %{param: param, holder_arke: arke} do
      assert {_, []} = Validator.validate_parameter(arke, param, "sec_target_unit", @project)
    end

    test "rejects a unit of another arke", %{param: param, holder_arke: arke} do
      assert {_, [_error]} = Validator.validate_parameter(arke, param, "sec_other_unit", @project)

      assert {_, [_error]} =
               Validator.validate_parameter(
                 arke,
                 param,
                 ["sec_target_unit", "sec_other_unit"],
                 @project
               )
    end

    test "leaves ids with no unit behind them alone", %{param: param, holder_arke: arke} do
      assert {_, []} = Validator.validate_parameter(arke, param, "sec_missing_unit", @project)
    end

    test "rejects creating a unit linked to another arke", %{holder_arke: arke} do
      assert {:error, _} =
               QueryManager.create(@project, arke, %{
                 id: "sec_holder_bad",
                 label: "bad",
                 sec_link: "sec_other_unit"
               })
    end
  end

  describe "load_links with a link_query (C4)" do
    setup [:setup_links]

    setup %{holder_arke: arke} do
      {:ok, holder} =
        QueryManager.create(@project, arke, %{
          id: "sec_holder_ok",
          label: "ok",
          sec_link: "sec_target_unit"
        })

      {:ok, holder: holder}
    end

    test "expands linked units without a link_query", %{holder: holder} do
      encoded = StructManager.encode(holder, load_links: true, type: :json)
      assert %{id: "sec_target_unit"} = encoded.sec_link
    end

    test "drops linked units the link_query denies", %{holder: holder} do
      encoded =
        StructManager.encode(holder,
          load_links: true,
          type: :json,
          link_query: fn _query, _arke_id -> :deny end
        )

      assert encoded.sec_link == nil
    end

    test "passes a query scoped to the arke and ids of the links", %{holder: holder} do
      test_pid = self()

      encoded =
        StructManager.encode(holder,
          load_links: true,
          type: :json,
          link_query: fn query, arke_id ->
            send(test_pid, {:link_query, arke_id})
            query
          end
        )

      assert_received {:link_query, :sec_target_arke}
      assert %{id: "sec_target_unit"} = encoded.sec_link
    end
  end

  describe "arke_file before_load (C2)" do
    setup do
      path = Path.join(System.tmp_dir!(), "arke_file_test_#{System.unique_integer([:positive])}")
      File.write!(path, "uploaded content")
      on_exit(fn -> File.rm(path) end)
      {:ok, path: path}
    end

    test "refuses a plain map pointing at a server path", %{path: path} do
      data = %{path: path, content_type: "text/plain", filename: "a.txt"}
      assert {:error, _} = ArkeFile.before_load(data, :create)
    end

    test "reads a Plug.Upload", %{path: path} do
      upload = %{
        __struct__: Plug.Upload,
        path: path,
        content_type: "text/plain",
        filename: "a.txt"
      }

      assert {:ok, %{binary_data: "uploaded content", extension: ".txt", name: "a.txt"}} =
               ArkeFile.before_load(upload, :create)
    end

    test "returns an error when the upload cannot be read" do
      upload = %{
        __struct__: Plug.Upload,
        path: "/nonexistent/arke_file_test",
        content_type: "text/plain",
        filename: "a.txt"
      }

      assert {:error, _} = ArkeFile.before_load(upload, :create)
    end
  end
end
