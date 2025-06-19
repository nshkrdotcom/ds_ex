defmodule DSPEx.Teleprompter.SIMBA.Signatures.OfferFeedbackTest do
  use ExUnit.Case
  alias DSPEx.Teleprompter.SIMBA.Signatures.OfferFeedback

  describe "OfferFeedback signature" do
    test "signature module exists and follows Sinter patterns" do
      # This test will fail until OfferFeedback signature is implemented
      assert Code.ensure_loaded?(OfferFeedback)
      assert function_exported?(OfferFeedback, :signature_definition, 0)
    end

    test "defines required input fields" do
      definition = OfferFeedback.signature_definition()

      # Verify all required input fields are present
      input_fields = Map.keys(definition.inputs)

      assert :program_code in input_fields
      assert :modules_defn in input_fields
      assert :better_program_trajectory in input_fields
      assert :worse_program_trajectory in input_fields
    end

    test "defines module_advice output field" do
      definition = OfferFeedback.signature_definition()

      # Verify output field for generated advice
      output_fields = Map.keys(definition.outputs)

      assert :module_advice in output_fields

      # Verify it's configured as a map type
      assert definition.outputs[:module_advice].type == :map
    end

    test "validates input field requirements" do
      definition = OfferFeedback.signature_definition()

      # All input fields should be required
      Enum.each(definition.inputs, fn {_field, config} ->
        assert config.required == true
      end)

      # Trajectory fields should have minimum length requirements
      better_trajectory = definition.inputs[:better_program_trajectory]
      worse_trajectory = definition.inputs[:worse_program_trajectory]

      assert better_trajectory.min_length >= 50
      assert worse_trajectory.min_length >= 50
    end

    test "validates module_advice output format" do
      definition = OfferFeedback.signature_definition()
      _module_advice_field = definition.outputs[:module_advice]

      # Should have custom validation function
      assert function_exported?(OfferFeedback, :validate_module_advice, 1)

      # Test validation function with valid advice
      valid_advice = %{
        "main" => "Improve calculation accuracy by double-checking arithmetic.",
        "helper" => "Use more descriptive variable names for clarity."
      }

      assert OfferFeedback.validate_module_advice(valid_advice) == true
    end

    test "rejects invalid module_advice formats" do
      # Empty advice should be invalid
      assert OfferFeedback.validate_module_advice(%{}) == false

      # Non-map should be invalid
      assert OfferFeedback.validate_module_advice("not a map") == false

      # Advice with too-short values should be invalid
      short_advice = %{"main" => "bad"}
      assert OfferFeedback.validate_module_advice(short_advice) == false

      # Advice with non-string values should be invalid
      invalid_advice = %{"main" => 123}
      assert OfferFeedback.validate_module_advice(invalid_advice) == false
    end

    test "signature description and purpose are clear" do
      definition = OfferFeedback.signature_definition()

      # Should have meaningful description
      assert String.length(definition.description) > 20
      assert String.contains?(definition.description, ["instruction", "improve", "trajectory"])
    end

    test "integrates with DSPEx signature system" do
      # Should be compatible with DSPEx.Predict.new/2
      program = DSPEx.Predict.new(OfferFeedback, :test)

      assert program.signature == OfferFeedback
      # Program starts with nil instruction, can be set later
      assert program.instruction == nil
      assert program.demos == []

      # But the signature should provide instructions
      instructions = OfferFeedback.instructions()
      assert is_binary(instructions)
      assert String.length(instructions) > 0
    end

    test "supports signature compilation and validation" do
      # Test that signature can be used for actual LLM calls
      inputs = %{
        program_code: "def answer(question), do: String.upcase(question)",
        modules_defn: "Simple answering module",
        better_program_trajectory:
          "Input: 'What is 2+2?' -> Output: '4' (Score: 1.0, Success: true)",
        worse_program_trajectory:
          "Input: 'What is 3+3?' -> Output: 'WHAT IS 3+3?' (Score: 0.0, Success: false)"
      }

      # Signature should validate these inputs
      assert {:ok, validated_inputs} = OfferFeedback.validate_inputs(inputs)

      # Verify the validated inputs contain the expected data
      assert validated_inputs == inputs
      assert String.length(inputs.better_program_trajectory) >= 50
      assert String.length(inputs.worse_program_trajectory) >= 50
    end

    test "rejects invalid input combinations" do
      # Missing required fields should fail validation
      incomplete_inputs = %{
        program_code: "def answer(q), do: q"
        # Missing other required fields
      }

      assert {:error, _reason} = OfferFeedback.validate_inputs(incomplete_inputs)

      # Too-short trajectory descriptions should fail
      short_trajectory_inputs = %{
        program_code: "def answer(q), do: q",
        modules_defn: "Test module",
        # Too short
        better_program_trajectory: "short",
        # Too short
        worse_program_trajectory: "also short"
      }

      assert {:error, _reason} = OfferFeedback.validate_inputs(short_trajectory_inputs)
    end
  end
end
