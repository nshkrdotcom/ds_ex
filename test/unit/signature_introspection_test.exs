defmodule DSPEx.SignatureIntrospectionTest do
  @moduledoc """
  Unit tests for DSPEx.Signature introspection capabilities.

  CRITICAL: BEACON references DSPEx.Signature introspection functions for
  validation and compatibility checking. These functions are essential
  for signature analysis and optimization workflows.
  """
  use ExUnit.Case, async: true

  alias DSPEx.Signature

  @moduletag :group_2

  # Create test signatures
  defmodule SimpleSignature do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule ComplexSignature do
    use DSPEx.Signature, "context, question -> answer, confidence"
  end

  defmodule MultiOutputSignature do
    use DSPEx.Signature, "input -> output_a, output_b, output_c"
  end

  defmodule SelectiveInputSignature do
    use DSPEx.Signature, "output_b, other_input -> result"
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
      assert :ok =
               Signature.validate_signature_compatibility(
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
      assert {:error, error_msg} =
               Signature.validate_signature_compatibility(FirstSignature, SecondSignature)

      assert is_binary(error_msg)
      assert String.contains?(error_msg, "do not match")
    end

    test "handles partial compatibility" do
      # Partial overlap should fail - consumer needs ALL inputs satisfied
      assert {:error, _error_msg} =
               Signature.validate_signature_compatibility(
                 MultiOutputSignature,
                 SelectiveInputSignature
               )
    end

    test "handles invalid modules" do
      # Non-existent module
      assert {:error, _} =
               Signature.validate_signature_compatibility(NonExistentSignature, SimpleSignature)

      # Module that doesn't implement Signature behavior
      defmodule NotASignatureModule do
        def some_function(), do: :ok
      end

      assert {:error, _} =
               Signature.validate_signature_compatibility(NotASignatureModule, SimpleSignature)
    end
  end

  describe "introspect/1 provides comprehensive metadata" do
    test "returns detailed information for simple signature" do
      {:ok, metadata} = Signature.introspect(SimpleSignature)

      assert metadata.module == SimpleSignature
      assert metadata.inputs == [:question]
      assert metadata.outputs == [:answer]
      assert metadata.all_fields == [:question, :answer]
      assert is_binary(metadata.instructions)
      assert metadata.field_count.inputs == 1
      assert metadata.field_count.outputs == 1
      assert metadata.field_count.total == 2
      assert %DateTime{} = metadata.introspected_at
    end

    test "returns detailed information for complex signature" do
      {:ok, metadata} = Signature.introspect(ComplexSignature)

      assert metadata.module == ComplexSignature
      assert metadata.inputs == [:context, :question]
      assert metadata.outputs == [:answer, :confidence]
      assert metadata.all_fields == [:context, :question, :answer, :confidence]
      assert metadata.field_count.inputs == 2
      assert metadata.field_count.outputs == 2
      assert metadata.field_count.total == 4
    end

    test "handles invalid signature modules" do
      # Non-existent module
      assert {:error, _} = Signature.introspect(NonExistentSignature)

      # Module that doesn't implement Signature behavior
      defmodule NotASignatureForIntrospect do
        def some_function(), do: :ok
      end

      assert {:error, _} = Signature.introspect(NotASignatureForIntrospect)
    end
  end

  describe "validate_signature_implementation/1 checks completeness" do
    test "validates complete signatures" do
      # Valid signatures
      assert :ok = Signature.validate_signature_implementation(SimpleSignature)
      assert :ok = Signature.validate_signature_implementation(ComplexSignature)
    end

    test "detects missing required functions" do
      # Create incomplete signature for testing
      defmodule IncompleteSignature do
        @behaviour DSPEx.Signature

        # Missing some required functions
        def input_fields(), do: [:input]
        # Missing output_fields, instructions, fields
      end

      assert {:error, error_msg} =
               Signature.validate_signature_implementation(IncompleteSignature)

      assert String.contains?(error_msg, "Missing required functions")
    end

    test "validates behavior implementation" do
      defmodule NonBehaviorSignature do
        # Has functions but doesn't declare behavior
        def input_fields(), do: [:input]
        def output_fields(), do: [:output]
        def fields(), do: [:input, :output]
        def instructions(), do: "test"
      end

      assert {:error, error_msg} =
               Signature.validate_signature_implementation(NonBehaviorSignature)

      assert String.contains?(error_msg, "does not implement DSPEx.Signature behavior")
    end

    test "validates field consistency" do
      defmodule InconsistentSignature do
        @behaviour DSPEx.Signature

        @impl DSPEx.Signature
        def input_fields(), do: [:input1, :input2]

        @impl DSPEx.Signature
        def output_fields(), do: [:output1]

        @impl DSPEx.Signature
        # Inconsistent with inputs+outputs
        def fields(), do: [:wrong, :fields]

        @impl DSPEx.Signature
        def instructions(), do: "test instructions"
      end

      assert {:error, error_msg} =
               Signature.validate_signature_implementation(InconsistentSignature)

      assert String.contains?(error_msg, "inconsistent")
    end

    test "validates return types" do
      defmodule BadReturnTypeSignature do
        @behaviour DSPEx.Signature

        @impl DSPEx.Signature
        # Should return list of atoms
        def input_fields(), do: "not a list"

        @impl DSPEx.Signature
        def output_fields(), do: [:output]

        @impl DSPEx.Signature
        def fields(), do: [:input, :output]

        @impl DSPEx.Signature
        def instructions(), do: "test"
      end

      assert {:error, error_msg} =
               Signature.validate_signature_implementation(BadReturnTypeSignature)

      assert String.contains?(error_msg, "must return a list of atoms")
    end
  end

  describe "field_statistics/1 calculates signature metrics" do
    test "calculates correct statistics for simple signature" do
      stats = Signature.field_statistics(SimpleSignature)

      assert stats.input_count == 1
      assert stats.output_count == 1
    end

    test "calculates correct statistics for complex signature" do
      stats = Signature.field_statistics(ComplexSignature)

      assert stats.input_count == 2
      assert stats.output_count == 2
    end

    test "handles invalid modules gracefully" do
      stats = Signature.field_statistics(NonExistentModule)

      assert stats.input_count == 0
      assert stats.output_count == 0
    end
  end

  describe "get_field_info/2 provides field metadata" do
    test "returns information for input fields" do
      {:ok, field_info} = Signature.get_field_info(SimpleSignature, :question)

      assert field_info.name == :question
      assert field_info.type == :input
      assert field_info.category == :input
    end

    test "returns information for output fields" do
      {:ok, field_info} = Signature.get_field_info(SimpleSignature, :answer)

      assert field_info.name == :answer
      assert field_info.type == :output
      assert field_info.category == :output
    end

    test "returns error for non-existent fields" do
      assert {:error, :field_not_found} = Signature.get_field_info(SimpleSignature, :nonexistent)
    end

    test "works with complex signatures" do
      {:ok, context_info} = Signature.get_field_info(ComplexSignature, :context)
      assert context_info.type == :input

      {:ok, confidence_info} = Signature.get_field_info(ComplexSignature, :confidence)
      assert confidence_info.type == :output
    end
  end

  describe "performance characteristics" do
    test "introspection functions are efficient" do
      # Should be fast even for complex signatures
      {time, {:ok, _metadata}} =
        :timer.tc(fn ->
          Signature.introspect(ComplexSignature)
        end)

      # < 1ms
      assert time < 1000

      {time, _stats} =
        :timer.tc(fn ->
          Signature.field_statistics(ComplexSignature)
        end)

      # < 1ms
      assert time < 1000
    end

    test "validation is reasonably fast" do
      {time, result} =
        :timer.tc(fn ->
          Signature.validate_signature_implementation(ComplexSignature)
        end)

      assert result == :ok
      # < 5ms
      assert time < 5000
    end

    test "compatibility checking is efficient" do
      # Create a signature that should be compatible
      defmodule CompatibleProducer do
        use DSPEx.Signature, "input -> question"
      end

      {time, result} =
        :timer.tc(fn ->
          Signature.validate_signature_compatibility(CompatibleProducer, SimpleSignature)
        end)

      assert result == :ok
      # < 1ms
      assert time < 1000
    end
  end

  describe "error handling and edge cases" do
    test "handles module loading errors gracefully" do
      # Non-existent modules should not crash
      assert {:error, _} = Signature.introspect(:NonExistentModule)
      assert {:error, _} = Signature.validate_signature_implementation(:NonExistentModule)

      stats = Signature.field_statistics(:NonExistentModule)
      assert stats.input_count == 0
      assert stats.output_count == 0
    end

    test "handles malformed signature modules" do
      defmodule MalformedSignature do
        # Has some functions but they crash
        def input_fields(), do: raise("error")
        def output_fields(), do: [:output]
        def fields(), do: [:input, :output]
        def instructions(), do: "test"
      end

      # Should handle errors gracefully
      assert {:error, _} = Signature.validate_signature_implementation(MalformedSignature)
      assert {:error, _} = Signature.introspect(MalformedSignature)

      # Statistics should handle gracefully
      stats = Signature.field_statistics(MalformedSignature)
      assert stats.input_count == 0
      assert stats.output_count == 0
    end
  end

  describe "BEACON-specific requirements" do
    test "all BEACON-required functions exist and work" do
      # BEACON requires these exact functions to exist
      assert function_exported?(Signature, :validate_signature_compatibility, 2)
      assert function_exported?(Signature, :introspect, 1)
      assert function_exported?(Signature, :validate_signature_implementation, 1)
      assert function_exported?(Signature, :field_statistics, 1)

      # Test with realistic BEACON usage scenarios
      assert :ok = Signature.validate_signature_implementation(SimpleSignature)

      {:ok, metadata} = Signature.introspect(SimpleSignature)
      assert is_map(metadata)

      stats = Signature.field_statistics(SimpleSignature)
      assert is_map(stats)
    end

    test "compatibility checking works for BEACON chaining scenarios" do
      # BEACON might chain multiple signatures
      defmodule StepOne do
        use DSPEx.Signature, "problem -> intermediate_result"
      end

      defmodule StepTwo do
        use DSPEx.Signature, "intermediate_result -> final_answer"
      end

      # Should be compatible for chaining
      assert :ok = Signature.validate_signature_compatibility(StepOne, StepTwo)

      # Should work in introspection
      {:ok, step1_info} = Signature.introspect(StepOne)
      {:ok, step2_info} = Signature.introspect(StepTwo)

      assert step1_info.outputs == [:intermediate_result]
      assert step2_info.inputs == [:intermediate_result]
    end

    test "introspection data is suitable for BEACON optimization metrics" do
      {:ok, metadata} = Signature.introspect(ComplexSignature)

      # BEACON needs this data for optimization decisions
      assert is_atom(metadata.module)
      assert is_list(metadata.inputs)
      assert is_list(metadata.outputs)
      assert is_map(metadata.field_count)
      assert is_integer(metadata.field_count.total)

      # All data should be serializable for telemetry
      # Test that we can convert to term that would be serializable
      assert is_map(metadata)

      assert Enum.all?(metadata, fn {_k, v} ->
               is_atom(v) or is_binary(v) or is_number(v) or is_list(v) or is_map(v) or is_nil(v)
             end)
    end

    test "validation works with extended signatures" do
      # BEACON extends signatures for ChainOfThought
      additional_fields = %{reasoning: "reasoning field"}
      {:ok, extended_module} = Signature.extend(SimpleSignature, additional_fields)

      # Extended signatures should pass validation
      assert :ok = Signature.validate_signature_implementation(extended_module)

      # Should be introspectable
      {:ok, metadata} = Signature.introspect(extended_module)
      assert :reasoning in metadata.outputs

      # Should have correct statistics
      stats = Signature.field_statistics(extended_module)
      # original input
      assert stats.input_count == 1
      # original output + reasoning
      assert stats.output_count == 2
    end
  end
end
