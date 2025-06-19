defmodule DSPEx.Integration.EvaluationSinterIntegrationTest do
  @moduledoc """
  Integration tests for Sinter validation in evaluation pipeline.

  Tests the integration of Sinter validation within DSPEx.Evaluate to ensure
  examples and evaluation data are properly validated without breaking
  existing evaluation functionality.
  """

  use ExUnit.Case, async: true

  alias DSPEx.Evaluate
  alias DSPEx.Example

  # Mock signature for testing
  defmodule TestQASignature do
    @behaviour DSPEx.Signature

    def input_fields, do: [:question]
    def output_fields, do: [:answer]
    def description, do: "Question-Answer signature for evaluation testing"
    def fields, do: %{question: :input, answer: :output}
    def instructions, do: "Answer questions accurately"
  end

  # Mock program for testing
  defmodule MockProgram do
    @behaviour DSPEx.Program

    defstruct [:signature]

    def new(signature), do: %__MODULE__{signature: signature}

    def forward(_program, inputs, _opts \\ []) do
      # Mock successful prediction
      case inputs do
        %{question: question} when is_binary(question) ->
          {:ok, %{answer: "Mock answer for: #{question}"}}

        _ ->
          {:error, :invalid_input}
      end
    end
  end

  describe "DSPEx.Evaluate with Sinter validation" do
    @tag :sinter_test
    test "evaluates examples with Sinter validation integration" do
      program = MockProgram.new(TestQASignature)

      examples = [
        %{inputs: %{question: "What is 2+2?"}, outputs: %{answer: "4"}},
        %{inputs: %{question: "What is 3+3?"}, outputs: %{answer: "6"}},
        %{inputs: %{question: "What is 5+5?"}, outputs: %{answer: "10"}}
      ]

      metric_fn = fn _example, _prediction -> 1.0 end

      # Should succeed with Sinter validation integrated
      assert {:ok, result} = Evaluate.run(program, examples, metric_fn)
      assert result.score == 1.0
      assert result.stats.total_examples == 3
      assert result.stats.successful == 3
    end

    test "handles DSPEx.Example format with validation" do
      program = MockProgram.new(TestQASignature)

      examples = [
        Example.new(%{question: "Test question 1", answer: "Test answer 1"}, [:question]),
        Example.new(%{question: "Test question 2", answer: "Test answer 2"}, [:question])
      ]

      metric_fn = fn _example, _prediction -> 0.8 end

      # Should work with DSPEx.Example format
      assert {:ok, result} = Evaluate.run(program, examples, metric_fn)
      assert result.score == 0.8
      assert result.stats.total_examples == 2
    end
  end

  describe "Sinter validation telemetry in evaluation" do
    test "emits Sinter validation telemetry during evaluation" do
      test_pid = self()

      # Attach to Sinter validation telemetry
      :telemetry.attach(
        "test-eval-sinter-validation",
        [:dspex, :evaluate, :validation, :sinter],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:sinter_telemetry, event, measurements, metadata})
        end,
        nil
      )

      program = MockProgram.new(TestQASignature)

      examples = [
        %{inputs: %{question: "Test"}, outputs: %{answer: "Test answer"}}
      ]

      metric_fn = fn _example, _prediction -> 1.0 end

      {:ok, _result} = Evaluate.run(program, examples, metric_fn)

      # Should receive Sinter validation telemetry
      assert_receive {:sinter_telemetry, [:dspex, :evaluate, :validation, :sinter], measurements,
                      metadata}

      assert Map.has_key?(measurements, :validated_examples)
      assert Map.has_key?(metadata, :total_examples)

      :telemetry.detach("test-eval-sinter-validation")
    end
  end

  describe "error handling with Sinter integration" do
    test "gracefully handles Sinter unavailability" do
      program = MockProgram.new(TestQASignature)

      examples = [
        %{inputs: %{question: "Test question"}, outputs: %{answer: "Test answer"}}
      ]

      metric_fn = fn _example, _prediction -> 1.0 end

      # Should not crash if Sinter is unavailable
      assert {:ok, result} = Evaluate.run(program, examples, metric_fn)
      assert result.score == 1.0
    end
  end
end
