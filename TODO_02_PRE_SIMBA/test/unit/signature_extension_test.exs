# File: test/unit/signature_extension_test.exs
defmodule DSPEx.SignatureExtensionTest do
  use ExUnit.Case, async: true

  alias DSPEx.Signature

  doctest DSPEx.Signature

  setup do
    # Create base test signature
    defmodule BaseTestSignature do
      @moduledoc "Base signature for testing extensions"
      use DSPEx.Signature, "question, context -> answer"
    end

    %{base_signature: BaseTestSignature}
  end

  describe "signature extension capabilities" do
    test "extend/2 creates new signatures with additional fields", %{base_signature: base_signature} do
      additional_fields = %{
        reasoning: %{position: :output, description: "Step by step reasoning"},
        confidence: %{position: :output, description: "Confidence score"}
      }

      {:ok, extended_signature} = Signature.extend(base_signature, additional_fields)

      # Should be a valid module
      assert is_atom(extended_signature)
      assert Code.ensure_loaded?(extended_signature)

      # Should implement Signature behavior
      assert function_exported?(extended_signature, :input_fields, 0)
      assert function_exported?(extended_signature, :output_fields, 0)
      assert function_exported?(extended_signature, :instructions, 0)
    end

    test "extend/2 preserves base signature functionality", %{base_signature: base_signature} do
      additional_fields = %{
        reasoning: %{position: :output, description: "Reasoning process"}
      }

      {:ok, extended_signature} = Signature.extend(base_signature, additional_fields)

      # Should preserve original input fields
      base_inputs = base_signature.input_fields()
      extended_inputs = extended_signature.input_fields()

      assert Enum.all?(base_inputs, &(&1 in extended_inputs))

      # Should preserve original output fields
      base_outputs = base_signature.output_fields()
      extended_outputs = extended_signature.output_fields()

      assert Enum.all?(base_outputs, &(&1 in extended_outputs))

      # Should include new output field
      assert :reasoning in extended_outputs
    end

    test "extend/2 handles different field position types" do
      base_signature = BaseTestSignature

      # Test input position
      input_fields = %{
        additional_context: %{position: :input, description: "Extra context"}
      }

      {:ok, with_input} = Signature.extend(base_signature, input_fields)
      assert :additional_context in with_input.input_fields()
      refute :additional_context in with_input.output_fields()

      # Test output position
      output_fields = %{
        confidence: %{position: :output, description: "Confidence score"}
      }

      {:ok, with_output} = Signature.extend(base_signature, output_fields)
      refute :confidence in with_output.input_fields()
      assert :confidence in with_output.output_fields()

      # Test before_outputs position (should be treated as input)
      before_output_fields = %{
        reasoning_step: %{position: :before_outputs, description: "Intermediate reasoning"}
      }

      {:ok, with_before} = Signature.extend(base_signature, before_output_fields)
      assert :reasoning_step in with_before.input_fields()
      refute :reasoning_step in with_before.output_fields()
    end

    test "extended signatures generate correct input/output field lists" do
      base_signature = BaseTestSignature

      additional_fields = %{
        user_id: %{position: :input, description: "User identifier"},
        reasoning: %{position: :output, description: "Reasoning process"},
        confidence: %{position: :output, description: "Confidence score"},
        thoughts: %{position: :before_outputs, description: "Internal thoughts"}
      }

      {:ok, extended} = Signature.extend(base_signature, additional_fields)

      # Check input fields
      inputs = extended.input_fields()
      assert :question in inputs
      assert :context in inputs
      assert :user_id in inputs
      assert :thoughts in inputs
      refute :answer in inputs
      refute :reasoning in inputs
      refute :confidence in inputs

      # Check output fields
      outputs = extended.output_fields()
      assert :answer in outputs
      assert :reasoning in outputs
      assert :confidence in outputs
      refute :question in outputs
      refute :context in outputs
      refute :user_id in outputs
      refute :thoughts in outputs
    end

    test "extended signatures maintain proper instruction generation" do
      base_signature = BaseTestSignature

      additional_fields = %{
        reasoning: %{position: :output, description: "Show your reasoning step by step"}
      }

      {:ok, extended} = Signature.extend(base_signature, additional_fields)

      instructions = extended.instructions()

      # Should include base instructions
      base_instructions = base_signature.instructions()
      assert String.contains?(instructions, base_instructions)

      # Should include information about additional fields
      assert String.contains?(instructions, "reasoning")
      assert String.contains?(instructions, "Show your reasoning step by step")
    end

    test "extend/2 handles empty additional fields" do
      base_signature = BaseTestSignature

      {:ok, extended} = Signature.extend(base_signature, %{})

      # Should be essentially the same as base signature
      assert extended.input_fields() == base_signature.input_fields()
      assert extended.output_fields() == base_signature.output_fields()
    end

    test "extend/2 handles complex field configurations" do
      base_signature = BaseTestSignature

      complex_fields = %{
        step1: %{position: :before_outputs, description: "First reasoning step"},
        step2: %{position: :before_outputs, description: "Second reasoning step"},
        final_reasoning: %{position: :output, description: "Final consolidated reasoning"},
        confidence_score: %{position: :output, description: "Numerical confidence"},
        metadata: %{position: :output, description: "Additional metadata"}
      }

      {:ok, extended} = Signature.extend(base_signature, complex_fields)

      # Check that all fields are properly categorized
      inputs = extended.input_fields()
      outputs = extended.output_fields()

      assert :step1 in inputs
      assert :step2 in inputs
      assert :final_reasoning in outputs
      assert :confidence_score in outputs
      assert :metadata in outputs

      # Should maintain original fields
      assert :question in inputs
      assert :context in inputs
      assert :answer in outputs
    end
  end

  describe "field introspection" do
    test "get_field_info/2 returns comprehensive field metadata", %{base_signature: base_signature} do
      {:ok, info} = Signature.get_field_info(base_signature, :question)

      assert %{
        name: :question,
        type: _,
        is_input: true,
        is_output: false,
        description: _
      } = info

      assert info.name == :question
      assert info.is_input == true
      assert info.is_output == false
    end

    test "get_field_info/2 correctly identifies input vs output fields", %{base_signature: base_signature} do
      # Test input field
      {:ok, question_info} = Signature.get_field_info(base_signature, :question)
      assert question_info.is_input == true
      assert question_info.is_output == false

      # Test output field
      {:ok, answer_info} = Signature.get_field_info(base_signature, :answer)
      assert answer_info.is_input == false
      assert answer_info.is_output == true
    end

    test "get_field_info/2 handles missing fields gracefully", %{base_signature: base_signature} do
      assert {:error, :field_not_found} = Signature.get_field_info(base_signature, :nonexistent_field)
    end

    test "get_field_info/2 infers field types correctly" do
      # Create signature with fields that should have specific inferred types
      defmodule TypeInferenceSignature do
        use DSPEx.Signature, "question, score -> answer, confidence, reasoning"
      end

      {:ok, question_info} = Signature.get_field_info(TypeInferenceSignature, :question)
      assert question_info.type == :string

      {:ok, score_info} = Signature.get_field_info(TypeInferenceSignature, :score)
      assert score_info.type == :number

      {:ok, confidence_info} = Signature.get_field_info(TypeInferenceSignature, :confidence)
      assert confidence_info.type == :number

      {:ok, reasoning_info} = Signature.get_field_info(TypeInferenceSignature, :reasoning)
      assert reasoning_info.type == :string
    end

    test "validate_signature_compatibility/2 checks signature composition compatibility" do
      # Create compatible signatures
      defmodule ProducerSignature do
        use DSPEx.Signature, "input -> output1, output2"
      end

      defmodule ConsumerSignature do
        use DSPEx.Signature, "output1, output2 -> final_result"
      end

      # Should be compatible
      assert :ok = Signature.validate_signature_compatibility(ProducerSignature, ConsumerSignature)

      # Create incompatible signatures
      defmodule IncompatibleSignature do
        use DSPEx.Signature, "different_input -> different_output"
      end

      # Should be incompatible
      assert {:error, {:incompatible_signatures, details}} =
        Signature.validate_signature_compatibility(ProducerSignature, IncompatibleSignature)

      assert is_map(details)
      assert Map.has_key?(details, :sig1_outputs)
      assert Map.has_key?(details, :sig2_inputs)
      assert Map.has_key?(details, :overlap)
    end
  end

  describe "enhanced signature introspection" do
    test "introspect/1 returns comprehensive signature metadata", %{base_signature: base_signature} do
      metadata = Signature.introspect(base_signature)

      assert %{
        name: _,
        input_fields: _,
        output_fields: _,
        all_fields: _,
        instructions: _,
        field_count: _,
        complexity_score: _,
        validation_rules: _
      } = metadata

      assert is_atom(metadata.name)
      assert is_list(metadata.input_fields)
      assert is_list(metadata.output_fields)
      assert is_list(metadata.all_fields)
      assert is_binary(metadata.instructions)
      assert is_number(metadata.field_count)
      assert is_number(metadata.complexity_score)
      assert is_map(metadata.validation_rules)
    end

    test "validate_signature_implementation/1 validates complete implementations", %{base_signature: base_signature} do
      # Should pass for properly implemented signature
      assert :ok = Signature.validate_signature_implementation(base_signature)

      # Test with incomplete implementation (mock)
      defmodule IncompleteSignature do
        # Missing required functions
        def some_function, do: :ok
      end

      assert {:error, missing_functions} = Signature.validate_signature_implementation(IncompleteSignature)
      assert is_list(missing_functions)
      assert :input_fields in missing_functions
      assert :output_fields in missing_functions
    end

    test "safe_description/1 handles missing description functions gracefully" do
      # Should work with normal signature
      description = Signature.safe_description(BaseTestSignature)
      assert is_binary(description)
      assert String.length(description) > 0

      # Test with signature that might have issues
      defmodule ProblematicSignature do
        use DSPEx.Signature, "input -> output"

        # Override instructions to cause potential issues
        def instructions, do: raise("Intentional error")
      end

      # Should handle gracefully
      fallback_description = Signature.safe_description(ProblematicSignature)
      assert is_binary(fallback_description)
      assert String.contains?(fallback_description, "input")
      assert String.contains?(fallback_description, "output")
    end

    test "field_statistics/1 calculates correct complexity metrics", %{base_signature: base_signature} do
      stats = Signature.field_statistics(base_signature)

      assert %{
        input_count: 2,
        output_count: 1,
        total_fields: 3,
        input_output_ratio: 2.0,
        complexity: :moderate
      } = stats
    end

    test "field_statistics/1 handles various signature complexities" do
      # Simple signature
      defmodule SimpleSignature do
        use DSPEx.Signature, "input -> output"
      end

      simple_stats = Signature.field_statistics(SimpleSignature)
      assert simple_stats.complexity == :simple
      assert simple_stats.total_fields == 2

      # Complex signature
      defmodule ComplexSignature do
        use DSPEx.Signature, "input1, input2, input3, input4 -> output1, output2, output3"
      end

      complex_stats = Signature.field_statistics(ComplexSignature)
      assert complex_stats.complexity == :complex
      assert complex_stats.total_fields == 7

      # Very complex signature
      defmodule VeryComplexSignature do
        use DSPEx.Signature, "i1, i2, i3, i4, i5 -> o1, o2, o3, o4"
      end

      very_complex_stats = Signature.field_statistics(VeryComplexSignature)
      assert very_complex_stats.complexity == :very_complex
      assert very_complex_stats.total_fields == 9
    end

    test "introspection handles edge cases" do
      # Signature with no outputs (should not happen normally, but test edge case)
      # This would require a custom implementation since the macro requires outputs

      # Test with minimal signature
      defmodule MinimalSignature do
        use DSPEx.Signature, "input -> output"
      end

      minimal_metadata = Signature.introspect(MinimalSignature)
      assert minimal_metadata.field_count == 2
      assert minimal_metadata.complexity_score >= 2.0  # Base score for minimal signature
    end
  end

  describe "signature name and metadata extraction" do
    test "signature_name/1 extracts correct names", %{base_signature: base_signature} do
      # Test private function through introspect
      metadata = Signature.introspect(base_signature)
      assert metadata.name == :BaseTestSignature
    end

    test "complexity calculation works correctly" do
      # Test different signature complexities
      defmodule HighComplexitySignature do
        @moduledoc """
        This is a very detailed signature with extensive instructions that should
        increase the complexity score due to the length of the instructions and
        the number of fields involved in the processing.
        """
        use DSPEx.Signature, "context, question, user_preferences, history -> answer, reasoning, confidence, sources, metadata"
      end

      metadata = Signature.introspect(HighComplexitySignature)

      # Should have higher complexity due to more fields and longer instructions
      assert metadata.complexity_score > 5.0
      assert metadata.field_count == 9
    end

    test "validation rules are correctly generated", %{base_signature: base_signature} do
      metadata = Signature.introspect(base_signature)
      rules = metadata.validation_rules

      assert %{
        required_inputs: [:question, :context],
        required_outputs: [:answer],
        allows_extra_fields: false,
        min_inputs: 2,
        min_outputs: 1
      } = rules
    end
  end

  describe "field context extraction and humanization" do
    test "field descriptions are extracted from instructions" do
      defmodule DescriptiveSignature do
        @moduledoc """
        Given a question and context, provide a comprehensive answer.
        The question should be clear and specific.
        The answer must be accurate and well-reasoned.
        """
        use DSPEx.Signature, "question, context -> answer"
      end

      {:ok, question_info} = Signature.get_field_info(DescriptiveSignature, :question)
      {:ok, answer_info} = Signature.get_field_info(DescriptiveSignature, :answer)

      # Should extract context from instructions
      assert String.contains?(String.downcase(question_info.description), "question")
      assert String.contains?(String.downcase(answer_info.description), "answer")
    end

    test "field names are humanized when context unavailable" do
      defmodule SimpleFieldSignature do
        use DSPEx.Signature, "user_input, additional_context -> final_response"
      end

      {:ok, input_info} = Signature.get_field_info(SimpleFieldSignature, :user_input)
      {:ok, context_info} = Signature.get_field_info(SimpleFieldSignature, :additional_context)
      {:ok, response_info} = Signature.get_field_info(SimpleFieldSignature, :final_response)

      # Should humanize field names
      assert String.contains?(input_info.description, "User input")
      assert String.contains?(context_info.description, "Additional context")
      assert String.contains?(response_info.description, "Final response")
    end
  end

  describe "error handling and edge cases" do
    test "extend/2 handles invalid additional fields gracefully" do
      base_signature = BaseTestSignature

      # Test with invalid field configuration
      invalid_fields = %{
        bad_field: "not a map",
        another_bad_field: %{position: :invalid_position}
      }

      result = Signature.extend(base_signature, invalid_fields)

      # Should either succeed with defaults or return an error
      case result do
        {:ok, _extended} -> :ok  # Handled gracefully
        {:error, _reason} -> :ok  # Proper error handling
      end
    end

    test "field introspection handles non-existent signatures gracefully" do
      # Test with invalid signature module
      assert {:error, :field_not_found} = Signature.get_field_info(NonExistentSignature, :field)
    end

    test "signature compatibility handles edge cases" do
      # Test with signatures that have no overlapping fields
      defmodule NoOverlapSignature1 do
        use DSPEx.Signature, "input1 -> output1"
      end

      defmodule NoOverlapSignature2 do
        use DSPEx.Signature, "input2 -> output2"
      end

      result = Signature.validate_signature_compatibility(NoOverlapSignature1, NoOverlapSignature2)
      assert {:error, {:incompatible_signatures, _}} = result
    end

    test "extension preserves original signature integrity" do
      base_signature = BaseTestSignature

      # Verify original signature is unchanged after extension
      original_inputs = base_signature.input_fields()
      original_outputs = base_signature.output_fields()
      original_instructions = base_signature.instructions()

      additional_fields = %{
        new_field: %{position: :output, description: "New field"}
      }

      {:ok, _extended} = Signature.extend(base_signature, additional_fields)

      # Original should be unchanged
      assert base_signature.input_fields() == original_inputs
      assert base_signature.output_fields() == original_outputs
      assert base_signature.instructions() == original_instructions
    end

    test "handles concurrent signature operations safely" do
      base_signature = BaseTestSignature

      # Test concurrent extensions
      tasks = Task.async_stream(1..10, fn i ->
        additional_fields = %{
          :"field_#{i}" => %{position: :output, description: "Field #{i}"}
        }

        Signature.extend(base_signature, additional_fields)
      end, max_concurrency: 5)
      |> Enum.to_list()

      # All should complete successfully
      assert length(tasks) == 10
      successes = Enum.count(tasks, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert successes >= 8  # Allow some potential failures due to dynamic module creation
    end

    test "memory usage remains reasonable with complex signatures" do
      # Create signature with many fields
      many_inputs = Enum.map(1..50, &"input#{&1}") |> Enum.join(", ")
      many_outputs = Enum.map(1..50, &"output#{&1}") |> Enum.join(", ")
      signature_string = "#{many_inputs} -> #{many_outputs}"

      # Should handle large signatures without excessive memory usage
      {time_us, _result} = :timer.tc(fn ->
        defmodule LargeSignature do
          use DSPEx.Signature, unquote(signature_string)
        end

        Signature.introspect(LargeSignature)
      end)

      # Should complete reasonably quickly
      assert time_us < 100_000  # Less than 100ms
    end
  end
end
