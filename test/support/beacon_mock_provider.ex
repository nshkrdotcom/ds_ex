defmodule DSPEx.Test.BeaconMockProvider do
  @moduledoc """
  Specialized mock provider for BEACON optimization workflows and bootstrap testing.

  This module provides high-level mock setup functions specifically designed for
  testing teleprompter optimization workflows, bootstrap few-shot learning,
  and BEACON-related functionality.
  """

  alias DSPEx.MockClientManager

  @doc """
  Sets up mock responses for bootstrap few-shot learning scenarios.

  ## Parameters

  - `teacher_responses` - List of responses that the teacher program should return
    Can be strings, maps with :content key, or {:error, reason} tuples

  ## Examples

      # Simple string responses
      setup_bootstrap_mocks(["4", "6", "Paris"])
      
      # Map responses 
      setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"}, 
        %{content: "Paris"}
      ])
      
      # Mix of success and error responses
      setup_bootstrap_mocks([
        %{content: "4"},
        {:error, :api_error},
        %{content: "Paris"}
      ])
  """
  def setup_bootstrap_mocks(teacher_responses) when is_list(teacher_responses) do
    # Normalize responses to the expected format: %{content: "string"}
    clean_responses =
      Enum.map(teacher_responses, fn response ->
        case response do
          %{content: content} when is_binary(content) ->
            %{content: content}

          %{content: %{content: content}} when is_binary(content) ->
            # Handle double-wrapped content
            %{content: content}

          content when is_binary(content) ->
            %{content: content}

          {:error, _} = error ->
            # Pass through error responses
            error

          other ->
            # Fallback for unknown formats
            %{content: "Mock response"}
        end
      end)

    # Expand responses to ensure we have enough for all potential requests
    # The bootstrap process may make multiple requests per example
    expanded_responses = clean_responses ++ clean_responses ++ clean_responses

    # Set up responses for common teacher providers
    [:teacher, :test, :openai, :gpt4, :gemini]
    |> Enum.each(fn provider ->
      MockClientManager.set_mock_responses(provider, expanded_responses)
    end)

    :ok
  end

  @doc """
  Sets up mock responses for instruction generation workflows.
  """
  def setup_instruction_generation_mocks(instruction_responses)
      when is_list(instruction_responses) do
    # Set up responses for instruction generation providers
    [:instruction_generator, :teacher, :test]
    |> Enum.each(fn provider ->
      MockClientManager.set_mock_responses(provider, instruction_responses)
    end)

    :ok
  end

  @doc """
  Sets up mock responses for evaluation workflows with specific scores.

  ## Parameters

  - `score_map` - Map of evaluation scenarios to scores, or list of scores

  ## Examples

      # Map format
      setup_evaluation_mocks(%{
        "math_qa" => 0.9,
        "reasoning" => 0.8,
        "factual" => 0.95
      })
      
      # List format (converted to indexed map)
      setup_evaluation_mocks([0.9, 0.8, 0.95])
  """
  def setup_evaluation_mocks(score_map) when is_map(score_map) do
    # Convert scores to response format
    responses =
      score_map
      |> Enum.map(fn {_key, score} ->
        %{content: Float.to_string(score)}
      end)

    [:evaluator, :test, :student]
    |> Enum.each(fn provider ->
      MockClientManager.set_mock_responses(provider, responses)
    end)

    :ok
  end

  def setup_evaluation_mocks(scores) when is_list(scores) do
    responses = Enum.map(scores, fn score -> %{content: Float.to_string(score)} end)

    [:evaluator, :test, :student]
    |> Enum.each(fn provider ->
      MockClientManager.set_mock_responses(provider, responses)
    end)

    :ok
  end

  @doc """
  Sets up comprehensive BEACON optimization workflow mocks.

  This is a high-level function that configures mocks for a complete
  optimization workflow including teacher responses, student evaluation,
  and progress tracking.
  """
  def setup_beacon_optimization_mocks(config) when is_map(config) do
    # Set up teacher responses if provided
    if teacher_responses = config[:teacher_responses] do
      setup_bootstrap_mocks(teacher_responses)
    end

    # Set up evaluation scores if provided
    if evaluation_scores = config[:evaluation_scores] do
      setup_evaluation_mocks(evaluation_scores)
    end

    # Set up instruction generation if provided
    if instruction_responses = config[:instruction_responses] do
      setup_instruction_generation_mocks(instruction_responses)
    end

    :ok
  end

  @doc """
  Resets all BEACON-related mock state.
  """
  def reset_all_beacon_mocks do
    # Clear all mock responses
    MockClientManager.clear_all_mock_responses()
    :ok
  end

  @doc """
  Sets up default successful mock responses for common test scenarios.

  This is a convenience function that sets up reasonable defaults for
  most bootstrap testing scenarios.
  """
  def setup_default_successful_mocks do
    # Default teacher responses for common QA scenarios
    default_teacher_responses = [
      # Math: 2+2
      %{content: "4"},
      # Math: 3+3
      %{content: "6"},
      # Geography: capital of France
      %{content: "Paris"},
      # Logic: apple problem
      %{content: "16"},
      # General math
      %{content: "42"},
      # Generic geography
      %{content: "The capital city"},
      # Fallback
      %{content: "Mock answer"},
      # Add more variety to handle edge cases
      %{content: "Test response"},
      %{content: "Bootstrap answer"},
      %{content: "Teacher output"}
    ]

    # Default evaluation scores (high success rate)
    default_scores = [0.9, 0.85, 0.92, 0.88, 0.91, 0.87, 0.90]

    setup_bootstrap_mocks(default_teacher_responses)
    setup_evaluation_mocks(default_scores)

    :ok
  end

  @doc """
  Sets up mock responses that will fail to test error handling.
  """
  def setup_failing_mocks do
    failing_responses = [
      {:error, :api_error},
      {:error, :network_error},
      {:error, :timeout},
      {:error, :rate_limit}
    ]

    setup_bootstrap_mocks(failing_responses)
    :ok
  end
end
