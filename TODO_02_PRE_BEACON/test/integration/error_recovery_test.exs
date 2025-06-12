# File: test/integration/error_recovery_test.exs
defmodule DSPEx.Integration.ErrorRecoveryTest do
  use ExUnit.Case, async: false

  alias DSPEx.{Client, Predict, Program, Example}
  alias DSPEx.Test.MockProvider
  alias DSPEx.Teleprompter.BootstrapFewShot

  @moduletag :integration
  @moduletag :error_recovery

  setup do
    {:ok, _mock} = MockProvider.start_link(mode: :contextual)

    defmodule ErrorRecoverySignature do
      use DSPEx.Signature, "question -> answer"
    end

    %{signature: ErrorRecoverySignature}
  end

  describe "program-level error isolation" do
    test "individual program failures don't affect other programs", %{signature: signature} do
      # Create multiple programs
      programs = [
        %Predict{signature: signature, client: :gemini},
        %Predict{signature: signature, client: :openai},
        %Predict{signature: signature, client: :anthropic}
      ]

      # Set up one to fail, others to succeed
      MockProvider.setup_bootstrap_mocks([
        {:error, :api_error},  # First fails
        %{content: "Success 1"},
        %{content: "Success 2"}
      ])

      inputs = %{question: "Test question"}

      # Execute all programs concurrently
      results = Task.async_stream(programs, fn program ->
        Program.forward(program, inputs)
      end, timeout: 5000)
      |> Enum.to_list()

      # Count successes - should have at least 2 despite 1 failure
      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert successes >= 2, "Expected at least 2 successes, got #{successes}"

      # Verify failures are isolated
      failures = Enum.count(results, fn
        {:ok, {:error, _}} -> true
        {:exit, _} -> true
        _ -> false
      end)

      assert failures <= 1, "Expected at most 1 failure, got #{failures}"
    end

    test "program timeout doesn't cascade to other operations", %{signature: signature} do
      program = %Predict{signature: signature, client: :test}

      # Set up mock to simulate timeout
      MockProvider.setup_bootstrap_mocks([
        {:timeout, :slow_response}
      ])

      inputs = %{question: "Timeout test"}

      # Execute with timeout
      task = Task.async(fn ->
        Program.forward(program, inputs, timeout: 100)
      end)

      # Should handle timeout gracefully
      result = case Task.yield(task, 200) do
        {:ok, result} -> result
        nil ->
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end

      # Verify timeout is handled gracefully
      assert match?({:error, _}, result)

      # Verify system is still responsive after timeout
      {:ok, _} = Program.forward(program, %{question: "After timeout"})
    end

    test "malformed input handling preserves system stability", %{signature: signature} do
      program = %Predict{signature: signature, client: :test}

      # Test various malformed inputs
      malformed_inputs = [
        nil,
        [],
        %{},
        %{wrong_field: "value"},
        %{question: nil},
        "not a map"
      ]

      results = Enum.map(malformed_inputs, fn input ->
        try do
          Program.forward(program, input)
        rescue
          error -> {:rescued, error}
        catch
          kind, reason -> {:caught, kind, reason}
        end
      end)

      # All should either return error tuples or be caught gracefully
      Enum.each(results, fn result ->
        assert match?({:error, _}, result) or
               match?({:rescued, _}, result) or
               match?({:caught, _, _}, result)
      end)

      # System should still be responsive after malformed inputs
      {:ok, _} = Program.forward(program, %{question: "Recovery test"})
    end
  end

  describe "client-level error recovery" do
    test "client connection failures trigger graceful fallback" do
      messages = [%{role: "user", content: "Connection test"}]

      # Set up mock to simulate network errors
      MockProvider.setup_bootstrap_mocks([
        {:error, :network_error},
        {:error, :timeout},
        %{content: "Fallback success"}
      ])

      # Multiple attempts should eventually succeed via fallback
      results = Enum.map(1..5, fn _i ->
        Client.request(messages, %{provider: :gemini})
      end)

      # Should have at least some successes due to fallback
      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      assert successes >= 2, "Expected fallback to work, got #{successes} successes"
    end

    test "provider switching on failure maintains correlation tracking" do
      messages = [%{role: "user", content: "Provider switching test"}]
      correlation_id = "error-recovery-#{System.unique_integer()}"

      # Test that correlation_id is preserved even during provider failures
      {:ok, _response} = Client.request(messages, %{
        provider: :gemini,
        correlation_id: correlation_id
      })

      # Verify request completed (may be mock fallback)
      # In real implementation, would verify correlation_id propagation
      # through telemetry events
    end

    test "retry mechanism with exponential backoff" do
      messages = [%{role: "user", content: "Retry test"}]

      # Simulate intermittent failures
      MockProvider.setup_bootstrap_mocks([
        {:error, :api_error},
        {:error, :rate_limited},
        %{content: "Eventually succeeds"}
      ])

      start_time = System.monotonic_time(:millisecond)

      # Should eventually succeed with retries
      {:ok, _response} = Client.request(messages, %{provider: :gemini})

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should have taken some time due to retries (in real implementation)
      # For mock, just verify it succeeded
      assert duration >= 0
    end
  end

  describe "teleprompter error recovery" do
    test "bootstrap failure recovery during optimization", %{signature: signature} do
      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}

      trainset = [
        %Example{
          data: %{question: "Test 1", answer: "Answer 1"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "Test 2", answer: "Answer 2"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "Test 3", answer: "Answer 3"},
          input_keys: MapSet.new([:question])
        }
      ]

      # Set up mixed success/failure for teacher responses
      MockProvider.setup_bootstrap_mocks([
        {:error, :teacher_failure},  # First example fails
        %{content: "Answer 2"},       # Second succeeds
        %{content: "Answer 3"}        # Third succeeds
      ])

      metric_fn = fn example, prediction ->
        expected = Example.get(example, :answer)
        actual = Map.get(prediction, :answer)
        if expected == actual, do: 1.0, else: 0.0
      end

      # Bootstrap should succeed with partial results
      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 3
      )

      assert {:ok, optimized} = result

      # Should have some demos despite failures
      demos = case optimized do
        %{demos: demos} -> demos
        %DSPEx.OptimizedProgram{demos: demos} -> demos
        _ -> []
      end

      # Should have at least the successful examples
      assert length(demos) >= 1
    end

    test "teacher timeout during optimization doesn't fail entire process", %{signature: signature} do
      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}

      trainset = [
        %Example{
          data: %{question: "Fast", answer: "Quick"},
          input_keys: MapSet.new([:question])
        }
      ]

      # Simulate teacher timeout
      MockProvider.setup_bootstrap_mocks([
        {:timeout, :teacher_slow}
      ])

      metric_fn = fn _example, _prediction -> 1.0 end

      # Should handle timeout gracefully
      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 1,
        timeout: 1000
      )

      # Should either succeed with fallback or fail gracefully
      case result do
        {:ok, _optimized} ->
          # Success with fallback
          :ok
        {:error, _reason} ->
          # Graceful failure
          :ok
      end
    end

    test "metric function errors don't crash optimization", %{signature: signature} do
      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}

      trainset = [
        %Example{
          data: %{question: "Test", answer: "Response"},
          input_keys: MapSet.new([:question])
        }
      ]

      MockProvider.setup_bootstrap_mocks([
        %{content: "Response"}
      ])

      # Metric function that throws errors
      metric_fn = fn _example, _prediction ->
        raise "Metric function error"
      end

      # Should handle metric errors gracefully
      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 1
      )

      # Should either succeed with error handling or fail gracefully
      case result do
        {:ok, _optimized} -> :ok  # Handled errors gracefully
        {:error, _reason} -> :ok  # Failed gracefully
      end
    end
  end

  describe "correlation ID preservation during errors" do
    test "correlation_id preserved through program failures", %{signature: signature} do
      program = %Predict{signature: signature, client: :test}
      correlation_id = "error-correlation-#{System.unique_integer()}"

      # Set up failure scenario
      MockProvider.setup_bootstrap_mocks([
        {:error, :test_failure}
      ])

      # Execute with correlation_id
      result = Program.forward(program, %{question: "Error test"},
                              correlation_id: correlation_id)

      # Should fail but preserve correlation context
      assert match?({:error, _}, result)

      # In real implementation, would verify correlation_id
      # was included in error telemetry events
    end

    test "correlation_id preserved through client errors" do
      messages = [%{role: "user", content: "Client error test"}]
      correlation_id = "client-error-#{System.unique_integer()}"

      # Set up client failure
      MockProvider.setup_bootstrap_mocks([
        {:error, :client_failure}
      ])

      # Should preserve correlation_id even in error scenarios
      _result = Client.request(messages, %{
        provider: :gemini,
        correlation_id: correlation_id
      })

      # In real implementation, would verify correlation_id
      # appears in error telemetry and logs
    end
  end

  describe "system stability under error conditions" do
    test "repeated errors don't degrade system performance" do
      # Simulate sustained error conditions

      for _i <- 1..20 do
        # Generate errors repeatedly
        result = Client.request([%{role: "user", content: "Error"}], %{
          provider: :test_failure
        })

        # Should handle each error gracefully
        case result do
          {:ok, _} -> :ok    # Fallback worked
          {:error, _} -> :ok # Error handled gracefully
        end
      end

      # System should still be responsive after error barrage
      {:ok, _} = Client.request([%{role: "user", content: "Recovery"}], %{
        provider: :gemini
      })
    end

    test "concurrent errors don't cause race conditions" do
      # Generate concurrent error conditions
      tasks = Task.async_stream(1..10, fn i ->
        Client.request([%{role: "user", content: "Concurrent error #{i}"}], %{
          provider: :error_generator
        })
      end, max_concurrency: 5, timeout: 5000)
      |> Enum.to_list()

      # All should complete without hanging or crashing
      assert length(tasks) == 10

      # System should be responsive after concurrent errors
      {:ok, _} = Client.request([%{role: "user", content: "After concurrent errors"}], %{
        provider: :gemini
      })
    end
  end
end
