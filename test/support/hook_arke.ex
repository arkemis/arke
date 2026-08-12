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

  before_transaction(fn hook ->
    send(self(), {:hook, :before_transaction, hook.op})
    {:ok, hook}
  end)

  before_write(:notify_before_write)
  before_write(:fail_when_flagged, on: [:create, :update])
  before_write(:stamp_when_flagged, on: :create)
  after_write(:notify_after_write)
  after_write(:fail_after_write_when_flagged, on: :create)
  after_commit(:fail_loudly_when_flagged)
  after_commit(:notify_after_commit)
  after_rollback(:notify_after_rollback)

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
