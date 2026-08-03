defmodule Arke.Utils.DefaultData do
  def get_arke_id(), do: get_parameters_id() ++ ["arke", "group"]

  def get_parameters_id(),
    do: [
      "boolean",
      "binary",
      "dict",
      "list",
      "float",
      "integer",
      "string",
      "unit",
      "link",
      "dynamic",
      "date",
      "datetime",
      "time"
    ]
end
