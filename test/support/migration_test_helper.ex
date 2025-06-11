defmodule DSPEx.Test.MigrationTestHelper do
  @moduledoc """
  Utilities for migrated tests from TODO_02_PRE_SIMBA and test_phase2.

  This module provides specialized helper functions needed during the test
  migration process, particularly for complex optimization test scenarios
  and SIMBA-related workflows.
  """

  alias DSPEx.{Program, Signature, Predict, OptimizedProgram}

  @doc """
  Creates a mock optimization configuration with default values.

  ## Options
    * `:max_iterations` - Maximum optimization iterations (default: 10)
    * `:concurrency` - Number of concurrent executions (default: 4)
    * `:timeout` - Timeout per operation in ms (default: 5000)
    * `:metric_threshold` - Minimum metric improvement (default: 0.1)
  """
  @spec create_mock_optimization_config(keyword()) :: map()
  def create_mock_optimization_config(opts \\ []) do
    %{
      max_iterations: Keyword.get(opts, :max_iterations, 10),
      concurrency: Keyword.get(opts, :concurrency, 4),
      timeout: Keyword.get(opts, :timeout, 5000),
      metric_threshold: Keyword.get(opts, :metric_threshold, 0.1),
      examples_per_iteration: Keyword.get(opts, :examples_per_iteration, 5),
      teacher_model: Keyword.get(opts, :teacher_model, :gpt4),
      student_model: Keyword.get(opts, :student_model, :gpt3_5)
    }
  end

  @doc """
  Simulates a concurrent optimization run for testing purposes.

  This function creates multiple concurrent tasks that run optimization
  scenarios, useful for testing system behavior under concurrent load.
  """
  @spec simulate_concurrent_optimization_run(Program.t(), list(), integer()) ::
          {:ok, list()} | {:error, term()}
  def simulate_concurrent_optimization_run(program, examples, concurrency) do
    tasks =
      1..concurrency
      |> Enum.map(fn _i ->
        Task.async(fn ->
          # Simulate optimization work with the program and examples
          # Simulate variable work time
          Process.sleep(Enum.random(10..50))

          case Program.forward(program, examples |> hd() |> Map.get(:inputs, %{})) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> {:error, reason}
          end
        end)
      end)

    results = Task.await_many(tasks, 10_000)

    # Filter successful results
    case Enum.split_with(results, fn
           {:ok, _} -> true
           _ -> false
         end) do
      {successes, []} ->
        {:ok, Enum.map(successes, fn {:ok, result} -> result end)}

      {successes, errors} ->
        {:error, %{successes: length(successes), errors: errors}}
    end
  end

  @doc """
  Asserts that optimization actually improves performance metrics.

  Compares before and after scores to ensure optimization is working.
  """
  @spec assert_optimization_improves_performance(list(number()), list(number())) :: :ok
  def assert_optimization_improves_performance(before_scores, after_scores) do
    before_avg = Enum.sum(before_scores) / length(before_scores)
    after_avg = Enum.sum(after_scores) / length(after_scores)

    improvement = after_avg - before_avg
    improvement_percentage = improvement / before_avg * 100

    # Assert meaningful improvement (at least 5% better)
    assert improvement > 0,
           "Optimization should improve performance, got #{improvement} change"

    assert improvement_percentage >= 5.0,
           "Optimization should improve performance by at least 5%, got #{improvement_percentage}%"

    :ok
  end

  @doc """
  Creates a test program with a specified number of demonstration examples.

  This is useful for testing teleprompter workflows that depend on
  programs having few-shot examples.
  """
  @spec create_test_program_with_demos(module(), integer()) :: Program.t()
  def create_test_program_with_demos(signature_module, demo_count) do
    base_program = Predict.new(signature_module, :gpt3_5)

    # Create demo examples based on signature
    demos = create_demo_examples_for_signature(signature_module, demo_count)

    # Create an optimized program that includes the demos
    %OptimizedProgram{
      base_program: base_program,
      examples: demos,
      optimization_metadata: %{
        method: :bootstrap_fewshot,
        demo_count: demo_count,
        created_at: DateTime.utc_now()
      }
    }
  end

  @doc """
  Creates realistic demo examples for a given signature module.

  This generates synthetic but realistic examples that match the
  signature's input/output format.
  """
  @spec create_demo_examples_for_signature(module(), integer()) :: list(map())
  def create_demo_examples_for_signature(signature_module, count) do
    # Get signature info to understand input/output fields
    case Signature.introspect(signature_module) do
      {:ok, signature_info} ->
        1..count
        |> Enum.map(fn i ->
          %{
            inputs: generate_sample_inputs(signature_info.inputs, i),
            outputs: generate_sample_outputs(signature_info.outputs, i)
          }
        end)

      {:error, _} ->
        # Fallback to generic examples if introspection fails
        create_generic_demo_examples(count)
    end
  end

  # Private helper functions

  defp generate_sample_inputs(input_fields, index) do
    input_fields
    |> Enum.into(%{}, fn field ->
      {field, "Sample input #{index} for #{field}"}
    end)
  end

  defp generate_sample_outputs(output_fields, index) do
    output_fields
    |> Enum.into(%{}, fn field ->
      {field, "Sample output #{index} for #{field}"}
    end)
  end

  defp create_generic_demo_examples(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        inputs: %{question: "What is #{i} + #{i}?"},
        outputs: %{answer: "#{i + i}"}
      }
    end)
  end

  @doc """
  Helper to create realistic test examples for various test scenarios.
  """
  @spec create_test_examples(atom(), integer()) :: list(map())
  def create_test_examples(type, count \\ 5)

  def create_test_examples(:math, count) do
    1..count
    |> Enum.map(fn i ->
      a = Enum.random(1..10)
      b = Enum.random(1..10)

      %{
        inputs: %{question: "What is #{a} + #{b}?"},
        outputs: %{answer: "#{a + b}"}
      }
    end)
  end

  def create_test_examples(:qa, count) do
    questions = [
      {"What is the capital of France?", "Paris"},
      {"What is 2 + 2?", "4"},
      {"What color is the sky?", "Blue"},
      {"What is the largest planet?", "Jupiter"},
      {"What year did humans land on the moon?", "1969"}
    ]

    questions
    |> Enum.take(count)
    |> Enum.map(fn {q, a} ->
      %{inputs: %{question: q}, outputs: %{answer: a}}
    end)
  end

  def create_test_examples(:reasoning, count) do
    1..count
    |> Enum.map(fn i ->
      %{
        inputs: %{
          context: "Context for reasoning problem #{i}",
          question: "Given the context, what can you conclude?"
        },
        outputs: %{
          reasoning: "Step-by-step reasoning for problem #{i}",
          conclusion: "Conclusion #{i}"
        }
      }
    end)
  end
end
