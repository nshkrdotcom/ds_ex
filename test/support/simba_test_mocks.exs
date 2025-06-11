defmodule DSPEx.Test.SimbaMockProvider do
  @moduledoc """
  Enhanced mocking infrastructure for SIMBA optimization workflows.

  This module extends the existing DSPEx.MockClientManager with specialized
  mocking capabilities needed for testing complex SIMBA optimization scenarios,
  including bootstrapping, instruction generation, evaluation, and full
  optimization workflows.
  """

  alias DSPEx.MockClientManager

  @doc """
  Sets up mocks for bootstrap few-shot learning scenarios.

  Configures the mock client to return specific teacher responses
  that can be used to test bootstrap learning workflows.

  ## Parameters
    * `teacher_responses` - List of responses the teacher model should return
  """
  @spec setup_bootstrap_mocks(list(String.t())) :: :ok
  def setup_bootstrap_mocks(teacher_responses) do
    # Configure mock responses for bootstrap scenarios
    responses_with_metadata =
      teacher_responses
      |> Enum.with_index()
      |> Enum.map(fn {response, index} ->
        %{
          content: response,
          metadata: %{
            bootstrap_step: index + 1,
            total_steps: length(teacher_responses),
            model: :teacher,
            reasoning_quality: :high
          }
        }
      end)

    MockClientManager.set_mock_responses(:gpt4, responses_with_metadata)
    MockClientManager.set_mock_responses(:teacher, responses_with_metadata)

    :ok
  end

  @doc """
  Sets up mocks for instruction generation workflows.

  Configures responses for scenarios where the system generates
  instructions or prompts as part of the optimization process.
  """
  @spec setup_instruction_generation_mocks(list(String.t())) :: :ok
  def setup_instruction_generation_mocks(instruction_responses) do
    instruction_mocks =
      instruction_responses
      |> Enum.with_index()
      |> Enum.map(fn {instruction, index} ->
        %{
          content: instruction,
          metadata: %{
            instruction_type: :optimization,
            generation_step: index + 1,
            # Increasing quality
            quality_score: 0.85 + index * 0.02,
            model: :instruction_generator
          }
        }
      end)

    MockClientManager.set_mock_responses(:instruction_model, instruction_mocks)

    :ok
  end

  @doc """
  Sets up mocks for evaluation scenarios.

  Configures mock responses that return specific scores for testing
  evaluation logic and metric calculations.

  ## Parameters
    * `score_map` - Map of input patterns to expected scores
  """
  @spec setup_evaluation_mocks(map()) :: :ok
  def setup_evaluation_mocks(score_map) do
    # Create mock responses that simulate evaluation scoring
    evaluation_responses =
      score_map
      |> Enum.map(fn {pattern, score} ->
        %{
          content: "Evaluation complete",
          metadata: %{
            input_pattern: pattern,
            score: score,
            evaluation_type: :simba_metric,
            confidence: 0.9
          }
        }
      end)

    MockClientManager.set_mock_responses(:evaluator, evaluation_responses)

    :ok
  end

  @doc """
  Sets up comprehensive mocks for full SIMBA optimization workflows.

  This configures all the different types of responses needed for
  a complete optimization run, including teacher responses, student
  responses, evaluation scores, and iteration feedback.
  """
  @spec setup_simba_optimization_mocks(map()) :: :ok
  def setup_simba_optimization_mocks(config) do
    max_iterations = Map.get(config, :max_iterations, 3)
    base_score = Map.get(config, :base_score, 0.6)
    improvement_per_iteration = Map.get(config, :improvement_per_iteration, 0.1)

    # Setup teacher responses (high quality)
    teacher_responses = create_teacher_responses(max_iterations)
    setup_bootstrap_mocks(teacher_responses)

    # Setup student responses (improving over iterations)
    student_responses =
      create_student_responses(max_iterations, base_score, improvement_per_iteration)

    MockClientManager.set_mock_responses(:gpt3_5, student_responses)
    MockClientManager.set_mock_responses(:student, student_responses)

    # Setup evaluation responses (showing improvement)
    evaluation_scores =
      create_evaluation_scores(max_iterations, base_score, improvement_per_iteration)

    setup_evaluation_mocks(evaluation_scores)

    # Setup optimization metadata responses
    optimization_responses = create_optimization_metadata_responses(max_iterations)
    MockClientManager.set_mock_responses(:optimizer, optimization_responses)

    :ok
  end

  @doc """
  Resets all SIMBA-related mocks to clean state.

  This should be called between tests to ensure clean mock state.
  """
  @spec reset_all_simba_mocks() :: :ok
  def reset_all_simba_mocks() do
    # Reset all known mock providers
    providers = [:gpt4, :gpt3_5, :teacher, :student, :evaluator, :optimizer, :instruction_model]

    Enum.each(providers, fn provider ->
      MockClientManager.clear_mock_responses(provider)
    end)

    :ok
  end

  @doc """
  Creates realistic concurrent optimization scenario mocks.

  Sets up mocks that can handle concurrent requests with appropriate
  delays and responses to test system behavior under load.
  """
  @spec setup_concurrent_optimization_mocks(integer(), keyword()) :: :ok
  def setup_concurrent_optimization_mocks(concurrency_level, opts \\ []) do
    base_delay = Keyword.get(opts, :base_delay, 10)
    max_delay = Keyword.get(opts, :max_delay, 100)

    # Create responses with varying delays to simulate real-world concurrency
    concurrent_responses =
      1..concurrency_level
      |> Enum.map(fn i ->
        # Pseudo-random delay
        delay = base_delay + rem(i * 17, max_delay - base_delay)

        %{
          content: "Concurrent response #{i}",
          metadata: %{
            concurrent_id: i,
            processing_delay: delay,
            batch_size: concurrency_level
          },
          delay: delay
        }
      end)

    # Setup mocks for concurrent scenarios
    MockClientManager.set_mock_responses(:concurrent_teacher, concurrent_responses)
    MockClientManager.set_mock_responses(:concurrent_student, concurrent_responses)

    :ok
  end

  @doc """
  Configures mocks for error recovery testing.

  Sets up scenarios where some requests fail and the system
  needs to handle errors gracefully.
  """
  @spec setup_error_recovery_mocks() :: :ok
  def setup_error_recovery_mocks() do
    # Mix of successful and error responses
    error_recovery_responses = [
      %{content: "Success 1", metadata: %{step: 1}},
      %{error: :rate_limit, metadata: %{step: 2, retry_after: 100}},
      %{content: "Success after retry", metadata: %{step: 3, was_retry: true}},
      %{error: :timeout, metadata: %{step: 4}},
      %{content: "Final success", metadata: %{step: 5}}
    ]

    MockClientManager.set_mock_responses(:error_prone, error_recovery_responses)

    :ok
  end

  # Private helper functions

  defp create_teacher_responses(iterations) do
    1..iterations
    |> Enum.map(fn i ->
      "High quality teacher response for iteration #{i}. This demonstrates excellent reasoning and should serve as a good example for the student model."
    end)
  end

  defp create_student_responses(iterations, base_score, improvement) do
    1..iterations
    |> Enum.with_index()
    |> Enum.map(fn {iteration, index} ->
      quality_score = base_score + index * improvement

      %{
        content: "Student response for iteration #{iteration}. Quality improving over time.",
        metadata: %{
          iteration: iteration,
          quality_score: quality_score,
          improvement_over_baseline: index * improvement
        }
      }
    end)
  end

  defp create_evaluation_scores(iterations, base_score, improvement) do
    1..iterations
    |> Enum.with_index()
    |> Enum.into(%{}, fn {iteration, index} ->
      score = base_score + index * improvement
      {"iteration_#{iteration}", score}
    end)
  end

  defp create_optimization_metadata_responses(iterations) do
    1..iterations
    |> Enum.map(fn i ->
      %{
        content: "Optimization metadata",
        metadata: %{
          iteration: i,
          total_iterations: iterations,
          convergence_rate: 0.1 * i,
          optimization_method: :simba
        }
      }
    end)
  end

  @doc """
  Helper to validate that mocks are properly configured.

  Useful for debugging test setup issues.
  """
  @spec validate_mock_setup() :: :ok | {:error, term()}
  def validate_mock_setup() do
    # Check for any configured providers - we need at least some basic setup
    all_providers = [:gpt4, :gpt3_5, :teacher, :student, :evaluator, :instruction_model]

    configured_providers =
      all_providers
      |> Enum.filter(fn provider ->
        case MockClientManager.get_mock_responses(provider) do
          [] -> false
          _responses -> true
        end
      end)

    case configured_providers do
      [] -> {:error, {:no_mock_providers_configured, all_providers}}
      _configured -> :ok
    end
  end
end
