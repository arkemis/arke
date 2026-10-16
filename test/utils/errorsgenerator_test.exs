defmodule Arke.Utils.ErrorGeneratorTest do
  use ExUnit.Case

  test "Arke.Utils.ErrorGenerator.create/2 when is_list" do
    errors = ["label is required", "username invalid"]

    assert Arke.Utils.ErrorGenerator.create(:test, errors) ==
             {:error,
              [
                %{context: "test", message: "label is required"},
                %{context: "test", message: "username invalid"}
              ]}
  end

  # PARAMETER VALIDATION ERROR FORMAT
  test "Arke.Utils.ErrorGenerator.create/2 when is_list(values)" do
    errors = [
      {"Max", "must be an integer"},
      {"allowed values for type are", ["customer", "admin", "super_admin"]}
    ]

    assert Arke.Utils.ErrorGenerator.create(:test, errors) ==
             {:error,
              [
                %{context: "test", message: "Max: must be an integer"},
                %{
                  context: "test",
                  message: "allowed values for type are: customer, admin, super_admin"
                }
              ]}
  end

  test "Arke.Utils.ErrorGenerator.create/2 when is_binary" do
    errors = "label must be a string"

    assert Arke.Utils.ErrorGenerator.create(:test, errors) ==
             {:error, [%{context: "test", message: "label must be a string"}]}
  end

  test "Arke.Utils.ErrorGenerator.create/2 invalid format" do
    errors = {12, [{"Label", "must be a string"}]}

    assert Arke.Utils.ErrorGenerator.create(:test, errors) ==
             {:error, [%{context: "error_generator", message: "invalid attribute format"}]}
  end

  describe "code" do
    test "is absent unless given" do
      {:error, [error]} = Arke.Utils.ErrorGenerator.create(:test, "boom")
      refute Map.has_key?(error, :code)
    end

    test "from opts, on every error" do
      assert Arke.Utils.ErrorGenerator.create(:test, ["a", "b"], code: "test.boom") ==
               {:error,
                [
                  %{context: "test", message: "a", code: "test.boom"},
                  %{context: "test", message: "b", code: "test.boom"}
                ]}

      assert Arke.Utils.ErrorGenerator.create(:test, :boom, code: "test.boom") ==
               {:error, [%{context: "test", message: "boom", code: "test.boom"}]}
    end

    test "from a 3-tuple, per error" do
      errors = [
        {"Max", "must be an integer", "parameter.invalid_type"},
        {"allowed values for type are", ["a", "b"], "parameter.not_allowed_value"},
        {"Label", "is required"}
      ]

      assert Arke.Utils.ErrorGenerator.create(:test, errors) ==
               {:error,
                [
                  %{
                    context: "test",
                    message: "Max: must be an integer",
                    code: "parameter.invalid_type"
                  },
                  %{
                    context: "test",
                    message: "allowed values for type are: a, b",
                    code: "parameter.not_allowed_value"
                  },
                  %{context: "test", message: "Label: is required"}
                ]}
    end

    test "a 3-tuple code wins over opts" do
      assert Arke.Utils.ErrorGenerator.create(:test, [{"Max", "too big", "own"}, "plain"],
               code: "default"
             ) ==
               {:error,
                [
                  %{context: "test", message: "Max: too big", code: "own"},
                  %{context: "test", message: "plain", code: "default"}
                ]}
    end
  end
end
