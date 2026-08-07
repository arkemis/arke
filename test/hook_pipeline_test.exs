defmodule Arke.HookPipelineTest do
  @moduledoc """
  Phase 1 of PLAN-transactions: `%Arke.Hook{}` token and `Arke.Hook.DSL`
  registration.
  """
  use Arke.Test.RepoCase

  import ExUnit.CaptureLog

  @project :test_schema

  defp hook_arke, do: ArkeManager.get(:hook_arke_support, :arke_system)

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
      {:ok, unit} =
        QueryManager.create(@project, hook_arke(), id: "hook_stamp", hook_flag: "stamp")

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
end
