defmodule Arke.Test.HookArke do
  @moduledoc """
  Support arke exercising the `Arke.Hook.DSL` slots. Handlers report to the
  test process via `send/2` and read `hook_flag` to fail or mutate on demand.
  """
  use Arke.System
  alias Arke.Core.Unit
  alias Arke.Hook

  arke id: :hook_arke_support do
    parameter(:hook_flag, :string, required: false)
  end

  before_transaction fn hook ->
    send(self(), {:hook, :before_transaction, hook.op})
    {:ok, hook}
  end

  before_write :notify_before_write
  before_write :fail_when_flagged, on: [:create, :update]
  before_write :stamp_when_flagged, on: :create
  after_write :notify_after_write
  after_write :fail_after_write_when_flagged, on: :create
  after_commit :fail_loudly_when_flagged
  after_commit :notify_after_commit
  after_rollback :notify_after_rollback

  defp notify_before_write(hook) do
    send(self(), {:hook, :before_write, hook.op})
    {:ok, hook}
  end

  defp notify_after_write(hook) do
    send(self(), {:hook, :after_write, hook.op})
    {:ok, hook}
  end

  defp notify_after_commit(hook) do
    send(self(), {:hook, :after_commit, hook.op})
    {:ok, hook}
  end

  defp notify_after_rollback(%Hook{error: error} = hook) do
    send(self(), {:hook, :after_rollback, hook.op, error})
    {:ok, hook}
  end

  defp fail_when_flagged(%Hook{unit: unit} = hook) do
    case Unit.get_value(unit, :hook_flag) do
      "fail_before_write" -> {:error, [%{context: "hook_test", message: "failed on purpose"}]}
      _ -> {:ok, hook}
    end
  end

  defp fail_after_write_when_flagged(%Hook{unit: unit} = hook) do
    case Unit.get_value(unit, :hook_flag) do
      "fail_after_write" -> {:error, [%{context: "hook_test", message: "failed after write"}]}
      _ -> {:ok, hook}
    end
  end

  defp stamp_when_flagged(%Hook{unit: unit} = hook) do
    case Unit.get_value(unit, :hook_flag) do
      "stamp" -> {:ok, %{hook | unit: Unit.update(unit, hook_flag: "stamped")}}
      _ -> {:ok, hook}
    end
  end

  defp fail_loudly_when_flagged(%Hook{unit: unit} = hook) do
    if Unit.get_value(unit, :hook_flag) == "raise_after_commit",
      do: raise("after_commit boom"),
      else: {:ok, hook}
  end

  def register() do
    Arke.Boundary.ParameterManager.create(
      Unit.new(
        :hook_flag,
        %{
          label: "hook_flag",
          format: :attribute,
          is_primary: false,
          nullable: true,
          required: false,
          persistence: "arke_parameter",
          helper_text: nil,
          min_length: nil,
          max_length: nil,
          values: nil,
          multiple: false,
          unique: false,
          default_string: nil
        },
        :string,
        nil,
        %{},
        nil,
        nil,
        nil
      ),
      :arke_system
    )

    [] =
      Arke.handle_manager(
        [arke_from_attr() |> Map.update!(:id, &to_string/1)],
        :arke_system,
        :arke
      )

    :ok
  end
end

defmodule Arke.Test.LegacyHookArke do
  @moduledoc """
  Support arke keeping the pre-pipeline callback heads, to prove the
  deprecation shim registers them as pipeline entries.
  """
  use Arke.System

  arke id: :legacy_hook_arke do
    parameter(:hook_flag, :string, required: false)
  end

  def before_create(_arke, unit) do
    send(self(), {:legacy, :before_create})

    case Arke.Core.Unit.get_value(unit, :hook_flag) do
      "fail_before_create" -> {:error, [%{context: "legacy_test", message: "failed on purpose"}]}
      "stamp" -> {:ok, Arke.Core.Unit.update(unit, hook_flag: "stamped")}
      _ -> {:ok, unit}
    end
  end

  def on_create(_arke, unit) do
    send(self(), {:legacy, :on_create})
    {:ok, unit}
  end

  def before_update(_arke, old_unit, unit) do
    send(self(), {:legacy, :before_update, old_unit.id})
    {:ok, unit}
  end

  def on_update(_arke, _old_unit, unit) do
    send(self(), {:legacy, :on_update})
    {:ok, unit}
  end

  def before_delete(_arke, unit) do
    send(self(), {:legacy, :before_delete})
    {:ok, unit}
  end

  def on_delete(_arke, unit) do
    send(self(), {:legacy, :on_delete})
    {:ok, unit}
  end

  def on_struct_encode(_arke, _unit, data, _opts) do
    {:ok, Map.put(data, :legacy_encoded, true)}
  end

  def register() do
    [] =
      Arke.handle_manager(
        [arke_from_attr() |> Map.update!(:id, &to_string/1)],
        :arke_system,
        :arke
      )

    :ok
  end
end

defmodule Arke.Test.LegacyHookGroup do
  @moduledoc """
  Support group keeping the pre-pipeline `*_unit_*` callback heads, to prove
  the group shim. Bound to `legacy_hook_arke`.
  """
  use Arke.System.Group

  group id: :legacy_hook_group do
  end

  def before_unit_create(_arke, unit) do
    send(self(), {:legacy_group, :before_unit_create})
    {:ok, unit}
  end

  def on_unit_create(_arke, unit) do
    send(self(), {:legacy_group, :on_unit_create})
    {:ok, unit}
  end

  def on_unit_delete(_arke, unit) do
    send(self(), {:legacy_group, :on_unit_delete})
    {:ok, unit}
  end

  def register() do
    [] =
      Arke.handle_manager(
        [%{id: "legacy_hook_group", label: "Legacy hook group", arke_list: ["legacy_hook_arke"]}],
        :arke_system,
        :group
      )

    :ok
  end
end
