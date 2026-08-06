defmodule Arke.HookPipelineTest do
  @moduledoc """
  Phase 1 of PLAN-transactions: `%Arke.Hook{}` token, `Arke.Hook.DSL`
  registration and the legacy-callback shim.
  """
  use Arke.Test.RepoCase

  import ExUnit.CaptureLog

  @project :test_schema

  defp hook_arke, do: ArkeManager.get(:hook_arke_support, :arke_system)
  defp legacy_arke, do: ArkeManager.get(:legacy_hook_arke, :arke_system)

  defp drain(messages \\ []) do
    receive do
      {:hook, _, _} = m -> drain([m | messages])
      {:hook, _, _, _} = m -> drain([m | messages])
    after
      0 -> Enum.reverse(messages)
    end
  end

  describe "DSL registration" do
    test "hooks fire in registration order with the op set" do
      assert {:ok, _unit} = QueryManager.create(@project, hook_arke(), id: "hook_order")

      assert drain() == [
               {:hook, :before_transaction, :create},
               {:hook, :before_write, :create},
               {:hook, :after_write, :create},
               {:hook, :after_commit, :create}
             ]
    end

    test "on: filters by operation" do
      {:ok, unit} = QueryManager.create(@project, hook_arke(), id: "hook_ops")
      drain()

      {:ok, unit} = QueryManager.update(unit, hook_flag: "x")
      assert {:hook, :before_write, :update} in drain()

      {:ok, nil} = QueryManager.delete(@project, unit)
      assert {:hook, :after_write, :delete} in drain()
    end

    test "a before_write error aborts the write and rolls into after_rollback" do
      assert {:error, [%{context: "hook_test"}]} =
               QueryManager.create(@project, hook_arke(),
                 id: "hook_fail",
                 hook_flag: "fail_before_write"
               )

      messages = drain()
      assert {:hook, :before_transaction, :create} in messages
      refute {:hook, :after_write, :create} in messages
      refute {:hook, :after_commit, :create} in messages
      assert Enum.any?(messages, &match?({:hook, :after_rollback, :create, [_ | _]}, &1))

      assert QueryManager.get_by(project: @project, id: "hook_fail") == nil
    end

    test "mutating hook.unit in before_write is persisted" do
      {:ok, unit} = QueryManager.create(@project, hook_arke(), id: "hook_stamp", hook_flag: "stamp")

      assert Unit.get_value(unit, :hook_flag) == "stamped"

      assert QueryManager.get_by(project: @project, id: "hook_stamp").data.hook_flag == "stamped"
    end

    test "a raising after_commit entry is isolated: caller still succeeds, later entries run" do
      log =
        capture_log(fn ->
          assert {:ok, _unit} =
                   QueryManager.create(@project, hook_arke(),
                     id: "hook_raise",
                     hook_flag: "raise_after_commit"
                   )
        end)

      assert {:hook, :after_commit, :create} in drain()
      assert log =~ "after_commit boom"
    end
  end

  describe "legacy shim" do
    defp drain_legacy(messages \\ []) do
      receive do
        {:legacy, _} = m -> drain_legacy([m | messages])
        {:legacy, _, _} = m -> drain_legacy([m | messages])
        {:legacy_group, _} = m -> drain_legacy([m | messages])
      after
        0 -> Enum.reverse(messages)
      end
    end

    test "old-style arke and group callbacks run as pipeline entries, in the old order" do
      {:ok, unit} = QueryManager.create(@project, legacy_arke(), id: "legacy_create")

      assert drain_legacy() == [
               {:legacy, :before_create},
               {:legacy_group, :before_unit_create},
               {:legacy, :on_create},
               {:legacy_group, :on_unit_create}
             ]

      {:ok, unit} = QueryManager.update(unit, hook_flag: "x")
      messages = drain_legacy()
      assert {:legacy, :before_update, :legacy_create} in messages
      assert {:legacy, :on_update} in messages

      {:ok, nil} = QueryManager.delete(@project, unit)

      assert drain_legacy() == [
               {:legacy, :before_delete},
               {:legacy_group, :on_unit_delete},
               {:legacy, :on_delete}
             ]
    end

    test "a legacy on_create error is returned but the committed row stays (autocommit contract)" do
      assert {:error, [%{message: "on_create failed"}]} =
               QueryManager.create(@project, legacy_arke(),
                 id: "legacy_on_fail",
                 hook_flag: "fail_on_create"
               )

      assert QueryManager.get_by(project: @project, id: "legacy_on_fail") != nil
    end

    test "a legacy before_create can still abort the write" do
      assert {:error, [%{context: "legacy_test"}]} =
               QueryManager.create(@project, legacy_arke(),
                 id: "legacy_fail",
                 hook_flag: "fail_before_create"
               )

      assert QueryManager.get_by(project: @project, id: "legacy_fail") == nil
    end

    test "a legacy before_create can still mutate the unit" do
      {:ok, unit} =
        QueryManager.create(@project, legacy_arke(), id: "legacy_stamp", hook_flag: "stamp")

      assert Unit.get_value(unit, :hook_flag) == "stamped"
    end

    test "a legacy on_struct_encode still runs under the after_struct_encode name" do
      {:ok, unit} = QueryManager.create(@project, legacy_arke(), id: "legacy_encode")

      assert %{legacy_encoded: true} = StructManager.encode(unit, type: "json")
    end
  end
end
