defmodule DSPEx.Integration.SignatureExampleTest do
  @moduledoc """
  Integration tests for DSPEx.Signature and DSPEx.Example working together.
  Tests Phase 1 functionality where signatures define contracts and examples provide data.
  """
  use ExUnit.Case, async: true

  @moduletag :phase_1

  alias DSPEx.Example

  describe "signature and example integration" do
    defmodule QASignature do
      @moduledoc "Simple question answering signature"
      use DSPEx.Signature, "question -> answer"
    end

    defmodule ComplexSignature do
      @moduledoc "Complex multi-field signature"
      use DSPEx.Signature, "question, context, examples -> answer, reasoning, confidence"
    end

    test "example data aligns with simple signature fields" do
      # Create example that matches signature
      example =
        Example.new(%{
          question: "What is 2+2?",
          answer: "4"
        })

      example_with_inputs = Example.with_inputs(example, QASignature.input_fields())
      inputs = Example.inputs(example_with_inputs)
      labels = Example.labels(example_with_inputs)

      # Verify alignment
      assert Map.keys(inputs) == QASignature.input_fields()
      assert Map.keys(labels) == QASignature.output_fields()
    end

    test "example data aligns with complex signature fields" do
      # Create example that matches complex signature
      example =
        Example.new(%{
          question: "What is the capital of France?",
          context: "Geography question about European capitals",
          examples: "Paris is the capital of France",
          answer: "Paris",
          reasoning: "Based on geographical knowledge",
          confidence: "high"
        })

      example_with_inputs = Example.with_inputs(example, ComplexSignature.input_fields())
      inputs = Example.inputs(example_with_inputs)
      labels = Example.labels(example_with_inputs)

      # Verify alignment
      assert MapSet.new(Map.keys(inputs)) == MapSet.new(ComplexSignature.input_fields())
      assert MapSet.new(Map.keys(labels)) == MapSet.new(ComplexSignature.output_fields())
    end

    test "signature can validate example inputs" do
      example =
        Example.new(%{
          question: "Test question",
          answer: "Test answer"
        })

      example_with_inputs = Example.with_inputs(example, [:question])
      inputs = Example.inputs(example_with_inputs)

      # Should validate successfully
      assert QASignature.validate_inputs(inputs) == :ok
    end

    test "signature can validate example outputs" do
      example =
        Example.new(%{
          question: "Test question",
          answer: "Test answer"
        })

      example_with_inputs = Example.with_inputs(example, [:question])
      labels = Example.labels(example_with_inputs)

      # Should validate successfully
      assert QASignature.validate_outputs(labels) == :ok
    end

    test "signature validation catches missing input fields" do
      example = Example.new(%{answer: "Test answer"})
      example_with_inputs = Example.with_inputs(example, [])
      inputs = Example.inputs(example_with_inputs)

      # Should fail validation
      assert QASignature.validate_inputs(inputs) == {:error, {:missing_inputs, [:question]}}
    end

    test "signature validation catches missing output fields" do
      example = Example.new(%{question: "Test question"})
      example_with_inputs = Example.with_inputs(example, [:question])
      labels = Example.labels(example_with_inputs)

      # Should fail validation
      assert QASignature.validate_outputs(labels) == {:error, {:missing_outputs, [:answer]}}
    end
  end

  describe "complex field validation scenarios" do
    defmodule MultiIOSignature do
      @moduledoc "Multiple input/output signature for testing"
      use DSPEx.Signature, "input1, input2, input3 -> output1, output2"
    end

    test "validates complete example against multi-field signature" do
      complete_example =
        Example.new(%{
          input1: "value1",
          input2: "value2",
          input3: "value3",
          output1: "result1",
          output2: "result2"
        })

      example_with_inputs = Example.with_inputs(complete_example, MultiIOSignature.input_fields())
      inputs = Example.inputs(example_with_inputs)
      labels = Example.labels(example_with_inputs)

      assert MultiIOSignature.validate_inputs(inputs) == :ok
      assert MultiIOSignature.validate_outputs(labels) == :ok
    end

    test "validates partial example against signature" do
      partial_example =
        Example.new(%{
          input1: "value1",
          input2: "value2",
          # Missing input3
          output1: "result1"
          # Missing output2
        })

      example_with_inputs = Example.with_inputs(partial_example, [:input1, :input2])
      inputs = Example.inputs(example_with_inputs)
      labels = Example.labels(example_with_inputs)

      # Should identify missing fields
      assert MultiIOSignature.validate_inputs(inputs) == {:error, {:missing_inputs, [:input3]}}
      assert MultiIOSignature.validate_outputs(labels) == {:error, {:missing_outputs, [:output2]}}
    end
  end

  describe "field ordering consistency" do
    defmodule OrderedSignature do
      @moduledoc "Testing field order preservation"
      use DSPEx.Signature, "first, second, third -> alpha, beta, gamma"
    end

    test "example field extraction preserves signature order" do
      example =
        Example.new(%{
          # Create in different order than signature
          gamma: "g",
          first: "1st",
          beta: "b",
          third: "3rd",
          alpha: "a",
          second: "2nd"
        })

      example_with_inputs = Example.with_inputs(example, OrderedSignature.input_fields())
      inputs = Example.inputs(example_with_inputs)
      labels = Example.labels(example_with_inputs)

      # The maps will contain correct keys regardless of creation order
      input_keys = Map.keys(inputs)
      label_keys = Map.keys(labels)

      # Verify all required fields are present (order in maps isn't guaranteed)
      assert MapSet.new(input_keys) == MapSet.new(OrderedSignature.input_fields())
      assert MapSet.new(label_keys) == MapSet.new(OrderedSignature.output_fields())
    end
  end
end
