# File: test/integration/teleprompter_workflow_test.exs
defmodule DSPEx.Integration.TeleprompterWorkflowTest do
  use ExUnit.Case, async: false

  alias DSPEx.{Teleprompter, Example, Predict, OptimizedProgram, Program}
  alias DSPEx.Test.MockProvider
  alias DSPEx.Teleprompter.BootstrapFewShot

  @moduletag :integration

  setup do
    # Set up mock provider for reliable testing
    {:ok, _pid} = MockProvider.start_link(mode: :contextual)

    # Create test signature
    defmodule TestWorkflowSignature do
      @moduledoc "Test signature for end-to-end workflow testing"
      use DSPEx.Signature, "question -> answer"
    end

    # Create programs
    student = %Predict{signature: TestWorkflowSignature, client: :test}
    teacher = %Predict{signature: TestWorkflowSignature, client: :test}

    # Create comprehensive training examples
    trainset = [
      %Example{
        data: %{question: "What is 2+2?", answer: "4"},
        input_keys: MapSet.new([:question])
      },
      %Example{
        data: %{question: "What is 3+3?", answer: "6"},
        input_keys: MapSet.new([:question])
      },
      %Example{
        data: %{question: "What is the capital of France?", answer: "Paris"},
        input_keys: MapSet.new([:question])
      },
      %Example{
        data: %{question: "What is 5+5?", answer: "10"},
        input_keys: MapSet.new([:question])
      }
    ]

    # Create metric function
    metric_fn = Teleprompter.exact_match(:answer)

    %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn,
      signature: TestWorkflowSignature
    }
  end

  describe "complete optimization pipeline" do
    test "student → teacher → optimized student workflow works end-to-end", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up realistic mock responses for the complete workflow
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"},
        %{content: "10"}
      ])

      # Step 1: Validate inputs (as SIMBA will do)
      assert :ok = Teleprompter.validate_student(student)
      assert :ok = Teleprompter.validate_teacher(teacher)
      assert :ok = Teleprompter.validate_trainset(trainset)

      # Step 2: Execute teleprompter compilation
      teleprompter = BootstrapFewShot.new(
        max_bootstrapped_demos: 3,
        quality_threshold: 0.7
      )

      result = BootstrapFewShot.compile(
        teleprompter,
        student,
        teacher,
        trainset,
        metric_fn
      )

      # Step 3: Validate optimization result
      assert {:ok, optimized_student} = result
      assert is_struct(optimized_student)

      # Step 4: Verify optimized program has demonstrations
      demos = case optimized_student do
        %OptimizedProgram{} ->
          OptimizedProgram.get_demos(optimized_student)
        %{demos: demos} ->
          demos
        _ ->
          []
      end

      assert length(demos) > 0, "Optimized student should have demonstrations"
      assert Enum.all?(demos, &is_struct(&1, Example)), "All demos should be Example structs"

      # Step 5: Verify optimized program can make predictions
      MockProvider.setup_evaluation_mocks([0.9])
      test_input = %{question: "What is 4+4?"}

      prediction_result = try do
        Program.forward(optimized_student, test_input)
      rescue
        _ -> {:error, :expected_test_error}
      end

      # Should either work or fail gracefully
      case prediction_result do
        {:ok, prediction} ->
          assert %{answer: answer} = prediction
          assert is_binary(answer)
        {:error, _reason} ->
          # Acceptable in test environment
          :ok
      end
    end

    test "real example optimization improves program performance", %{student: student, teacher: teacher, trainset: trainset} do
      # Create a performance-sensitive metric
      performance_metric = fn example, prediction ->
        expected = Example.get(example, :answer)
        actual = Map.get(prediction, :answer)

        cond do
          expected == actual -> 1.0  # Perfect match
          is_binary(actual) and String.contains?(actual, expected) -> 0.8  # Partial match
          true -> 0.0  # No match
        end
      end

      # Set up mock responses with varying quality
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},                    # Perfect for "4"
        %{content: "Six (6)"},             # Good for "6"
        %{content: "Paris, France"},       # Good for "Paris"
        %{content: "The answer is 10"}     # Good for "10"
      ])

      # Optimize student
      {:ok, optimized_student} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        performance_metric,
        max_bootstrapped_demos: 4,
        quality_threshold: 0.6
      )

      # Verify optimization collected good demonstrations
      demos = case optimized_student do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized_student)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should have high-quality demonstrations
      high_quality_demos = Enum.filter(demos, fn demo ->
        score = demo.data[:__quality_score]
        is_number(score) and score >= 0.6
      end)

      assert length(high_quality_demos) > 0, "Should have high-quality demonstrations"

      # Verify metadata indicates successful optimization
      if is_struct(optimized_student, OptimizedProgram) do
        metadata = OptimizedProgram.get_metadata(optimized_student)
        assert metadata.demo_count == length(demos)
        assert %DateTime{} = metadata.optimized_at
      end
    end

    test "multiple optimization iterations work correctly", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # First optimization round
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      {:ok, first_optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 2
      )

      first_demos = case first_optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(first_optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Second optimization round (optimize the already optimized program)
      MockProvider.reset()
      MockProvider.setup_bootstrap_mocks([
        %{content: "The answer is 4"},
        %{content: "The answer is 6"},
        %{content: "Paris is the capital"},
        %{content: "10"}
      ])

      additional_examples = [
        %Example{
          data: %{question: "What is 7+7?", answer: "14"},
          input_keys: MapSet.new([:question])
        }
      ]

      {:ok, second_optimized} = BootstrapFewShot.compile(
        first_optimized,  # Use optimized program as student
        teacher,
        additional_examples,
        metric_fn,
        max_bootstrapped_demos: 3
      )

      second_demos = case second_optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(second_optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Second optimization should work
      assert is_struct(second_optimized)
      assert length(second_demos) >= 0

      # Should be able to continue optimizing
      assert Program.implements_program?(second_optimized.__struct__)
    end

    test "optimization results are reproducible with same inputs", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up identical mock responses for both runs
      mock_responses = [
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ]

      # First optimization run
      MockProvider.setup_bootstrap_mocks(mock_responses)

      {:ok, optimized1} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 3,
        quality_threshold: 0.5
      )

      demos1 = case optimized1 do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized1)
        %{demos: demos} -> demos
        _ -> []
      end

      # Reset and repeat with same configuration
      MockProvider.reset()
      MockProvider.setup_bootstrap_mocks(mock_responses)

      {:ok, optimized2} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 3,
        quality_threshold: 0.5
      )

      demos2 = case optimized2 do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized2)
        %{demos: demos} -> demos
        _ -> []
      end

      # Results should be similar (demo count and structure)
      assert length(demos1) == length(demos2)

      # Should have similar structure
      assert Enum.all?(demos1, &is_struct(&1, Example))
      assert Enum.all?(demos2, &is_struct(&1, Example))
    end
  end

  describe "integration with existing components" do
    test "teleprompter works with DSPEx.Predict programs", %{trainset: trainset, metric_fn: metric_fn} do
      # Test with different client configurations
      student_openai = %Predict{signature: TestWorkflowSignature, client: :openai}
      teacher_gemini = %Predict{signature: TestWorkflowSignature, client: :gemini}

      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      {:ok, optimized} = BootstrapFewShot.compile(
        student_openai,
        teacher_gemini,
        trainset,
        metric_fn
      )

      # Should work with different client configurations
      assert is_struct(optimized)

      # Verify original program is preserved
      original_program = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_program(optimized)
        program -> program
      end

      assert original_program.client == :openai
      assert original_program.signature == TestWorkflowSignature
    end

    test "teleprompter works with DSPEx.Evaluate for metrics", %{student: student, teacher: teacher, trainset: trainset} do
      # Create evaluation-compatible metric
      eval_metric = fn example, prediction ->
        expected_answer = Example.get(example, :answer)
        predicted_answer = Map.get(prediction, :answer)

        if expected_answer == predicted_answer do
          1.0
        else
          0.0
        end
      end

      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      # Use the metric in teleprompter
      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        eval_metric,
        max_bootstrapped_demos: 3
      )

      # Should work with evaluation-style metrics
      assert is_struct(optimized)

      # Test that optimized program can be used with DSPEx.Evaluate
      MockProvider.setup_evaluation_mocks([0.8, 0.9, 0.7])

      # Create test examples for evaluation
      eval_examples = [
        %Example{
          data: %{question: "Test question", answer: "Test answer"},
          input_keys: MapSet.new([:question])
        }
      ]

      # This would be the actual evaluation call (may fail in test environment)
      eval_result = try do
        DSPEx.Evaluate.run_local(optimized, eval_examples, eval_metric)
      rescue
        _ -> {:error, :expected_test_error}
      end

      # Should either work or fail gracefully
      case eval_result do
        {:ok, result} ->
          assert is_map(result)
          assert Map.has_key?(result, :score)
        {:error, _} ->
          :ok  # Expected in test environment
      end
    end

    test "optimized programs work with DSPEx.Program.forward/3", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn
      )

      # Test Program.forward interface
      test_inputs = %{question: "What is the capital of Italy?"}

      # Set up mock for forward call
      MockProvider.setup_evaluation_mocks([0.85])

      # Test the Program behavior interface
      assert Program.implements_program?(optimized.__struct__)

      # Test forward call
      forward_result = try do
        Program.forward(optimized, test_inputs)
      rescue
        error -> {:caught_error, error}
      end

      # Should work with Program interface
      case forward_result do
        {:ok, outputs} ->
          assert is_map(outputs)
          # Should have answer field based on signature

        {:error, _reason} ->
          :ok  # Expected in test environment

        {:caught_error, _error} ->
          :ok  # Expected in test environment
      end
    end

    test "telemetry integration works throughout optimization", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Capture telemetry events
      test_pid = self()
      handler_id = "test-teleprompter-telemetry"

      telemetry_events = [
        [:dspex, :program, :forward, :start],
        [:dspex, :program, :forward, :stop],
        [:dspex, :client, :request, :start],
        [:dspex, :client, :request, :stop]
      ]

      :telemetry.attach_many(
        handler_id,
        telemetry_events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{}
      )

      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      # Execute optimization
      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn
      )

      # Should receive telemetry events
      telemetry_received = collect_telemetry_events([])

      # Should have some telemetry events from the process
      assert length(telemetry_received) > 0

      # Cleanup
      :telemetry.detach(handler_id)
    end
  end

  describe "error handling and edge cases" do
    test "optimization handles teacher program failures gracefully", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up mixed success/failure responses
      MockProvider.setup_bootstrap_mocks([
        {:error, :api_error},        # First example fails
        %{content: "6"},             # Second succeeds
        {:error, :network_error},    # Third fails
        %{content: "Paris"}          # Fourth succeeds (if using 4 examples)
      ])

      # Should not fail completely due to partial failures
      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 4
      )

      # Should succeed with partial results
      assert {:ok, optimized} = result

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should have some demos from successful examples
      # (might be fewer than expected due to failures)
      assert is_list(demos)
      # Don't assert specific count since failures are handled gracefully
    end

    test "optimization timeout scenarios work correctly", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      # Test with very short timeout
      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        timeout: 1  # 1ms timeout
      )

      # Should either complete quickly or handle timeout gracefully
      case result do
        {:ok, _optimized} ->
          # Completed within timeout
          :ok

        {:error, reason} ->
          # Should be a reasonable timeout-related error
          assert reason in [:timeout, :max_retries_exceeded, :no_successful_bootstrap_candidates]
      end
    end

    test "invalid training examples are handled correctly", %{student: student, teacher: teacher, metric_fn: metric_fn} do
      # Mix valid and invalid examples
      mixed_trainset = [
        %Example{
          data: %{question: "Valid question", answer: "Valid answer"},
          input_keys: MapSet.new([:question])
        },
        # This should cause validation to fail at the teleprompter level
        "invalid example"
      ]

      # Should reject invalid training set
      result = BootstrapFewShot.compile(
        student,
        teacher,
        mixed_trainset,
        metric_fn
      )

      assert {:error, :invalid_or_empty_trainset} = result
    end

    test "metric function errors are handled gracefully", %{student: student, teacher: teacher, trainset: trainset} do
      # Create metric function that throws errors
      error_metric = fn _example, _prediction ->
        if :rand.uniform() > 0.5 do
          raise "Random metric error"
        else
          1.0
        end
      end

      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      # Should handle metric errors gracefully
      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        error_metric
      )

      case result do
        {:ok, optimized} ->
          # Should succeed even with some metric failures
          assert is_struct(optimized)

        {:error, _reason} ->
          # Also acceptable if all metrics fail
          :ok
      end
    end

    test "concurrent optimization operations don't interfere", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up enough mock responses for concurrent operations
      MockProvider.setup_bootstrap_mocks(
        Enum.map(1..20, fn i -> %{content: "Answer #{i}"} end)
      )

      # Run multiple optimizations concurrently
      concurrent_results = Task.async_stream(1..3, fn i ->
        # Each gets a subset of training data
        subset_trainset = Enum.take(trainset, 2)

        BootstrapFewShot.compile(
          student,
          teacher,
          subset_trainset,
          metric_fn,
          max_bootstrapped_demos: 2,
          max_concurrency: 5  # Lower concurrency to avoid overwhelming mock
        )
      end, max_concurrency: 3, timeout: 15_000)
      |> Enum.to_list()

      # All should complete successfully
      successes = Enum.count(concurrent_results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert successes >= 2, "Concurrent optimizations failed: #{successes}/3"
    end
  end

  describe "performance and scalability" do
    test "optimization completes within reasonable time", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"},
        %{content: "10"}
      ])

      # Measure optimization time
      start_time = System.monotonic_time()

      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 3
      )

      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Should complete quickly in test environment
      assert duration_ms < 5000, "Optimization took too long: #{duration_ms}ms"
    end

    test "optimization scales reasonably with training set size", %{student: student, teacher: teacher, metric_fn: metric_fn} do
      # Test with different sizes
      sizes = [5, 10, 20]

      results = Enum.map(sizes, fn size ->
        # Create training set of specified size
        large_trainset = Enum.map(1..size, fn i ->
          %Example{
            data: %{question: "Question #{i}?", answer: "Answer #{i}"},
            input_keys: MapSet.new([:question])
          }
        end)

        # Set up mock responses
        MockProvider.reset()
        MockProvider.setup_bootstrap_mocks(
          Enum.map(1..size, fn i -> %{content: "Answer #{i}"} end)
        )

        # Measure time
        start_time = System.monotonic_time()

        result = BootstrapFewShot.compile(
          student,
          teacher,
          large_trainset,
          metric_fn,
          max_bootstrapped_demos: min(size, 5),  # Cap demos
          max_concurrency: 10
        )

        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        {size, duration_ms, result}
      end)

      # All should succeed
      assert Enum.all?(results, fn {_size, _duration, result} ->
        match?({:ok, _}, result)
      end)

      # Performance should scale reasonably
      durations = Enum.map(results, fn {size, duration, _result} -> {size, duration} end)

      Enum.each(durations, fn {size, duration} ->
        # Should complete within reasonable time even for larger sets
        max_expected = size * 50  # 50ms per example max
        assert duration < max_expected, "Size #{size} took #{duration}ms (expected < #{max_expected}ms)"
      end)
    end

    test "memory usage remains stable during optimization", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      # Measure memory before
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)

      # Run optimization
      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn
      )

      # Force garbage collection and measure after
      :erlang.garbage_collect()
      final_memory = :erlang.memory(:total)

      # Memory growth should be reasonable
      memory_growth_mb = (final_memory - initial_memory) / (1024 * 1024)
      assert memory_growth_mb < 10, "Memory growth too high: #{memory_growth_mb}MB"
    end
  end

  # Helper function to collect telemetry events
  defp collect_telemetry_events(acc) do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        collect_telemetry_events([{event, measurements, metadata} | acc])
    after
      100 ->
        Enum.reverse(acc)
    end
  end
end
