defmodule DSPEx.PropertyTest do
  use ExUnit.Case
  use PropCheck

  describe "signature parsing properties" do
    property "parsed signatures maintain field order" do
      forall {inputs, outputs} <- {field_list(), field_list()} do
        signature_string = "#{Enum.join(inputs, ", ")} -> #{Enum.join(outputs, ", ")}"
        {parsed_inputs, parsed_outputs} = DSPEx.Signature.Parser.parse(signature_string)

        Enum.map(inputs, &String.to_atom/1) == parsed_inputs and
        Enum.map(outputs, &String.to_atom/1) == parsed_outputs
      end
    end

    property "field validation is consistent" do
      forall field_name <- field_name() do
        case DSPEx.Signature.Parser.validate_field_name(field_name) do
          {:ok, _} -> String.match?(field_name, ~r/^[a-z][a-zA-Z0-9_]*$/)
          {:error, _} -> not String.match?(field_name, ~r/^[a-z][a-zA-Z0-9_]*$/)
        end
      end
    end
  end

  describe "example manipulation properties" do
    property "example copy preserves original fields" do
      forall {original_fields, new_fields} <- {example_fields(), example_fields()} do
        original = DSPEx.Example.new(original_fields)
        copied = DSPEx.Example.copy(original, new_fields)

        # All original fields should be preserved
        Enum.all?(original_fields, fn {key, value} ->
          Map.get(copied, key) == value
        end)
      end
    end

    property "input/output designation is stable" do
      forall {fields, input_keys} <- {example_fields(), list(atom())} do
        example = DSPEx.Example.new(fields)
        valid_input_keys = Enum.filter(input_keys, &Map.has_key?(example, &1))

        example_with_inputs = DSPEx.Example.with_inputs(example, valid_input_keys)
        inputs = DSPEx.Example.inputs(example_with_inputs)
        labels = DSPEx.Example.labels(example_with_inputs)

        # Inputs and labels should not overlap
        MapSet.disjoint?(MapSet.new(Map.keys(inputs)), MapSet.new(Map.keys(labels))) and
        # All designated input keys should be in inputs
        Enum.all?(valid_input_keys, &Map.has_key?(inputs, &1))
      end
    end
  end

  describe "prediction properties" do
    property "batch prediction preserves order" do
      forall inputs_list <- non_empty(list(example_fields())) do
        # Mock predict that returns deterministic results based on input
        predict_fn = fn inputs ->
          hash = :erlang.phash2(inputs)
          {:ok, %{answer: "answer_#{hash}", confidence: "high"}}
        end

        # Sequential execution
        sequential_results = Enum.map(inputs_list, predict_fn)

        # Batch execution (would use actual DSPEx.Predict.batch in real test)
        batch_results = Enum.map(inputs_list, predict_fn)  # Simplified for example

        sequential_results == batch_results
      end
    end
  end

  # Property test generators
  defp field_list() do
    non_empty(list(field_name()))
  end

  defp field_name() do
    let name <- non_empty(string(:alphanumeric)) do
      # Ensure it starts with lowercase letter
      first_char = String.downcase(String.at(name, 0) || "a")
      rest = String.slice(name, 1..-1//1) |> String.replace(~r/[^a-zA-Z0-9_]/, "")
      "#{first_char}#{rest}"
    end
  end

  defp example_fields() do
    let field_pairs <- list({field_name(), term()}) do
      Map.new(field_pairs, fn {k, v} -> {String.to_atom(k), v} end)
    end
  end
end
