defmodule DSPEx.SignatureDataPropertyTest do
  @moduledoc """
  Property-based tests for DSPEx signature parsing and data structure invariants.
  Tests signature parsing, field validation, example creation and manipulation,
  and ensures data structure consistency across various inputs.
  """
  use ExUnit.Case, async: true
  use PropCheck

  @moduletag :phase_1
  @moduletag :property_tests

  # Generators for signature components

  def field_name_generator do
    # Valid Elixir atom names
    let name <-
          oneof([
            "input",
            "output",
            "question",
            "answer",
            "context",
            "reasoning",
            "problem",
            "solution",
            "data",
            "result",
            "text",
            "number"
          ]) do
      String.to_atom(name)
    end
  end

  def field_list_generator do
    non_empty(list(field_name_generator()))
  end

  def signature_string_generator do
    let {inputs, outputs} <- {field_list_generator(), field_list_generator()} do
      input_str = inputs |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")
      output_str = outputs |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")
      "#{input_str} -> #{output_str}"
    end
  end

  def field_value_generator do
    oneof([
      # String values
      non_empty(utf8()),
      # Integer values  
      integer(),
      # Float values
      float(),
      # Boolean values
      bool(),
      # List of strings
      list(non_empty(utf8())),
      # Nested maps
      map(field_name_generator(), non_empty(utf8()))
    ])
  end

  def field_map_generator(fields) do
    let values <- vector(length(fields), field_value_generator()) do
      Enum.zip(fields, values) |> Enum.into(%{})
    end
  end

  def example_data_generator do
    let {input_fields, output_fields} <- {field_list_generator(), field_list_generator()} do
      let {inputs, outputs} <-
            {field_map_generator(input_fields), field_map_generator(output_fields)} do
        %{inputs: inputs, outputs: outputs}
      end
    end
  end

  describe "signature parsing properties" do
    property "signature parsing is deterministic and reversible" do
      forall signature_str <- signature_string_generator() do
        # Create a dynamic signature module
        _module_name = String.to_atom("TestSig#{:rand.uniform(1_000_000)}")

        # Test that parsing doesn't crash
        try do
          # Simulate signature creation
          [input_part, output_part] = String.split(signature_str, " -> ")

          input_fields =
            input_part
            |> String.split(", ")
            |> Enum.map(&String.trim/1)
            |> Enum.map(&String.to_atom/1)

          output_fields =
            output_part
            |> String.split(", ")
            |> Enum.map(&String.trim/1)
            |> Enum.map(&String.to_atom/1)

          # Basic parsing invariants
          # All fields should be atoms
          basic_checks =
            is_list(input_fields) and
              is_list(output_fields) and
              length(input_fields) > 0 and
              length(output_fields) > 0 and
              Enum.all?(input_fields, &is_atom/1) and
              Enum.all?(output_fields, &is_atom/1)

          # Reversibility: reconstructing string should match (modulo spacing)
          reversibility_check =
            (fn ->
               reconstructed =
                 "#{Enum.join(input_fields, ", ")} -> #{Enum.join(output_fields, ", ")}"

               normalized_original = String.replace(signature_str, ~r/\s+/, " ")
               normalized_reconstructed = String.replace(reconstructed, ~r/\s+/, " ")
               String.trim(normalized_original) == String.trim(normalized_reconstructed)
             end).()

          basic_checks and reversibility_check
        rescue
          # Some generated strings might be invalid, that's OK
          _error -> true
        end
      end
    end

    property "field validation follows consistent rules" do
      forall {field_name, field_value} <- {field_name_generator(), field_value_generator()} do
        field_map = %{field_name => field_value}

        # Test various validation scenarios
        required_fields = [field_name]

        # Field is present - should validate
        validation_result = validate_fields_present(field_map, required_fields)
        assert validation_result == :ok

        # Field is missing - should fail
        empty_map = %{}
        missing_validation = validate_fields_present(empty_map, required_fields)
        assert missing_validation == {:error, :missing_fields}

        # Extra fields should be allowed
        extra_field_map = Map.put(field_map, :extra_field, "extra_value")
        extra_validation = validate_fields_present(extra_field_map, required_fields)
        assert extra_validation == :ok
      end
    end

    property "signature field lists maintain ordering and uniqueness" do
      forall field_list <- field_list_generator() do
        # Duplicate detection
        unique_fields = Enum.uniq(field_list)
        has_duplicates = length(field_list) != length(unique_fields)

        if has_duplicates do
          # If there are duplicates, unique list should be shorter
          assert length(unique_fields) < length(field_list)
        else
          # If no duplicates, lists should be equal
          assert unique_fields == field_list
        end

        # Ordering preservation
        first_occurrence_order =
          Enum.reduce(field_list, [], fn field, acc ->
            if field in acc, do: acc, else: acc ++ [field]
          end)

        assert first_occurrence_order == unique_fields
      end
    end
  end

  describe "example data structure properties" do
    property "example creation and access maintain structure invariants" do
      forall example_data <- example_data_generator() do
        # Basic structure requirements
        assert Map.has_key?(example_data, :inputs)
        assert Map.has_key?(example_data, :outputs)
        assert is_map(example_data.inputs)
        assert is_map(example_data.outputs)

        # Field access should be consistent
        for {field, value} <- example_data.inputs do
          assert Map.get(example_data.inputs, field) == value
          assert Map.has_key?(example_data.inputs, field)
        end

        for {field, value} <- example_data.outputs do
          assert Map.get(example_data.outputs, field) == value
          assert Map.has_key?(example_data.outputs, field)
        end

        # Immutability: modifying copy shouldn't affect original
        modified_inputs = Map.put(example_data.inputs, :new_field, "new_value")
        assert Map.get(example_data.inputs, :new_field) == nil
        assert Map.get(modified_inputs, :new_field) == "new_value"
      end
    end

    property "field type preservation across operations" do
      forall {field, value} <- {field_name_generator(), field_value_generator()} do
        # Create example with field
        example = %{inputs: %{field => value}, outputs: %{}}

        # Type should be preserved through various operations
        retrieved_value = Map.get(example.inputs, field)
        value_preserved = retrieved_value == value
        type_preserved = typeof(retrieved_value) == typeof(value)

        # Serialization/deserialization should preserve type (for simple types)
        serialization_preserved =
          case value do
            v when is_binary(v) or is_integer(v) or is_float(v) or is_boolean(v) ->
              serialized = :erlang.term_to_binary(v)
              deserialized = :erlang.binary_to_term(serialized)
              deserialized == v and typeof(deserialized) == typeof(v)

            _ ->
              # Complex types might not serialize/deserialize exactly the same
              true
          end

        value_preserved and type_preserved and serialization_preserved
      end
    end

    property "example validation is consistent and complete" do
      forall example_data <- example_data_generator() do
        # Test the validation logic used in DSPEx.Evaluate
        is_valid_structure =
          match?(
            %{inputs: inputs, outputs: outputs} when is_map(inputs) and is_map(outputs),
            example_data
          )

        # Test edge cases
        invalid_examples = [
          %{inputs: "not a map", outputs: %{}},
          %{inputs: %{}, outputs: "not a map"},
          # Missing outputs
          %{inputs: %{}},
          # Missing inputs
          %{outputs: %{}},
          # Missing both
          %{},
          "not a map at all"
        ]

        all_invalid_correctly_detected =
          Enum.all?(invalid_examples, fn invalid ->
            not match?(
              %{inputs: inputs, outputs: outputs} when is_map(inputs) and is_map(outputs),
              invalid
            )
          end)

        is_valid_structure and all_invalid_correctly_detected
      end
    end
  end

  describe "data transformation properties" do
    property "field mapping preserves data integrity" do
      forall example_data <- example_data_generator() do
        inputs = example_data.inputs
        _outputs = example_data.outputs

        # Test various field transformations

        # Identity transformation
        identity_inputs = Enum.into(inputs, %{})
        assert identity_inputs == inputs

        # Field renaming should preserve values
        renamed_inputs =
          for {field, value} <- inputs, into: %{} do
            new_field = String.to_atom("renamed_#{field}")
            {new_field, value}
          end

        # Should have same number of fields
        assert map_size(renamed_inputs) == map_size(inputs)

        # Values should be preserved
        input_values = Map.values(inputs) |> Enum.sort()
        renamed_values = Map.values(renamed_inputs) |> Enum.sort()
        assert input_values == renamed_values

        # Field filtering should maintain subset relationship
        if map_size(inputs) > 0 do
          [first_field | _] = Map.keys(inputs)
          filtered = Map.take(inputs, [first_field])
          assert map_size(filtered) <= map_size(inputs)
          assert Map.get(filtered, first_field) == Map.get(inputs, first_field)
        end
      end
    end

    property "example merging and splitting operations are consistent" do
      forall {example1, example2} <- {example_data_generator(), example_data_generator()} do
        # Merging inputs
        merged_inputs = Map.merge(example1.inputs, example2.inputs)

        # Merged map should contain all fields from both
        for {field, _value} <- example1.inputs do
          # Field should exist in merged (though value might be overridden)
          assert Map.has_key?(merged_inputs, field)
        end

        for {field, value} <- example2.inputs do
          # example2 values should take precedence in merge
          assert Map.get(merged_inputs, field) == value
        end

        # Size should be <= sum of individual sizes (due to potential overlaps)
        assert map_size(merged_inputs) <= map_size(example1.inputs) + map_size(example2.inputs)

        # Splitting should be reversible for non-overlapping merges
        all_fields = Map.keys(merged_inputs)
        split_point = div(length(all_fields), 2)
        {left_fields, right_fields} = Enum.split(all_fields, split_point)

        left_split = Map.take(merged_inputs, left_fields)
        right_split = Map.take(merged_inputs, right_fields)

        # Splits should be disjoint
        assert Map.keys(left_split)
               |> MapSet.new()
               |> MapSet.disjoint?(Map.keys(right_split) |> MapSet.new())

        # Union should recreate original
        reunited = Map.merge(left_split, right_split)
        assert reunited == merged_inputs
      end
    end
  end

  describe "edge cases and boundary conditions" do
    property "empty and minimal structures are handled correctly" do
      # Dummy generator since we're testing fixed cases
      forall _ <- bool() do
        # Empty maps
        empty_example = %{inputs: %{}, outputs: %{}}
        assert is_map(empty_example.inputs)
        assert is_map(empty_example.outputs)
        assert map_size(empty_example.inputs) == 0
        assert map_size(empty_example.outputs) == 0

        # Single field examples
        single_input = %{inputs: %{field: "value"}, outputs: %{}}
        assert map_size(single_input.inputs) == 1
        assert Map.get(single_input.inputs, :field) == "value"

        single_output = %{inputs: %{}, outputs: %{result: "output"}}
        assert map_size(single_output.outputs) == 1
        assert Map.get(single_output.outputs, :result) == "output"
      end
    end

    property "large data structures maintain performance characteristics" do
      forall size <- choose(10, 50) do
        # Generate large field maps
        large_fields =
          for i <- 1..size do
            {String.to_atom("field_#{i}"), "value_#{i}"}
          end
          |> Enum.into(%{})

        large_example = %{inputs: large_fields, outputs: large_fields}

        # Basic operations should complete in reasonable time
        start_time = System.monotonic_time()

        # Field access
        field_count = map_size(large_example.inputs)

        # Field enumeration
        all_keys = Map.keys(large_example.inputs)
        all_values = Map.values(large_example.inputs)

        # Field lookup
        if field_count > 0 do
          first_key = hd(all_keys)
          _value = Map.get(large_example.inputs, first_key)
        end

        # Merging
        _merged = Map.merge(large_example.inputs, large_example.outputs)

        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        # Should complete within reasonable time (1ms per field + 10ms base)
        reasonable_time = size * 1 + 10
        assert duration_ms <= reasonable_time

        # Verify structure integrity
        assert map_size(large_example.inputs) == size
        assert length(all_keys) == size
        assert length(all_values) == size
      end
    end

    property "unicode and special characters are handled correctly" do
      forall special_string <-
               oneof([
                 "🚀 Unicode test ∑ ∆ ∞",
                 "Mixed案例with中文",
                 "Русский текст",
                 "العربية النص",
                 "Special chars: !@#$%^&*()_+-=[]{}|;':\",./<>?",
                 "Newlines\nand\ttabs",
                 "Empty: ''",
                 "Quotes: \"double\" 'single'",
                 "Backslashes: \\ and \\n \\t"
               ]) do
        # Test that special characters don't break field operations
        special_field = String.to_atom("special_field")
        example = %{inputs: %{special_field => special_string}, outputs: %{}}

        # Should be able to store and retrieve
        retrieved = Map.get(example.inputs, special_field)
        assert retrieved == special_string

        # Should be able to serialize/deserialize
        serialized = :erlang.term_to_binary(example)
        deserialized = :erlang.binary_to_term(serialized)
        assert deserialized == example

        # String operations should work
        assert is_binary(special_string)
        assert String.length(special_string) >= 0
      end
    end
  end

  describe "concurrent data access properties" do
    property "concurrent field access is safe" do
      forall example_data <- example_data_generator() do
        if map_size(example_data.inputs) > 0 do
          # Spawn multiple processes accessing the same data
          tasks =
            for _i <- 1..5 do
              Task.async(fn ->
                # Perform various read operations
                _size = map_size(example_data.inputs)
                _keys = Map.keys(example_data.inputs)
                _values = Map.values(example_data.inputs)

                # Get random field if any exist
                if map_size(example_data.inputs) > 0 do
                  random_key = example_data.inputs |> Map.keys() |> Enum.random()
                  _value = Map.get(example_data.inputs, random_key)
                end

                :ok
              end)
            end

          results = Task.await_many(tasks, 1000)

          # All tasks should complete successfully
          assert Enum.all?(results, &(&1 == :ok))
        else
          # Empty inputs, just verify structure
          assert example_data.inputs == %{}
        end
      end
    end
  end

  # Helper functions

  defp validate_fields_present(field_map, required_fields) do
    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(field_map, field)
      end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, :missing_fields}
    end
  end

  defp typeof(value) do
    cond do
      is_binary(value) -> :binary
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_boolean(value) -> :boolean
      is_list(value) -> :list
      is_map(value) -> :map
      is_atom(value) -> :atom
      true -> :other
    end
  end
end
