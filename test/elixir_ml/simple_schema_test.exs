defmodule ElixirML.SimpleSchemaTest do
  use ExUnit.Case, async: true

  alias ElixirML.Schema.Types

  describe "ML-specific type validation" do
    test "validates embedding type" do
      assert {:ok, [1.0, 2.0, 3.0]} = Types.validate_type([1.0, 2.0, 3.0], :embedding)
      assert {:error, _} = Types.validate_type("not a list", :embedding)
      assert {:error, _} = Types.validate_type([1, "2", 3], :embedding)
    end

    test "validates probability type" do
      assert {:ok, 0.5} = Types.validate_type(0.5, :probability)
      assert {:ok, 0.0} = Types.validate_type(0.0, :probability)
      assert {:ok, 1.0} = Types.validate_type(1.0, :probability)
      assert {:error, _} = Types.validate_type(1.5, :probability)
      assert {:error, _} = Types.validate_type(-0.1, :probability)
    end

    test "validates confidence score type" do
      assert {:ok, 0.8} = Types.validate_type(0.8, :confidence_score)
      # Can exceed 1.0
      assert {:ok, 1.2} = Types.validate_type(1.2, :confidence_score)
      assert {:error, _} = Types.validate_type(-0.1, :confidence_score)
    end

    test "validates token list type" do
      assert {:ok, ["hello", "world"]} = Types.validate_type(["hello", "world"], :token_list)
      assert {:ok, [1, 2, 3]} = Types.validate_type([1, 2, 3], :token_list)
      assert {:ok, ["hello", 123]} = Types.validate_type(["hello", 123], :token_list)
      assert {:error, _} = Types.validate_type(["hello", 1.5], :token_list)
    end

    test "validates model response type" do
      assert {:ok, %{text: "response"}} =
               Types.validate_type(%{text: "response"}, :model_response)

      assert {:ok, %{"text" => "response"}} =
               Types.validate_type(%{"text" => "response"}, :model_response)

      assert {:error, _} = Types.validate_type(%{content: "response"}, :model_response)
    end

    test "validates tensor type" do
      assert {:ok, [[1.0, 2.0], [3.0, 4.0]]} =
               Types.validate_type([[1.0, 2.0], [3.0, 4.0]], :tensor)

      assert {:ok, [1.0, 2.0, 3.0]} = Types.validate_type([1.0, 2.0, 3.0], :tensor)
      assert {:error, _} = Types.validate_type([["mixed", 2.0]], :tensor)
    end

    test "validates basic types" do
      assert {:ok, "hello"} = Types.validate_type("hello", :string)
      assert {:ok, 42} = Types.validate_type(42, :integer)
      assert {:ok, 3.14} = Types.validate_type(3.14, :float)
      assert {:ok, true} = Types.validate_type(true, :boolean)
      assert {:ok, %{}} = Types.validate_type(%{}, :map)
      assert {:ok, []} = Types.validate_type([], :list)
    end
  end

  describe "runtime schema validation" do
    test "creates and validates runtime schema" do
      runtime_schema =
        ElixirML.Schema.create([
          {:text, :string, required: true},
          {:score, :probability, default: 0.5}
        ])

      valid_data = %{text: "hello world"}
      assert {:ok, validated} = ElixirML.Schema.Runtime.validate(runtime_schema, valid_data)
      assert validated.text == "hello world"
      assert validated.score == 0.5
    end

    test "runtime schema handles missing required fields" do
      runtime_schema =
        ElixirML.Schema.create([
          {:text, :string, required: true}
        ])

      invalid_data = %{score: 0.8}
      assert {:error, error} = ElixirML.Schema.Runtime.validate(runtime_schema, invalid_data)
      assert error.message =~ "text"
      assert error.message =~ "required"
    end

    test "runtime schema validates types" do
      runtime_schema =
        ElixirML.Schema.create([
          {:embedding, :embedding, required: true}
        ])

      valid_data = %{embedding: [1.0, 2.0, 3.0]}
      assert {:ok, _} = ElixirML.Schema.Runtime.validate(runtime_schema, valid_data)

      invalid_data = %{embedding: "not an embedding"}
      assert {:error, _} = ElixirML.Schema.Runtime.validate(runtime_schema, invalid_data)
    end
  end

  describe "JSON schema generation" do
    test "runtime schema generates JSON schema" do
      runtime_schema =
        ElixirML.Schema.create([
          {:embedding, :embedding, required: true},
          {:confidence, :probability, default: 0.5}
        ])

      json_schema = ElixirML.Schema.Runtime.to_json_schema(runtime_schema)

      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema["properties"], "embedding")
      assert Map.has_key?(json_schema["properties"], "confidence")
      assert "embedding" in json_schema["required"]
      refute "confidence" in json_schema["required"]
    end
  end
end
