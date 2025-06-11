defmodule DSPEx.SimbaMockProviderTest do
  @moduledoc """
  Unit tests for SIMBA mock provider infrastructure.

  Tests the enhanced mocking capabilities needed for SIMBA optimization workflows,
  including bootstrap scenarios, instruction generation, and evaluation workflows.
  """
  use ExUnit.Case, async: false

  alias DSPEx.{Test.SimbaMockProvider, MockClientManager}

  @moduletag :phase_2

  setup do
    # Clean up any existing mock state
    SimbaMockProvider.reset_all_simba_mocks()
    MockClientManager.clear_all_mock_responses()

    on_exit(fn ->
      SimbaMockProvider.reset_all_simba_mocks()
      MockClientManager.clear_all_mock_responses()
    end)

    :ok
  end

  describe "bootstrap mock setup" do
    test "setup_bootstrap_mocks/1 configures teacher responses" do
      teacher_responses = [
        "The answer is 4 because 2+2 equals 4",
        "6 is the result of adding 3+3",
        "Paris is the capital city of France"
      ]

      assert :ok = SimbaMockProvider.setup_bootstrap_mocks(teacher_responses)

      # Verify responses were stored
      gpt4_responses = MockClientManager.get_mock_responses(:gpt4)
      teacher_responses_stored = MockClientManager.get_mock_responses(:teacher)

      assert length(gpt4_responses) == 3
      assert length(teacher_responses_stored) == 3

      # Verify response structure
      first_response = hd(gpt4_responses)
      assert %{content: content, metadata: metadata} = first_response
      assert is_binary(content)
      assert %{bootstrap_step: 1, total_steps: 3, model: :teacher} = metadata
    end

    test "setup_bootstrap_mocks/1 handles empty list" do
      assert :ok = SimbaMockProvider.setup_bootstrap_mocks([])

      responses = MockClientManager.get_mock_responses(:gpt4)
      assert responses == []
    end
  end

  describe "instruction generation mock setup" do
    test "setup_instruction_generation_mocks/1 configures instruction responses" do
      instruction_responses = [
        "Think step by step and show your reasoning",
        "Consider multiple perspectives before answering",
        "Use specific examples to support your conclusions"
      ]

      assert :ok = SimbaMockProvider.setup_instruction_generation_mocks(instruction_responses)

      # Verify responses were stored
      instruction_responses_stored = MockClientManager.get_mock_responses(:instruction_model)
      assert length(instruction_responses_stored) == 3

      # Verify response structure
      first_response = hd(instruction_responses_stored)
      assert %{content: content, metadata: metadata} = first_response
      assert is_binary(content)
      assert %{instruction_type: :optimization, generation_step: 1} = metadata
    end
  end

  describe "evaluation mock setup" do
    test "setup_evaluation_mocks/1 configures score responses" do
      score_map = %{
        "pattern1" => 0.8,
        "pattern2" => 0.9,
        "pattern3" => 0.7
      }

      assert :ok = SimbaMockProvider.setup_evaluation_mocks(score_map)

      # Verify responses were stored
      eval_responses = MockClientManager.get_mock_responses(:evaluator)
      assert length(eval_responses) == 3

      # Verify response structure
      first_response = hd(eval_responses)
      assert %{content: "Evaluation complete", metadata: metadata} = first_response
      assert %{evaluation_type: :simba_metric, confidence: 0.9} = metadata
    end
  end

  describe "comprehensive SIMBA optimization mocks" do
    test "setup_simba_optimization_mocks/1 configures full workflow" do
      config = %{
        max_iterations: 3,
        base_score: 0.6,
        improvement_per_iteration: 0.1
      }

      assert :ok = SimbaMockProvider.setup_simba_optimization_mocks(config)

      # Verify different provider responses were configured
      teacher_responses = MockClientManager.get_mock_responses(:teacher)
      student_responses = MockClientManager.get_mock_responses(:student)
      evaluator_responses = MockClientManager.get_mock_responses(:evaluator)

      assert length(teacher_responses) == 3
      assert length(student_responses) == 3
      assert length(evaluator_responses) == 3

      # Verify teacher responses
      teacher_response = hd(teacher_responses)
      assert %{content: content} = teacher_response
      assert String.contains?(content, "High quality teacher response")

      # Verify student responses show improvement
      student_scores =
        student_responses
        |> Enum.map(fn %{metadata: metadata} -> metadata.quality_score end)

      # Should be increasing
      assert Enum.sort(student_scores) == student_scores
    end

    test "setup_simba_optimization_mocks/1 uses default configuration" do
      assert :ok = SimbaMockProvider.setup_simba_optimization_mocks(%{})

      # Should still create responses with defaults
      teacher_responses = MockClientManager.get_mock_responses(:teacher)
      # Default max_iterations
      assert length(teacher_responses) == 3
    end
  end

  describe "mock reset functionality" do
    test "reset_all_simba_mocks/0 clears all configured responses" do
      # Set up various mocks
      SimbaMockProvider.setup_bootstrap_mocks(["response1", "response2"])
      SimbaMockProvider.setup_instruction_generation_mocks(["instruction1"])
      SimbaMockProvider.setup_evaluation_mocks(%{"pattern" => 0.8})

      # Verify mocks are set
      assert length(MockClientManager.get_mock_responses(:teacher)) > 0
      assert length(MockClientManager.get_mock_responses(:instruction_model)) > 0
      assert length(MockClientManager.get_mock_responses(:evaluator)) > 0

      # Reset all mocks
      assert :ok = SimbaMockProvider.reset_all_simba_mocks()

      # Verify all mocks are cleared
      assert MockClientManager.get_mock_responses(:teacher) == []
      assert MockClientManager.get_mock_responses(:instruction_model) == []
      assert MockClientManager.get_mock_responses(:evaluator) == []
    end
  end

  describe "concurrent optimization mocks" do
    test "setup_concurrent_optimization_mocks/1 configures concurrent scenarios" do
      concurrency_level = 5
      opts = [base_delay: 10, max_delay: 100]

      assert :ok = SimbaMockProvider.setup_concurrent_optimization_mocks(concurrency_level, opts)

      # Verify concurrent responses were configured
      concurrent_teacher = MockClientManager.get_mock_responses(:concurrent_teacher)
      concurrent_student = MockClientManager.get_mock_responses(:concurrent_student)

      assert length(concurrent_teacher) == 5
      assert length(concurrent_student) == 5

      # Verify response structure includes concurrency metadata
      first_response = hd(concurrent_teacher)
      assert %{content: content, metadata: metadata} = first_response
      assert String.contains?(content, "Concurrent response")
      assert %{concurrent_id: 1, batch_size: 5} = metadata
    end
  end

  describe "error recovery mocks" do
    test "setup_error_recovery_mocks/0 configures mixed success/error responses" do
      assert :ok = SimbaMockProvider.setup_error_recovery_mocks()

      # Verify error recovery responses were configured
      error_responses = MockClientManager.get_mock_responses(:error_prone)
      assert length(error_responses) == 5

      # Verify mix of success and error responses
      response_types =
        error_responses
        |> Enum.map(fn response ->
          if Map.has_key?(response, :error), do: :error, else: :success
        end)

      assert :success in response_types
      assert :error in response_types
    end
  end

  describe "mock validation" do
    test "validate_mock_setup/0 checks required providers" do
      # Initially should fail - no mocks set up
      assert {:error, {:no_mock_providers_configured, _all_providers}} =
               SimbaMockProvider.validate_mock_setup()

      # Set up some mocks (any mocks should pass)
      SimbaMockProvider.setup_bootstrap_mocks(["Test response"])

      # Should now pass
      assert :ok = SimbaMockProvider.validate_mock_setup()
    end
  end

  describe "integration with mock client manager" do
    test "mock responses integrate with existing MockClientManager" do
      # This test verifies that our SIMBA mocks work with the existing mock infrastructure
      SimbaMockProvider.setup_bootstrap_mocks(["Test teacher response"])

      # Start a mock client manager for the teacher provider
      {:ok, client_pid} = MockClientManager.start_link(:teacher)

      # Test that it can handle requests (though with basic responses for now)
      messages = [%{role: "user", content: "Test question"}]
      result = GenServer.call(client_pid, {:request, messages, %{}})

      # Should get a response in the expected format
      assert {:ok, response} = result
      assert %{choices: [%{message: %{content: content}}]} = response
      assert is_binary(content)

      # Clean up
      GenServer.stop(client_pid)
    end
  end

  describe "performance characteristics" do
    test "mock setup operations are fast" do
      # Test that setting up mocks doesn't take too long
      {time, :ok} =
        :timer.tc(fn ->
          SimbaMockProvider.setup_simba_optimization_mocks(%{max_iterations: 10})
        end)

      # Should complete quickly (< 10ms)
      # microseconds
      assert time < 10_000
    end

    test "mock reset is efficient" do
      # Set up multiple mock configurations
      SimbaMockProvider.setup_bootstrap_mocks(Enum.map(1..50, &"Response #{&1}"))
      SimbaMockProvider.setup_instruction_generation_mocks(Enum.map(1..50, &"Instruction #{&1}"))

      # Time the reset operation
      {time, :ok} =
        :timer.tc(fn ->
          SimbaMockProvider.reset_all_simba_mocks()
        end)

      # Should complete quickly even with many mocks
      # microseconds
      assert time < 5_000
    end
  end

  describe "SIMBA workflow simulation readiness" do
    test "all required mock types can be configured simultaneously" do
      # This test ensures all SIMBA mock types can work together
      assert :ok = SimbaMockProvider.setup_bootstrap_mocks(["Teacher response"])
      assert :ok = SimbaMockProvider.setup_instruction_generation_mocks(["Instruction"])
      assert :ok = SimbaMockProvider.setup_evaluation_mocks(%{"test" => 0.8})
      assert :ok = SimbaMockProvider.setup_concurrent_optimization_mocks(3)
      assert :ok = SimbaMockProvider.setup_error_recovery_mocks()

      # Verify all mock types are present
      providers = [
        :gpt4,
        :teacher,
        :instruction_model,
        :evaluator,
        :concurrent_teacher,
        :error_prone
      ]

      Enum.each(providers, fn provider ->
        responses = MockClientManager.get_mock_responses(provider)
        assert length(responses) > 0, "No responses found for provider #{provider}"
      end)

      # Verify we can validate the complete setup
      assert :ok = SimbaMockProvider.validate_mock_setup()
    end

    test "mock infrastructure supports expected SIMBA data flow" do
      # Configure a realistic SIMBA workflow scenario
      config = %{
        max_iterations: 5,
        base_score: 0.5,
        improvement_per_iteration: 0.15
      }

      SimbaMockProvider.setup_simba_optimization_mocks(config)

      # Verify teacher responses are available
      teacher_responses = MockClientManager.get_mock_responses(:teacher)
      assert length(teacher_responses) == 5

      # Verify student responses show progression
      student_responses = MockClientManager.get_mock_responses(:student)

      quality_scores =
        student_responses
        |> Enum.map(fn %{metadata: metadata} -> metadata.quality_score end)

      # Should show improvement (increasing scores)
      assert Enum.max(quality_scores) > Enum.min(quality_scores)

      # Verify evaluation responses are configured
      eval_responses = MockClientManager.get_mock_responses(:evaluator)
      assert length(eval_responses) == 5
    end
  end
end
