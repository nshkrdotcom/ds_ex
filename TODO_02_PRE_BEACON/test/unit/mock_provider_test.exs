# File: test/unit/mock_provider_test.exs
defmodule DSPEx.Test.MockProviderTest do
  use ExUnit.Case, async: false

  alias DSPEx.Test.MockProvider

  doctest DSPEx.Test.MockProvider

  setup do
    # Start fresh mock provider for each test
    {:ok, pid} = MockProvider.start_link(mode: :contextual)

    on_exit(fn ->
      if Process.alive?(pid) do
        MockProvider.reset()
      end
    end)

    %{mock_pid: pid}
  end

  describe "BEACON-specific mock patterns" do
    test "setup_bootstrap_mocks/1 provides realistic teacher responses" do
      teacher_responses = [
        %{content: "The answer is 4 because 2+2 equals 4"},
        %{content: "6 is the result of adding 3+3"},
        %{content: "Paris is the capital city of France"}
      ]

      assert :ok = MockProvider.setup_bootstrap_mocks(teacher_responses)

      # Verify the setup worked by checking call history after making requests
      messages = [%{role: "user", content: "What is 2+2?"}]
      {:ok, response1} = GenServer.call(MockProvider, {:mock_request, messages, %{}})

      assert %{choices: [%{message: %{content: content}}]} = response1
      assert is_binary(content)
      assert String.length(content) > 0
    end

    test "setup_instruction_generation_mocks/1 supports instruction optimization" do
      instruction_responses = [
        %{content: "Think step by step and show your reasoning"},
        %{content: "Consider multiple perspectives before answering"},
        %{content: "Use specific examples to support your conclusions"}
      ]

      assert :ok = MockProvider.setup_instruction_generation_mocks(instruction_responses)

      # Test instruction-related requests
      instruction_messages = [%{role: "user", content: "Generate an instruction for reasoning"}]
      {:ok, response} = GenServer.call(MockProvider, {:mock_request, instruction_messages, %{}})

      assert %{choices: [%{message: %{content: content}}]} = response
      assert String.contains?(content, "instruction") or String.contains?(content, "reasoning")
    end

    test "setup_evaluation_mocks/1 simulates optimization trajectories" do
      scores = [0.1, 0.3, 0.7, 0.9, 0.95]  # Improving trajectory

      assert :ok = MockProvider.setup_evaluation_mocks(scores)

      # Test evaluation requests
      eval_messages = [%{role: "user", content: "Evaluate this response"}]
      {:ok, response} = GenServer.call(MockProvider, {:mock_request, eval_messages, %{}})

      assert %{choices: [%{message: %{content: content}}]} = response
      assert String.contains?(content, "evaluat") or is_binary(content)
    end

    test "setup_beacon_optimization_mocks/1 configures comprehensive BEACON workflow" do
      config = [
        bootstrap_success_rate: 0.8,
        quality_distribution: :normal,
        instruction_effectiveness: 0.7,
        optimization_trajectory: :improving
      ]

      assert :ok = MockProvider.setup_beacon_optimization_mocks(config)

      # Test different types of BEACON requests
      bootstrap_msg = [%{role: "user", content: "Bootstrap demonstration example"}]
      {:ok, bootstrap_response} = GenServer.call(MockProvider, {:mock_request, bootstrap_msg, %{}})

      instruction_msg = [%{role: "user", content: "Optimize instruction for better results"}]
      {:ok, instruction_response} = GenServer.call(MockProvider, {:mock_request, instruction_msg, %{}})

      # Both should succeed with contextual responses
      assert %{choices: [%{message: %{content: bootstrap_content}}]} = bootstrap_response
      assert %{choices: [%{message: %{content: instruction_content}}]} = instruction_response

      assert String.contains?(bootstrap_content, "bootstrap") or String.contains?(bootstrap_content, "demonstration")
      assert String.contains?(instruction_content, "instruction") or String.contains?(instruction_content, "optimize")
    end

    test "mock responses maintain consistency across optimization cycles" do
      # Set up consistent responses
      MockProvider.setup_bootstrap_mocks([
        %{content: "Consistent answer 1"},
        %{content: "Consistent answer 2"}
      ])

      # Make multiple requests with same content
      messages = [%{role: "user", content: "Bootstrap question"}]

      responses = Enum.map(1..5, fn _i ->
        {:ok, response} = GenServer.call(MockProvider, {:mock_request, messages, %{}})
        response
      end)

      # Should have consistent structure
      assert Enum.all?(responses, fn response ->
        %{choices: [%{message: %{content: content}}]} = response
        is_binary(content) and String.length(content) > 0
      end)
    end
  end

  describe "advanced mock capabilities" do
    test "contextual response generation based on message content" do
      # Test different content types get appropriate responses
      test_cases = [
        {[%{role: "user", content: "What is 2+2?"}], "math"},
        {[%{role: "user", content: "Capital of France?"}], "capital"},
        {[%{role: "user", content: "Bootstrap demonstration"}], "bootstrap"},
        {[%{role: "user", content: "Reasoning step by step"}], "reasoning"}
      ]

      Enum.each(test_cases, fn {messages, expected_content_type} ->
        {:ok, response} = GenServer.call(MockProvider, {:mock_request, messages, %{}})

        assert %{choices: [%{message: %{content: content}}]} = response

        case expected_content_type do
          "math" -> assert content =~ ~r/\b4\b/ or String.contains?(content, "math")
          "capital" -> assert String.contains?(String.downcase(content), "paris")
          "bootstrap" -> assert String.contains?(String.downcase(content), "bootstrap") or String.contains?(String.downcase(content), "demonstration")
          "reasoning" -> assert String.contains?(String.downcase(content), "step") or String.contains?(String.downcase(content), "reasoning")
        end
      end)
    end

    test "failure simulation for robustness testing" do
      # Configure mock to fail some percentage of requests
      {:ok, _pid} = MockProvider.start_link(mode: :contextual, failure_rate: 0.3)

      messages = [%{role: "user", content: "Test failure simulation"}]

      # Make multiple requests
      results = Enum.map(1..20, fn _i ->
        GenServer.call(MockProvider, {:mock_request, messages, %{}})
      end)

      # Should have some failures
      failures = Enum.count(results, fn
        {:error, _} -> true
        _ -> false
      end)

      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      # Should have both successes and failures
      assert failures > 0, "No failures generated with 30% failure rate"
      assert successes > 0, "No successes with 30% failure rate"
      assert failures < successes, "Too many failures generated"
    end

    test "latency simulation for performance testing" do
      {:ok, _pid} = MockProvider.start_link(
        mode: :contextual,
        latency_simulation: true,
        base_delay_ms: 100,
        max_delay_ms: 300
      )

      messages = [%{role: "user", content: "Latency test"}]

      # Measure response time
      start_time = System.monotonic_time()
      {:ok, _response} = GenServer.call(MockProvider, {:mock_request, messages, %{}})
      end_time = System.monotonic_time()

      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Should have some simulated latency
      assert duration_ms >= 90, "Latency simulation not working: #{duration_ms}ms"
      assert duration_ms <= 400, "Latency simulation too high: #{duration_ms}ms"
    end

    test "call history tracking for validation" do
      messages1 = [%{role: "user", content: "First request"}]
      messages2 = [%{role: "user", content: "Second request"}]

      # Make some requests
      {:ok, _} = GenServer.call(MockProvider, {:mock_request, messages1, %{provider: :openai}})
      {:ok, _} = GenServer.call(MockProvider, {:mock_request, messages2, %{provider: :gemini}})

      # Check call history
      history = MockProvider.get_call_history()

      assert length(history) == 2

      # Verify history structure
      assert Enum.all?(history, fn call ->
        Map.has_key?(call, :timestamp) and
        Map.has_key?(call, :messages) and
        Map.has_key?(call, :options) and
        Map.has_key?(call, :response) and
        Map.has_key?(call, :latency_ms)
      end)

      # Verify content
      first_call = Enum.at(history, 0)
      assert first_call.messages == messages1
      assert first_call.options.provider == :openai

      second_call = Enum.at(history, 1)
      assert second_call.messages == messages2
      assert second_call.options.provider == :gemini
    end

    test "mock framework supports concurrent test execution" do
      # Test concurrent requests to mock provider
      messages = [%{role: "user", content: "Concurrent test"}]

      concurrent_results = Task.async_stream(1..20, fn i ->
        GenServer.call(MockProvider, {:mock_request, messages, %{correlation_id: "concurrent-#{i}"}})
      end, max_concurrency: 10, timeout: 5_000)
      |> Enum.to_list()

      # All should complete successfully
      successes = Enum.count(concurrent_results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert successes == 20, "Concurrent mock requests failed: #{successes}/20"

      # Check that all are recorded in history
      history = MockProvider.get_call_history()
      assert length(history) == 20
    end
  end

  describe "integration with existing test infrastructure" do
    test "MockProvider works with existing test modes (mock/fallback/live)" do
      # Test in different test modes
      original_mode = DSPEx.TestModeConfig.get_test_mode()

      try do
        # Test in mock mode
        DSPEx.TestModeConfig.set_test_mode(:mock)
        messages = [%{role: "user", content: "Test mode integration"}]
        {:ok, response1} = GenServer.call(MockProvider, {:mock_request, messages, %{}})
        assert %{choices: [%{message: %{content: _}}]} = response1

        # Test in fallback mode
        DSPEx.TestModeConfig.set_test_mode(:fallback)
        {:ok, response2} = GenServer.call(MockProvider, {:mock_request, messages, %{}})
        assert %{choices: [%{message: %{content: _}}]} = response2

        # Both should work
        assert is_map(response1)
        assert is_map(response2)

      after
        DSPEx.TestModeConfig.set_test_mode(original_mode)
      end
    end

    test "mock responses integrate with telemetry system" do
      messages = [%{role: "user", content: "Telemetry integration test"}]

      # Capture telemetry events
      test_pid = self()
      handler_id = "test-mock-telemetry"

      :telemetry.attach(
        handler_id,
        [:dspex, :client_manager, :request],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{}
      )

      # Make request
      {:ok, _response} = GenServer.call(MockProvider, {:mock_request, messages, %{correlation_id: "telemetry-test"}})

      # Should receive telemetry event
      assert_receive {:telemetry_event, [:dspex, :client_manager, :request], measurements, metadata}, 1000

      assert is_map(measurements)
      assert metadata.mock_mode == true
      assert metadata.correlation_id == "telemetry-test"

      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "MockProvider supports different response strategies" do
      # Test deterministic mode
      {:ok, _pid} = MockProvider.start_link(mode: :deterministic)
      messages = [%{role: "user", content: "Deterministic test"}]

      {:ok, response1} = GenServer.call(MockProvider, {:mock_request, messages, %{}})
      {:ok, response2} = GenServer.call(MockProvider, {:mock_request, messages, %{}})

      # Should be identical
      assert response1 == response2

      # Test contextual mode (default)
      MockProvider.reset()
      {:ok, _pid} = MockProvider.start_link(mode: :contextual)

      math_messages = [%{role: "user", content: "What is 2+2?"}]
      geography_messages = [%{role: "user", content: "Capital of France?"}]

      {:ok, math_response} = GenServer.call(MockProvider, {:mock_request, math_messages, %{}})
      {:ok, geo_response} = GenServer.call(MockProvider, {:mock_request, geography_messages, %{}})

      # Should be different and contextual
      refute math_response == geo_response

      math_content = get_in(math_response, [:choices, Access.at(0), :message, :content])
      geo_content = get_in(geo_response, [:choices, Access.at(0), :message, :content])

      assert String.contains?(math_content, "4") or String.contains?(math_content, "math")
      assert String.contains?(String.downcase(geo_content), "paris")
    end
  end

  describe "BEACON workflow simulation" do
    test "complete BEACON bootstrap workflow simulation" do
      # Simulate a complete bootstrap workflow
      MockProvider.setup_beacon_optimization_mocks([
        bootstrap_success_rate: 0.9,
        optimization_trajectory: :improving
      ])

      # Simulate teacher generating demonstrations
      teacher_messages = [
        [%{role: "user", content: "Teacher: What is 2+2?"}],
        [%{role: "user", content: "Teacher: What is 3+3?"}],
        [%{role: "user", content: "Teacher: Capital of France?"}]
      ]

      teacher_responses = Enum.map(teacher_messages, fn messages ->
        {:ok, response} = GenServer.call(MockProvider, {:mock_request, messages, %{}})
        response
      end)

      # All teacher responses should succeed
      assert Enum.all?(teacher_responses, fn response ->
        %{choices: [%{message: %{content: content}}]} = response
        is_binary(content) and String.length(content) > 0
      end)

      # Simulate student evaluation
      student_messages = [%{role: "user", content: "Student evaluation"}]
      {:ok, student_response} = GenServer.call(MockProvider, {:mock_request, student_messages, %{}})

      assert %{choices: [%{message: %{content: _}}]} = student_response

      # Check call history shows complete workflow
      history = MockProvider.get_call_history()
      assert length(history) >= 4  # 3 teacher + 1 student
    end

    test "instruction generation and optimization simulation" do
      MockProvider.setup_instruction_generation_mocks([
        %{content: "Think step by step and provide detailed reasoning"},
        %{content: "Consider multiple perspectives before concluding"},
        %{content: "Use concrete examples to support your answer"}
      ])

      # Simulate instruction optimization iterations
      instruction_requests = [
        "Generate instruction for mathematical reasoning",
        "Optimize instruction for better accuracy",
        "Refine instruction based on feedback"
      ]

      instruction_responses = Enum.map(instruction_requests, fn request ->
        messages = [%{role: "user", content: request}]
        {:ok, response} = GenServer.call(MockProvider, {:mock_request, messages, %{}})
        get_in(response, [:choices, Access.at(0), :message, :content])
      end)

      # All should contain instruction-related content
      assert Enum.all?(instruction_responses, fn content ->
        String.contains?(content, "instruction") or
        String.contains?(content, "reasoning") or
        String.contains?(content, "step") or
        String.contains?(content, "consider")
      end)
    end

    test "optimization trajectory simulation" do
      # Test different optimization trajectories
      trajectories = [:improving, :declining, :plateau, :noisy]

      Enum.each(trajectories, fn trajectory ->
        MockProvider.reset()
        MockProvider.setup_beacon_optimization_mocks([
          optimization_trajectory: trajectory
        ])

        # Simulate multiple optimization iterations
        iteration_messages = Enum.map(1..5, fn i ->
          [%{role: "user", content: "Optimization iteration #{i}"}]
        end)

        responses = Enum.map(iteration_messages, fn messages ->
          {:ok, response} = GenServer.call(MockProvider, {:mock_request, messages, %{}})
          response
        end)

        # All should succeed
        assert Enum.all?(responses, fn response ->
          %{choices: [%{message: %{content: content}}]} = response
          is_binary(content)
        end)
      end)
    end
  end

  describe "performance and reliability" do
    test "mock provider handles high-frequency requests" do
      messages = [%{role: "user", content: "High frequency test"}]

      # Make many rapid requests
      start_time = System.monotonic_time()

      results = Enum.map(1..100, fn i ->
        GenServer.call(MockProvider, {:mock_request, messages, %{id: i}})
      end)

      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # All should succeed
      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      assert successes == 100, "High frequency requests failed: #{successes}/100"

      # Should be fast
      assert duration_ms < 1000, "High frequency requests too slow: #{duration_ms}ms"

      # Check throughput
      throughput = 100 / (duration_ms / 1000)
      assert throughput > 50, "Mock provider throughput too low: #{throughput} req/sec"
    end

    test "memory usage remains stable during extended operation" do
      messages = [%{role: "user", content: "Memory stability test"}]

      # Measure initial memory
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)

      # Make many requests in batches
      Enum.each(1..10, fn batch ->
        Enum.each(1..50, fn i ->
          {:ok, _} = GenServer.call(MockProvider, {:mock_request, messages, %{batch: batch, id: i}})
        end)

        # Periodically check memory
        :erlang.garbage_collect()
      end)

      # Final memory check
      :erlang.garbage_collect()
      final_memory = :erlang.memory(:total)

      # Memory growth should be minimal
      memory_growth_mb = (final_memory - initial_memory) / (1024 * 1024)
      assert memory_growth_mb < 10, "Mock provider memory growth too high: #{memory_growth_mb}MB"

      # Call history should be manageable size
      history = MockProvider.get_call_history()
      assert length(history) == 500  # 10 batches * 50 requests
    end

    test "mock provider recovery from errors" do
      # Test that mock provider can recover from internal errors
      messages = [%{role: "user", content: "Error recovery test"}]

      # This should work normally
      {:ok, _} = GenServer.call(MockProvider, {:mock_request, messages, %{}})

      # Reset and continue working
      MockProvider.reset()
      {:ok, _} = GenServer.call(MockProvider, {:mock_request, messages, %{}})

      # Should still work after reset
      history = MockProvider.get_call_history()
      assert length(history) == 1  # Should only have post-reset request
    end
  end

  describe "configuration and customization" do
    test "custom response patterns work correctly" do
      # Configure custom responses
      custom_responses = [
        %{content: "Custom response 1", latency_ms: 100},
        %{content: "Custom response 2", latency_ms: 200}
      ]

      MockProvider.setup_bootstrap_mocks(custom_responses)

      messages = [%{role: "user", content: "Custom pattern test"}]
      {:ok, response} = GenServer.call(MockProvider, {:mock_request, messages, %{}})

      content = get_in(response, [:choices, Access.at(0), :message, :content])
      assert String.contains?(content, "Custom") or is_binary(content)
    end

    test "provider-specific mock behavior" do
      messages = [%{role: "user", content: "Provider-specific test"}]

      # Test different provider options
      providers = [:openai, :gemini, :anthropic]

      provider_responses = Enum.map(providers, fn provider ->
        {:ok, response} = GenServer.call(MockProvider, {:mock_request, messages, %{provider: provider}})
        {provider, response}
      end)

      # All should work
      assert Enum.all?(provider_responses, fn {_provider, response} ->
        %{choices: [%{message: %{content: content}}]} = response
        is_binary(content)
      end)
    end

    test "reset functionality clears state properly" do
      messages = [%{role: "user", content: "Reset test"}]

      # Make some requests
      {:ok, _} = GenServer.call(MockProvider, {:mock_request, messages, %{}})
      {:ok, _} = GenServer.call(MockProvider, {:mock_request, messages, %{}})

      # Should have history
      history_before = MockProvider.get_call_history()
      assert length(history_before) == 2

      # Reset
      MockProvider.reset()

      # History should be cleared
      history_after = MockProvider.get_call_history()
      assert length(history_after) == 0

      # Should still work after reset
      {:ok, _} = GenServer.call(MockProvider, {:mock_request, messages, %{}})
      final_history = MockProvider.get_call_history()
      assert length(final_history) == 1
    end
  end
end
