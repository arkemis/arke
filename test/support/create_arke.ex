defmodule Arke.Test.CreateArke do
  use Arke.System
  alias Arke.Validator
  alias Arke.Core.Unit
  alias Arke.Boundary.{ArkeManager, GroupManager, ParameterManager}
  alias Arke.Core.Parameter

  arke id: :arke_test_support do
    parameter(:string_support, :string,
      required: false,
      default_string: "test_default",
      unique: true
    )

    parameter(:enum_string_support, :string,
      required: false,
      values: ["first", "second", "third"]
    )

    parameter(:integer_support, :integer, required: false, default_integer: 5)

    parameter(:enum_integer_support, :integer,
      required: true,
      values: [1, 2, 3, 4, 5],
      multiple: true
    )

    parameter(:float_support, :float, required: false, default_float: 2.5)

    parameter(:enum_float_support, :float,
      required: false,
      values: [
        %{label: "One", value: 1},
        %{label: "Two", value: 2},
        %{label: "Three and a half", value: 3.5}
      ]
    )

    parameter(:boolean_support, :boolean, required: false, default_boolean: false)
    parameter(:list_support, :list, required: false, default_list: ["list", "of", "values"])
    parameter(:dict_support, :dict, required: false, default_dict: %{starting: "value"})
    parameter(:date_support, :date, default_date: ~D[1999-11-08])
    parameter(:datetime_support, :datetime, default_datetime: ~U[1999-11-08 09:55:13.416444Z])
    parameter(:time_support, :time, default_time: ~T[09:55:13.416444])
  end

  def support_arke() do
    %{id: id} = attr = arke_from_attr()
    [] = Arke.handle_manager([Map.update!(attr, :id, &to_string/1)], :arke_system, :arke)

    Enum.each(groups_from_attr(), fn %{id: parent_id, metadata: link_metadata} ->
      GroupManager.add_link(parent_id, :arke_system, :arke_list, id, link_metadata)
    end)
  end

  defp base_parameter(opts \\ []) do
    %{
      label: Keyword.get(opts, :label),
      format: Keyword.get(opts, :format, :attribute),
      is_primary: Keyword.get(opts, :is_primary, false),
      nullable: Keyword.get(opts, :nullable, true),
      required: Keyword.get(opts, :required, false),
      persistence: Keyword.get(opts, :persistence, "arke_parameter"),
      helper_text: Keyword.get(opts, :label, nil)
    }
  end

  def support_parameter() do
    string_support =
      Unit.new(
        :string_support,
        Map.merge(
          base_parameter(
            label: "string_support",
            is_primary: true,
            nullable: false,
            required: false
          ),
          %{
            min_length: 2,
            max_length: nil,
            values: nil,
            multiple: false,
            unique: true,
            default_string: nil
          }
        ),
        :string,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    enum_string_support =
      Unit.new(
        :enum_string_support,
        Map.merge(
          base_parameter(
            label: "enum_string_support",
            is_primary: true,
            nullable: false,
            required: false
          ),
          %{
            min_length: 2,
            max_length: nil,
            values: nil,
            multiple: false,
            unique: true,
            default_string: nil
          }
        ),
        :string,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    dict_support =
      Unit.new(
        :dict_support,
        Map.merge(
          base_parameter(label: "dict_support"),
          %{default_dict: %{}}
        ),
        :dict,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    datetime_support =
      Unit.new(
        :datetime_support,
        Map.merge(
          base_parameter(label: "datetime_support"),
          %{default_datetime: nil}
        ),
        :datetime,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    time_support =
      Unit.new(
        :time_support,
        Map.merge(
          base_parameter(label: "time_support"),
          %{default_time: nil}
        ),
        :time,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    date_support =
      Unit.new(
        :date_support,
        Map.merge(
          base_parameter(label: "date_support"),
          %{default_date: nil}
        ),
        :date,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    boolean_support =
      Unit.new(
        :boolean_support,
        Map.merge(
          base_parameter(label: "boolean_support", nullable: false),
          %{default_boolean: true}
        ),
        :boolean,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    integer_support =
      Unit.new(
        :integer_support,
        Map.merge(
          base_parameter(label: "integer_support"),
          %{min: nil, max: nil, values: nil, multiple: false, unique: false, default_integer: nil}
        ),
        :integer,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    enum_integer_support =
      Unit.new(
        :enum_integer_support,
        Map.merge(
          base_parameter(label: "enum_integer_support"),
          %{min: nil, max: nil, values: nil, multiple: false, unique: false, default_integer: nil}
        ),
        :integer,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    float_support =
      Unit.new(
        :float_support,
        Map.merge(
          base_parameter(label: "float_support"),
          %{min: nil, max: nil, values: nil, multiple: false, unique: false, default_float: nil}
        ),
        :float,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    enum_float_support =
      Unit.new(
        :enum_float_support,
        Map.merge(
          base_parameter(label: "enum_float_support"),
          %{min: nil, max: nil, values: nil, multiple: false, unique: false, default_float: nil}
        ),
        :float,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    list_support =
      Unit.new(
        :list_support,
        Map.merge(
          base_parameter(label: "list_support"),
          %{default_list: nil}
        ),
        :list,
        nil,
        %{},
        nil,
        nil,
        nil
      )

    parameters = [
      string_support,
      dict_support,
      date_support,
      datetime_support,
      time_support,
      integer_support,
      enum_float_support,
      enum_integer_support,
      enum_string_support,
      float_support,
      list_support,
      boolean_support
    ]

    Enum.map(parameters, fn parameter ->
      ParameterManager.create(parameter, :arke_system)
    end)
  end
end
