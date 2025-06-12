defmodule DSPEx.SignatureExtensionTest do
  @moduledoc """
  Unit tests for DSPEx.Signature extension capabilities.

  CRITICAL: SIMBA references DSPEx.Signature.extend/2 for ChainOfThought patterns.
  This functionality is essential for creating signatures with additional
  reasoning fields that SIMBA's optimization algorithms require.
  """
  use ExUnit.Case, async: true

  alias DSPEx.Signature

  @moduletag :integration_2

  # Create base test signatures
  defmodule SimpleSignature do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule ComplexSignature do
    use DSPEx.Signature, "context, question -> answer, confidence"
  end

  describe "extend/2 creates new signatures with additional fields" do
    test "extends simple signature with reasoning field" do
      # This is the exact pattern SIMBA uses for ChainOfThought
      additional_fields = %{
        reasoning: %{
          description: "Step-by-step reasoning process",
          position: :before_outputs
        }
      }

      {:ok, extended_module} = Signature.extend(SimpleSignature, additional_fields)

      # Verify the extended signature exists and is usable
      assert Code.ensure_loaded?(extended_module)

      # Should have all original fields plus new ones
      assert :question in extended_module.input_fields()
      assert :answer in extended_module.output_fields()
      assert :reasoning in extended_module.output_fields()

      # Should implement Signature behavior
      assert function_exported?(extended_module, :input_fields, 0)
      assert function_exported?(extended_module, :output_fields, 0)
      assert function_exported?(extended_module, :instructions, 0)
    end

    test "extends complex signature with multiple additional fields" do
      additional_fields = %{
        reasoning: %{description: "Detailed reasoning", position: :output},
        confidence: %{description: "Confidence score", position: :output},
        sources: %{description: "Reference sources", position: :output}
      }

      {:ok, extended_module} = Signature.extend(ComplexSignature, additional_fields)

      # Original fields preserved
      assert :context in extended_module.input_fields()
      assert :question in extended_module.input_fields()
      assert :answer in extended_module.output_fields()

      # New fields added (note: ComplexSignature already has confidence)
      assert :reasoning in extended_module.output_fields()
      assert :sources in extended_module.output_fields()

      # Should be able to create instances
      instance = extended_module.new(%{
        context: "Test context",
        question: "Test question",
        answer: "Test answer",
        reasoning: "Test reasoning",
        sources: ["source1", "source2"]
      })

      assert is_struct(instance, extended_module)
    end

    test "handles field positioning correctly" do
      additional_fields = %{
        preliminary_analysis: %{position: :input},
        reasoning: %{position: :before_outputs},
        final_check: %{position: :output}
      }

      {:ok, extended_module} = Signature.extend(SimpleSignature, additional_fields)

      inputs = extended_module.input_fields()
      outputs = extended_module.output_fields()

      # Check positioning
      assert :question in inputs  # Original input
      assert :preliminary_analysis in inputs  # New input
      assert :reasoning in inputs  # Before outputs = input

      assert :answer in outputs  # Original output
      assert :final_check in outputs  # New output
    end

    test "extended signature has enhanced instructions" do
      additional_fields = %{
        reasoning: %{
          description: "Show your step-by-step thinking process",
          position: :before_outputs
        }
      }

      {:ok, extended_module} = Signature.extend(SimpleSignature, additional_fields)

      instructions = extended_module.instructions()

      # Should include base instructions
      assert String.contains?(instructions, "question")
      assert String.contains?(instructions, "answer")

      # Should include additional field descriptions
      assert String.contains?(instructions, "Additional requirements")
      assert String.contains?(instructions, "reasoning")
      assert String.contains?(instructions, "step-by-step thinking")
    end
  end

  describe "get_field_info/2 provides comprehensive field metadata" do
    test "returns detailed information for signature fields" do
      {:ok, field_info} = Signature.get_field_info(SimpleSignature, :question)

      assert field_info.name == :question
      assert field_info.is_input == true
      assert field_info.is_output == false
      assert field_info.type == :string  # Inferred from name
      assert is_binary(field_info.description)
    end

    test "handles output fields correctly" do
      {:ok, field_info} = Signature.get_field_info(SimpleSignature, :answer)

      assert field_info.name == :answer
      assert field_info.is_input == false
      assert field_info.is_output == true
      assert field_info.type == :string
    end

    test "returns error for non-existent fields" do
      assert {:error, :field_not_found} = Signature.get_field_info(SimpleSignature, :nonexistent)
    end

    test "works with extended signatures" do
      additional_fields = %{reasoning: %{description: "Reasoning process"}}
      {:ok, extended_module} = Signature.extend(SimpleSignature, additional_fields)

      # Original field
      {:ok, question_info} = Signature.get_field_info(extended_module, :question)
      assert question_info.is_input == true

      # Extended field
      {:ok, reasoning_info} = Signature.get_field_info(extended_module, :reasoning)
      assert reasoning_info.is_output == true
      assert reasoning_info.name == :reasoning
    end
  end

  describe "validate_signature_compatibility/2 for program composition" do
    test "validates compatible signatures" do
      # Create signatures where output of first can be input to second
      defmodule ProcessingSignature do
        use DSPEx.Signature, "raw_data -> processed_data"
      end

      defmodule AnalysisSignature do
        use DSPEx.Signature, "processed_data -> analysis_result"
      end

      # These should be compatible for chaining
      assert :ok = Signature.validate_signature_compatibility(
        ProcessingSignature,
        AnalysisSignature
      )
    end

    test "identifies incompatible signatures" do
      defmodule FirstSignature do
        use DSPEx.Signature, "input_a -> output_x"
      end

      defmodule SecondSignature do
        use DSPEx.Signature, "input_y -> output_z"
      end

      # No overlap between outputs and inputs
      assert {:error, {:incompatible_signatures, details}} =
        Signature.validate_signature_compatibility(FirstSignature, SecondSignature)

      assert is_list(details.sig1_outputs)
      assert is_list(details.sig2_inputs)
      assert is_list(details.overlap)
      assert Enum.empty?(details.overlap)
    end

    test "handles partial compatibility" do
      defmodule MultiOutputSignature do
        use DSPEx.Signature, "input -> output_a, output_b, output_c"
      end

      defmodule SelectiveInputSignature do
        use DSPEx.Signature, "output_b, other_input -> result"
      end

      # Partial overlap should be OK
      assert :ok = Signature.validate_signature_compatibility(
        MultiOutputSignature,
        SelectiveInputSignature
      )
    end
  end

  describe "enhanced signature introspection" do
    test "introspect/1 provides comprehensive metadata" do
      metadata = Signature.introspect(ComplexSignature)

      assert metadata.name == :ComplexSignature
      assert metadata.input_fields == [:context, :question]
      assert metadata.output_fields == [:answer, :confidence]
      assert metadata.all_fields == [:context, :question, :answer, :confidence]
      assert is_binary(metadata.instructions)
      assert metadata.field_count == 4
      assert is_number(metadata.complexity_score)
      assert is_map(metadata.validation_rules)
    end

    test "validate_signature_implementation/1 checks completeness" do
      # Valid signature
      assert :ok = Signature.validate_signature_implementation(SimpleSignature)
      assert :ok = Signature.validate_signature_implementation(ComplexSignature)

      # Create incomplete signature for testing
      defmodule IncompleteSignature do
        # Missing some required functions
        def input_fields(), do: [:input]
        # Missing output_fields, instructions, fields
      end

      {:error, missing} = Signature.validate_signature_implementation(IncompleteSignature)
      assert :output_fields in missing
      assert :instructions in missing
      assert :fields in missing
    end

    test "safe_description/1 handles missing description gracefully" do
      # Should work with normal signatures
      description = Signature.safe_description(SimpleSignature)
      assert is_binary(description)
      assert String.length(description) > 0

      # Should handle signatures without proper instructions
      defmodule NoDescriptionSignature do
        def input_fields(), do: [:input]
        def output_fields(), do: [:output]
        def fields(), do: [:input, :output]
        # Missing instructions function
      end

      description = Signature.safe_description(NoDescriptionSignature)
      assert is_binary(description)
      assert String.contains?(description, "input")
      assert String.contains?(description, "output")
    end

    test "field_statistics/1 calculates signature metrics" do
      stats = Signature.field_statistics(ComplexSignature)

      assert stats.input_count == 2
      assert stats.output_count == 2
      assert stats.total_fields == 4
      assert stats.input_output_ratio == 1.0
      assert stats.complexity in [:simple, :moderate, :complex, :very_complex]
    end
  end

  describe "error handling and edge cases" do
    test "extend/2 handles invalid base signatures" do
      # Non-existent module
      assert {:error, _} = Signature.extend(NonExistentSignature, %{})

      # Module that doesn't implement Signature behavior
      defmodule NotASignature do
        def some_function(), do: :ok
      end

      assert {:error, _} = Signature.extend(NotASignature, %{})
    end

    test "extend/2 handles invalid additional fields" do
      # Empty additional fields
      {:ok, extended} = Signature.extend(SimpleSignature, %{})

      # Should be same as original
      assert extended.input_fields() == SimpleSignature.input_fields()
      assert extended.output_fields() == SimpleSignature.output_fields()
    end

    test "extend/2 prevents field name conflicts" do
      # Try to add field that already exists
      conflicting_fields = %{
        question: %{description: "Duplicate field name"}
      }

      assert {:error, _} = Signature.extend(SimpleSignature, conflicting_fields)
    end

    test "extended signatures are properly isolated" do
      # Create multiple extensions of the same base
      fields1 = %{reasoning: %{description: "Reasoning 1"}}
      fields2 = %{analysis: %{description: "Analysis 1"}}

      {:ok, ext1} = Signature.extend(SimpleSignature, fields1)
      {:ok, ext2} = Signature.extend(SimpleSignature, fields2)

      # Should be different modules
      assert ext1 != ext2

      # Should have different fields
      assert :reasoning in ext1.output_fields()
      refute :reasoning in ext2.output_fields()

      assert :analysis in ext2.output_fields()
      refute :analysis in ext1.output_fields()
    end

    test "handles malformed field configurations" do
      malformed_fields = %{
        bad_field: "not a map",
        another_bad: nil
      }

      # Should handle gracefully
      {:ok, extended} = Signature.extend(SimpleSignature, malformed_fields)

      # Fields should be added as outputs by default
      assert :bad_field in extended.output_fields()
      assert :another_bad in extended.output_fields()
    end
  end

  describe "performance and memory characteristics" do
    test "signature extension is reasonably fast" do
      additional_fields = %{
        reasoning: %{description: "Fast reasoning"},
        confidence: %{description: "Confidence level"}
      }

      {time, {:ok, _extended}} = :timer.tc(fn ->
        Signature.extend(SimpleSignature, additional_fields)
      end)

      # Should complete quickly (< 10ms)
      assert time < 10000
    end

    test "multiple extensions don't leak memory excessively" do
      initial_memory = :erlang.memory(:total)

      # Create many extensions
      for i <- 1..20 do
        fields = %{
          "field_#{i}" |> String.to_atom() => %{description: "Field #{i}"}
        }
        {:ok, _} = Signature.extend(SimpleSignature, fields)
      end

      :erlang.garbage_collect()
      final_memory = :erlang.memory(:total)

      memory_growth = final_memory - initial_memory
      memory_growth_mb = memory_growth / (1024 * 1024)

      # Should not grow excessively
      assert memory_growth_mb < 10  # Less than 10MB for 20 extensions
    end

    test "introspection functions are efficient" do
      # Should be fast even for complex signatures
      {time, _metadata} = :timer.tc(fn ->
        Signature.introspect(ComplexSignature)
      end)

      assert time < 1000  # < 1ms

      {time, _stats} = :timer.tc(fn ->
        Signature.field_statistics(ComplexSignature)
      end)

      assert time < 1000  # < 1ms
    end
  end

  describe "SIMBA-specific requirements" do
    test "ChainOfThought pattern extension works correctly" do
      # This mimics exactly how SIMBA will extend signatures for ChainOfThought
      additional_fields = %{
        reasoning: %{
          description: "Think step by step about this problem",
          position: :before_outputs
        }
      }

      {:ok, cot_signature} = Signature.extend(SimpleSignature, additional_fields)

      # Should have reasoning as input (before outputs)
      assert :reasoning in cot_signature.input_fields()
      assert :question in cot_signature.input_fields()
      assert :answer in cot_signature.output_fields()

      # Should be able to create instances
      instance = cot_signature.new(%{
        question: "What is the capital of France?",
        reasoning: "I need to recall European geography...",
        answer: "Paris"
      })

      assert is_struct(instance, cot_signature)
      assert instance.question == "What is the capital of France?"
      assert instance.reasoning == "I need to recall European geography..."
      assert instance.answer == "Paris"
    end

    test "multiple reasoning fields for complex SIMBA patterns" do
      # SIMBA might create signatures with multiple reasoning stages
      multi_stage_fields = %{
        initial_analysis: %{
          description: "Initial problem analysis",
          position: :before_outputs
        },
        reasoning_steps: %{
          description: "Step-by-step reasoning",
          position: :before_outputs
        },
        confidence_assessment: %{
          description: "Confidence in the answer",
          position: :output
        }
      }

      {:ok, complex_reasoning} = Signature.extend(SimpleSignature, multi_stage_fields)

      inputs = complex_reasoning.input_fields()
      outputs = complex_reasoning.output_fields()

      # Should have all reasoning fields properly positioned
      assert :question in inputs
      assert :initial_analysis in inputs
      assert :reasoning_steps in inputs

      assert :answer in outputs
      assert :confidence_assessment in outputs

      # Should work with validation
      assert :ok = complex_reasoning.validate_inputs(%{
        question: "Test",
        initial_analysis: "Analysis",
        reasoning_steps: "Steps"
      })
    end

    test "extended signatures work with Program.forward" do
      # SIMBA will use extended signatures in actual program execution
      additional_fields = %{reasoning: %{description: "Reasoning"}}
      {:ok, extended_sig} = Signature.extend(SimpleSignature, additional_fields)

      # Should be usable in a Predict program
      program = %DSPEx.Predict{
        signature: extended_sig,
        client: :test
      }

      # Should be a valid program structure
      assert DSPEx.Program.implements_program?(DSPEx.Predict)

      # Program should have the extended signature
      assert program.signature == extended_sig
    end
  end
end
