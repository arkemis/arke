defmodule Arke.TransactionTest do
  @moduledoc """
  Phase 2 of PLAN-transactions: the transaction seam wraps the write pipeline,
  `{:error, _}` from any step rolls everything back, and `after_commit`
  entries only run on success.
  """
  use Arke.Test.RepoCase

  @project :test_schema

  defp hook_arke, do: ArkeManager.get(:hook_arke_support, :arke_system)
  defp support_arke, do: ArkeManager.get(:arke_test_support, :arke_system)

  defp drain(messages \\ []) do
    receive do
      {:hook, _, _} = m -> drain([m | messages])
      {:hook, _, _, _} = m -> drain([m | messages])
    after
      0 -> Enum.reverse(messages)
    end
  end

  test "an after_write failure rolls the persisted row back" do
    assert {:error, [%{message: "failed after write"}]} =
             QueryManager.create(@project, hook_arke(),
               id: "txn_rollback",
               hook_flag: "fail_after_write"
             )

    assert QueryManager.get_by(project: @project, id: "txn_rollback") == nil

    messages = drain()
    refute {:hook, :after_commit, :create} in messages
    assert Enum.any?(messages, &match?({:hook, :after_rollback, :create, _}, &1))
  end

  test "a failing link write leaves nothing committed" do
    {:ok, _} =
      QueryManager.create(@project, support_arke(),
        id: "txn_link_target",
        enum_integer_support: [1],
        string_support: "txn-target",
        enum_string_support: "first"
      )

    assert {:error, _} =
             QueryManager.create(@project, support_arke(),
               id: "txn_link_source",
               enum_integer_support: [1],
               string_support: "txn-source",
               enum_string_support: "second",
               multi_link_support: ["txn_link_target", "txn_missing"]
             )

    assert QueryManager.get_by(project: @project, id: "txn_link_source") == nil

    assert QueryManager.query(project: @project, arke: :arke_link)
           |> QueryManager.filter(:parent_id, :eq, "txn_link_source", false)
           |> QueryManager.all() == []
  end

  test "a nested create rolls back with the outer write" do
    {:ok, target} =
      QueryManager.create(@project, support_arke(),
        id: "txn_nested_target",
        enum_integer_support: [1],
        string_support: "txn-nested",
        enum_string_support: "first"
      )

    assert {:error, _} =
             QueryManager.update(target, multi_link_support: ["does_not_exist"])

    stored = QueryManager.get_by(project: @project, id: "txn_nested_target")
    assert Unit.get_value(stored, :multi_link_support) in [nil, []]
  end

  describe "QueryManager.transaction/3" do
    test "commits the writes and returns {:ok, _}" do
      assert {:ok, unit} =
               QueryManager.transaction(@project, fn ->
                 QueryManager.create(@project, hook_arke(), id: "txn_api_commit")
               end)

      assert unit.id == :txn_api_commit
      assert QueryManager.get_by(project: @project, id: "txn_api_commit") != nil
    end

    test "rolls back every write when the function returns {:error, _}" do
      assert {:error, :nope} =
               QueryManager.transaction(@project, fn ->
                 {:ok, _} = QueryManager.create(@project, hook_arke(), id: "txn_api_a")
                 {:ok, _} = QueryManager.create(@project, hook_arke(), id: "txn_api_b")
                 {:error, :nope}
               end)

      assert QueryManager.get_by(project: @project, id: "txn_api_a") == nil
      assert QueryManager.get_by(project: @project, id: "txn_api_b") == nil
    end

    test "after_commit hooks defer to the outermost commit" do
      {:ok, _} =
        QueryManager.transaction(@project, fn ->
          {:ok, unit} = QueryManager.create(@project, hook_arke(), id: "txn_defer")

          messages = drain()
          assert {:hook, :after_write, :create} in messages
          refute {:hook, :after_commit, :create} in messages

          {:ok, unit}
        end)

      assert {:hook, :after_commit, :create} in drain()
    end

    test "a rolled-back transaction drops the queued after_commit entries" do
      {:error, :nope} =
        QueryManager.transaction(@project, fn ->
          {:ok, _} = QueryManager.create(@project, hook_arke(), id: "txn_dropped")
          {:error, :nope}
        end)

      refute {:hook, :after_commit, :create} in drain()
    end

    test "a rolled-back transaction compensates the writes that already succeeded" do
      {:error, :nope} =
        QueryManager.transaction(@project, fn ->
          {:ok, _} = QueryManager.create(@project, hook_arke(), id: "txn_compensated")
          {:error, :nope}
        end)

      assert {:hook, :after_rollback, :create, :nope} in drain()
    end

    test "a raise inside the transaction compensates and leaves no queue behind" do
      assert_raise RuntimeError, "boom", fn ->
        QueryManager.transaction(@project, fn ->
          {:ok, _} = QueryManager.create(@project, hook_arke(), id: "txn_raised")
          raise "boom"
        end)
      end

      assert Enum.any?(drain(), &match?({:hook, :after_rollback, :create, _}, &1))

      {:ok, _} = QueryManager.create(@project, hook_arke(), id: "txn_after_raise")

      assert Enum.count(drain(), &match?({:hook, :after_commit, :create}, &1)) == 1
    end
  end

  describe "lock:" do
    test "raises outside a transaction" do
      assert_raise ArgumentError, ~r/only valid inside a transaction/, fn ->
        QueryManager.get_by(project: @project, id: "whatever", lock: true)
      end
    end

    test "is accepted inside a transaction" do
      {:ok, _} = QueryManager.create(@project, hook_arke(), id: "txn_lock")
      drain()

      assert {:ok, unit} =
               QueryManager.transaction(@project, fn ->
                 {:ok, QueryManager.get_by(project: @project, id: "txn_lock", lock: true)}
               end)

      assert unit.id == :txn_lock
    end
  end

  test "a string-keyed transaction flag, as reloaded from jsonb, still opts out" do
    arke =
      Arke.Core.Unit.update(hook_arke(), %{
        metadata: Map.put(hook_arke().metadata, "transaction", false)
      })

    assert {:error, [%{message: "failed after write"}]} =
             QueryManager.create(@project, arke,
               id: "txn_string_optout",
               hook_flag: "fail_after_write"
             )

    assert QueryManager.get_by(project: @project, id: "txn_string_optout") != nil
  end

  test "after_commit still flushes for a transaction-opted-out arke" do
    arke_project = ArkeManager.get(:arke_project, :arke_system)

    assert {:ok, unit} =
             QueryManager.create(:arke_system, arke_project, %{
               id: "txn_optout_project",
               name: "txn_optout_project",
               description: "txn optout",
               type: "postgres_schema",
               label: "Txn optout"
             })

    assert {:ok, nil} = QueryManager.delete(:arke_system, unit)
  end
end
