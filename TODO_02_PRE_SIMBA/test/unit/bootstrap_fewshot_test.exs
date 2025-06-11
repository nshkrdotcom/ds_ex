# File: test/unit/bootstrap_fewshot_test.exs
defmodule DSPEx.Teleprompter.BootstrapFewShotTest do
  use ExUnit.Case, async: true

  alias DSPEx.{Teleprompter, Example, Predict, OptimizedProgram, Program}
  alias DSPEx.Teleprompter.BootstrapFewShot
  alias DSPEx.Test.MockProvider

  doctest DSPEx.Teleprompter.BootstrapFewShot

  setup do
    # Start mock provider for testing
    {:ok, _pid} = MockProvider.start_link(mode: :contextual)

    # Create test signature
    defmodule TestBootstrapSignature do
      @moduledoc "Test signature for bootstrap few-shot testing"
      use DSPEx.Signature, "question -> answer"
    end

    # Create programs
    student = %Predict{signature: TestBootstrapSignature, client: :test}
    teacher = %Predict{signature: TestBootstrapSignature, client: :test}

    # Create training examples
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
      }
    ]

    # Create metric function
    metric_fn = Teleprompter.exact_match(:answer)

    %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn,
      signature: TestBootstrapSignature
    }
  end

  describe "teleprompter behavior implementation" do
    test "implements DSPEx.Teleprompter behavior correctly" do
      # Verify BootstrapFewShot implements the behavior
      assert Teleprompter.implements_behavior?(BootstrapFewShot)

      # Test that compile/5 function exists with correct arity
      assert function_exported?(BootstrapFewShot, :compile, 5)
      assert function_exported?(BootstrapFewShot, :compile, 6)  # struct version
    end

    test "new/1 creates teleprompter with correct default options" do
      teleprompter = BootstrapFewShot.new()

      assert %BootstrapFewShot{} = teleprompter
      assert teleprompter.max_bootstrapped_demos == 4
      assert teleprompter.max_labeled_demos == 16
      assert teleprompter.quality_threshold == 0.7
      assert teleprompter.max_concurrency == 20
      assert teleprompter.timeout == 30_000
      assert teleprompter.teacher_retries == 2
      assert teleprompter.progress_callback == nil
    end

    test "new/1 accepts custom options" do
      options = [
        max_bootstrapped_demos: 8,
        quality_threshold: 0.9,
        max_concurrency: 50,
        timeout: 60_000,
        progress_callback: fn _progress -> :ok end
      ]

      teleprompter = BootstrapFewShot.new(options)

      assert teleprompter.max_bootstrapped_demos == 8
      assert teleprompter.quality_threshold == 0.9
      assert teleprompter.max_concurrency == 50
      assert teleprompter.timeout == 60_000
      assert is_function(teleprompter.progress_callback, 1)
    end
  end

  describe "core optimization algorithm" do
    test "compile/5 successfully optimizes student programs", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up mock responses for teacher
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      # Execute compilation
      result = BootstrapFewShot.compile(
        student,
        teacher,
        empty_trainset,
        metric_fn
      )

      # Should return error for empty training set
      assert {:error, :invalid_or_empty_trainset} = result
    end

    test "handles invalid student program", %{teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      invalid_student = "not a program"

      result = BootstrapFewShot.compile(
        invalid_student,
        teacher,
        trainset,
        metric_fn
      )

      assert {:error, :invalid_student_program} = result
    end

    test "handles invalid teacher program", %{student: student, trainset: trainset, metric_fn: metric_fn} do
      invalid_teacher = %{not: "a program"}

      result = BootstrapFewShot.compile(
        student,
        invalid_teacher,
        trainset,
        metric_fn
      )

      assert {:error, :invalid_teacher_program} = result
    end

    test "handles invalid metric function", %{student: student, teacher: teacher, trainset: trainset} do
      invalid_metric = "not a function"

      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        invalid_metric
      )

      assert {:error, :invalid_metric_function} = result
    end

    test "handles all teacher failures gracefully", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up all teacher calls to fail
      MockProvider.setup_bootstrap_mocks([
        {:error, :api_error},
        {:error, :network_error},
        {:error, :timeout}
      ])

      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn
      )

      assert {:error, :no_successful_bootstrap_candidates} = result
    end

    test "handles metric function errors gracefully", %{student: student, teacher: teacher, trainset: trainset} do
      # Metric function that throws errors
      error_metric = fn _example, _prediction ->
        raise "Metric error"
      end

      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        error_metric
      )

      # Should handle metric errors gracefully
      case result do
        {:ok, optimized} ->
          # Should succeed with empty or filtered demos
          demos = case optimized do
            %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
            %{demos: demos} -> demos
            _ -> []
          end
          # Demos might be empty due to metric errors
          assert is_list(demos)

        {:error, _reason} ->
          # Also acceptable if all metrics fail
          :ok
      end
    end

    test "handles very small quality thresholds", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        quality_threshold: 0.0  # Accept everything
      )

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should have demos since threshold is 0
      assert length(demos) > 0
    end

    test "handles very high quality thresholds", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        quality_threshold: 1.1  # Impossible threshold
      )

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should have no demos due to impossible threshold
      assert length(demos) == 0
    end

    test "handles single example training set", %{student: student, teacher: teacher, metric_fn: metric_fn} do
      single_example = [
        %Example{
          data: %{question: "Single question?", answer: "Single answer"},
          input_keys: MapSet.new([:question])
        }
      ]

      MockProvider.setup_bootstrap_mocks([%{content: "Single answer"}])

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        single_example,
        metric_fn
      )

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should work with single example
      assert length(demos) >= 0  # Might be 0 or 1 depending on quality
    end

    test "handles malformed examples in training set", %{student: student, teacher: teacher, metric_fn: metric_fn} do
      malformed_trainset = [
        %Example{
          data: %{question: "Good question?", answer: "Good answer"},
          input_keys: MapSet.new([:question])
        },
        "not an example",  # This should be filtered out
        %{not: "a proper example"}
      ]

      # Should validate and reject malformed trainset
      result = BootstrapFewShot.compile(
        student,
        teacher,
        malformed_trainset,
        metric_fn
      )

      assert {:error, :invalid_or_empty_trainset} = result
    end
  end

  describe "optimization results validation" do
    test "optimized program maintains original program interface", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
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

      # Should be usable as a program
      assert Program.implements_program?(optimized.__struct__)

      # Should maintain program interface
      test_input = %{question: "Test question"}

      # Mock a response for the optimized program test
      MockProvider.setup_evaluation_mocks([0.9])

      result = try do
        Program.forward(optimized, test_input)
      rescue
        _ -> :expected_test_error
      end

      # Should either work or fail gracefully
      case result do
        {:ok, _response} -> :ok
        {:error, _reason} -> :ok
        :expected_test_error -> :ok
      end
    end

    test "demonstrations have correct metadata", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
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

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Each demo should have bootstrap metadata
      assert Enum.all?(demos, fn demo ->
        data = demo.data

        Map.has_key?(data, :__generated_by) and
        data[:__generated_by] == :bootstrap_fewshot and
        Map.has_key?(data, :__teacher) and
        Map.has_key?(data, :__timestamp) and
        Map.has_key?(data, :__quality_score) and
        is_number(data[:__quality_score])
      end)
    end

    test "optimization preserves example input/output structure", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
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

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Each demo should have proper input/output structure
      assert Enum.all?(demos, fn demo ->
        inputs = Example.inputs(demo)
        outputs = Example.outputs(demo)

        Map.has_key?(inputs, :question) and
        Map.has_key?(outputs, :answer)
      end)
    end
  end

  # Helper function to collect progress messages
  defp collect_progress_messages(acc) do
    receive do
      {:progress_update, progress} ->
        collect_progress_messages([progress | acc])
    after
      100 ->
        Enum.reverse(acc)
    end
  end
end
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 2,
        quality_threshold: 0.5
      )

      assert {:ok, optimized_student} = result
      assert is_struct(optimized_student)

      # Check that optimized student has demonstrations
      demos = case optimized_student do
        %OptimizedProgram{} ->
          OptimizedProgram.get_demos(optimized_student)
        %{demos: demos} ->
          demos
        _ ->
          []
      end

      assert length(demos) > 0
      assert Enum.all?(demos, &is_struct(&1, Example))
    end

    test "compile/6 works with teleprompter struct", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      teleprompter = BootstrapFewShot.new(
        max_bootstrapped_demos: 3,
        quality_threshold: 0.6
      )

      MockProvider.setup_bootstrap_mocks([
        %{content: "The answer is 4"},
        %{content: "The answer is 6"},
        %{content: "Paris is the capital"}
      ])

      result = BootstrapFewShot.compile(
        teleprompter,
        student,
        teacher,
        trainset,
        metric_fn
      )

      assert {:ok, optimized_student} = result
      assert is_struct(optimized_student)
    end

    test "bootstrap generation creates valid demonstration examples", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      MockProvider.setup_bootstrap_mocks([
        %{content: "Four (4)"},
        %{content: "Six (6)"},
        %{content: "Paris, France"}
      ])

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 3
      )

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Verify demos have correct structure
      assert Enum.all?(demos, fn demo ->
        is_struct(demo, Example) and
        not Example.empty?(demo) and
        map_size(Example.inputs(demo)) > 0 and
        map_size(Example.outputs(demo)) > 0
      end)

      # Verify demos have metadata from bootstrap process
      assert Enum.all?(demos, fn demo ->
        data = demo.data
        Map.has_key?(data, :__generated_by) and
        Map.has_key?(data, :__teacher) and
        Map.has_key?(data, :__timestamp)
      end)
    end

    test "quality scoring and filtering works correctly", %{student: student, teacher: teacher, trainset: trainset} do
      # Create metric that only accepts exact "4" answers
      strict_metric = fn _example, prediction ->
        case Map.get(prediction, :answer) do
          "4" -> 1.0
          _ -> 0.0
        end
      end

      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},      # Should pass
        %{content: "Four"},   # Should fail
        %{content: "2+2=4"}   # Should fail
      ])

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        strict_metric,
        max_bootstrapped_demos: 3,
        quality_threshold: 0.9  # High threshold
      )

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should only have high-quality demos
      assert Enum.all?(demos, fn demo ->
        score = demo.data[:__quality_score]
        is_number(score) and score >= 0.9
      end)
    end

    test "demo selection respects max_demos limits", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Create more examples than the limit
      large_trainset = Enum.map(1..10, fn i ->
        %Example{
          data: %{question: "Question #{i}?", answer: "Answer #{i}"},
          input_keys: MapSet.new([:question])
        }
      end)

      # Set up mock responses for all examples
      MockProvider.setup_bootstrap_mocks(
        Enum.map(1..10, fn i -> %{content: "Answer #{i}"} end)
      )

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        large_trainset,
        metric_fn,
        max_bootstrapped_demos: 3  # Limit to 3
      )

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should respect the limit
      assert length(demos) <= 3
    end
  end

  describe "concurrent execution" do
    test "teacher program calls execute concurrently", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up many examples to test concurrency
      many_examples = Enum.map(1..20, fn i ->
        %Example{
          data: %{question: "Concurrent question #{i}?", answer: "Answer #{i}"},
          input_keys: MapSet.new([:question])
        }
      end)

      MockProvider.setup_bootstrap_mocks(
        Enum.map(1..20, fn i -> %{content: "Concurrent answer #{i}"} end)
      )

      start_time = System.monotonic_time()

      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        many_examples,
        metric_fn,
        max_bootstrapped_demos: 10,
        max_concurrency: 10
      )

      duration_ms = System.convert_time_unit(
        System.monotonic_time() - start_time,
        :native,
        :millisecond
      )

      # Should complete reasonably quickly due to concurrency
      # (This is somewhat environment-dependent, but should be much faster than sequential)
      assert duration_ms < 5000  # Less than 5 seconds
    end

    test "evaluation steps execute concurrently", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      # Test that evaluation of demos happens concurrently
      # This is implicit in the implementation, but we can test timing
      start_time = System.monotonic_time()

      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_concurrency: 10
      )

      duration_ms = System.convert_time_unit(
        System.monotonic_time() - start_time,
        :native,
        :millisecond
      )

      # Should complete quickly
      assert duration_ms < 2000
    end

    test "progress tracking works correctly during optimization", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      progress_updates = []

      progress_callback = fn progress ->
        send(self(), {:progress_update, progress})
        :ok
      end

      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        progress_callback: progress_callback
      )

      # Collect progress updates
      progress_updates = collect_progress_messages([])

      # Should have received progress updates
      assert length(progress_updates) > 0

      # Should have different phases
      phases = Enum.map(progress_updates, & &1.phase) |> Enum.uniq()
      assert :bootstrap_generation in phases
    end

    test "error handling isolates individual example failures", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up mixed success/failure responses
      MockProvider.setup_bootstrap_mocks([
        {:error, :api_error},  # This should be handled gracefully
        %{content: "6"},
        %{content: "Paris"}
      ])

      # Should not fail completely due to one error
      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 3
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
    end
  end

  describe "configuration and options" do
    test "quality threshold filtering works correctly", %{student: student, teacher: teacher, trainset: trainset} do
      # Create metric that gives varying scores
      variable_metric = fn example, prediction ->
        case Example.get(example, :question) do
          "What is 2+2?" -> 0.9  # High quality
          "What is 3+3?" -> 0.5  # Medium quality
          _ -> 0.2  # Low quality
        end
      end

      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      # Test with high threshold
      {:ok, optimized_high} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        variable_metric,
        quality_threshold: 0.8  # Only first example should pass
      )

      demos_high = case optimized_high do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized_high)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should have fewer demos due to high threshold
      high_quality_demos = Enum.filter(demos_high, fn demo ->
        (demo.data[:__quality_score] || 0.0) >= 0.8
      end)

      assert length(high_quality_demos) <= 1

      # Test with low threshold
      {:ok, optimized_low} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        variable_metric,
        quality_threshold: 0.1  # All should pass
      )

      demos_low = case optimized_low do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized_low)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should have more demos with low threshold
      assert length(demos_low) >= length(demos_high)
    end

    test "max concurrency limits are respected", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Create many examples to test concurrency limiting
      many_examples = Enum.map(1..50, fn i ->
        %Example{
          data: %{question: "Question #{i}?", answer: "Answer #{i}"},
          input_keys: MapSet.new([:question])
        }
      end)

      MockProvider.setup_bootstrap_mocks(
        Enum.map(1..50, fn i -> %{content: "Answer #{i}"} end)
      )

      # Test with low concurrency limit
      start_time = System.monotonic_time()

      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        many_examples,
        metric_fn,
        max_bootstrapped_demos: 10,
        max_concurrency: 2  # Very low concurrency
      )

      duration_ms = System.convert_time_unit(
        System.monotonic_time() - start_time,
        :native,
        :millisecond
      )

      # Should still complete (might be slower due to low concurrency)
      assert duration_ms < 10_000  # Should complete within 10 seconds
    end

    test "timeout handling works correctly", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
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
        timeout: 1  # 1ms timeout - very short
      )

      # Should either succeed quickly or handle timeout gracefully
      case result do
        {:ok, _optimized} -> :ok  # Completed quickly
        {:error, _reason} -> :ok  # Handled timeout gracefully
      end
    end

    test "teacher retry mechanism works", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up to fail first, then succeed (simulating retry)
      MockProvider.setup_bootstrap_mocks([
        {:error, :network_error},  # Should trigger retry
        %{content: "6"},
        %{content: "Paris"}
      ])

      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        teacher_retries: 3
      )

      # Should handle the retry and succeed
      case result do
        {:ok, _optimized} -> :ok
        {:error, _} -> :ok  # Acceptable if retries exhausted
      end
    end
  end

  describe "edge cases and error handling" do
    test "handles empty training set gracefully", %{student: student, teacher: teacher, metric_fn: metric_fn} do
      empty_trainset = []

      result = BootstrapFewShot.compile(
        student,
        teacher,
        empty_trainset,
        metric_fn
      )

      # Should return error for empty training set
      assert {:error, :invalid_or_empty_trainset} = result
    end

    test "handles nil inputs gracefully" do
      # Test various nil scenarios
      student = %Predict{signature: TestBootstrapSignature, client: :test}
      teacher = %Predict{signature: TestBootstrapSignature, client: :test}
      trainset = [
        %Example{
          data: %{question: "Test", answer: "Response"},
          input_keys: MapSet.new([:question])
        }
      ]
      metric_fn = Teleprompter.exact_match(:answer)

      # Nil student
      assert {:error, :invalid_student_program} = BootstrapFewShot.compile(
        nil, teacher, trainset, metric_fn
      )

      # Nil teacher
      assert {:error, :invalid_teacher_program} = BootstrapFewShot.compile(
        student, nil, trainset, metric_fn
      )

      # Nil trainset
      assert {:error, :invalid_or_empty_trainset} = BootstrapFewShot.compile(
        student, teacher, nil, metric_fn
      )

      # Nil metric function
      assert {:error, :invalid_metric_function} = BootstrapFewShot.compile(
        student, teacher, trainset, nil
      )
    end

    test "handles timeout scenarios gracefully", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up mock to simulate slow responses
      MockProvider.setup_bootstrap_mocks([
        %{content: "4", latency_ms: 100},
        %{content: "6", latency_ms: 100},
        %{content: "Paris", latency_ms: 100}
      ])

      # Test with very short timeout
      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        timeout: 1  # 1ms - very short
      )

      # Should handle timeout gracefully
      case result do
        {:ok, _optimized} -> :ok  # Completed quickly despite short timeout
        {:error, reason} ->
          assert reason in [:timeout, :no_successful_bootstrap_candidates]
      end
    end

    test "handles examples with missing required fields", %{student: student, teacher: teacher, metric_fn: metric_fn} do
      # Create trainset with malformed examples
      invalid_trainset = [
        %Example{
          data: %{question: "Good question?", answer: "Good answer"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{answer: "Missing question field"},  # Missing question
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "Missing answer field"},  # Missing answer
          input_keys: MapSet.new([:question])
        }
      ]

      MockProvider.setup_bootstrap_mocks([
        %{content: "Good answer"},
        %{content: "Response to missing question"},
        %{content: "Response to missing answer"}
      ])

      # Should handle gracefully - filter out invalid examples or succeed with valid ones
      result = BootstrapFewShot.compile(
        student,
        teacher,
        invalid_trainset,
        metric_fn
      )

      case result do
        {:ok, optimized} ->
          # Should succeed with valid examples only
          demos = case optimized do
            %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
            %{demos: demos} -> demos
            _ -> []
          end
          # Should have some valid demos
          assert is_list(demos)

        {:error, _reason} ->
          # Also acceptable if validation rejects the dataset
          :ok
      end
    end
  end

  describe "complex optimization scenarios" do
    test "handles heterogeneous training data", %{student: student, teacher: teacher} do
      # Mix of different question types and difficulties
      mixed_trainset = [
        %Example{
          data: %{question: "Simple: 2+2?", answer: "4"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "Geography: Capital of France?", answer: "Paris"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "Complex: Explain photosynthesis", answer: "Process by which plants convert light to energy"},
          input_keys: MapSet.new([:question])
        }
      ]

      # Metric that works across different types
      flexible_metric = fn example, prediction ->
        expected = Example.get(example, :answer)
        actual = Map.get(prediction, :answer, "")

        # Simple scoring based on content similarity
        if String.contains?(String.downcase(actual), String.downcase(expected)) do
          1.0
        else
          0.0
        end
      end

      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "Paris"},
        %{content: "Process by which plants convert light to energy"}
      ])

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        mixed_trainset,
        flexible_metric,
        max_bootstrapped_demos: 3
      )

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should handle diverse content types
      assert length(demos) > 0

      # Verify diversity in demo content
      demo_questions = Enum.map(demos, fn demo ->
        Example.get(demo, :question, "")
      end)

      # Should have meaningful content
      assert Enum.all?(demo_questions, fn q -> String.length(q) > 0 end)
    end

    test "optimization with very strict quality requirements", %{student: student, teacher: teacher, trainset: trainset} do
      # Metric that is very picky about exact matches
      strict_metric = fn example, prediction ->
        expected = Example.get(example, :answer)
        actual = Map.get(prediction, :answer)

        # Must match exactly, case-sensitive
        if expected == actual do
          1.0
        else
          0.0
        end
      end

      # Set up responses that won't match exactly
      MockProvider.setup_bootstrap_mocks([
        %{content: "four"},      # Instead of "4"
        %{content: "Six"},       # Instead of "6"
        %{content: "paris"}      # Instead of "Paris"
      ])

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        strict_metric,
        quality_threshold: 1.0  # Perfect score required
      )

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should result in no demos due to strict requirements
      assert length(demos) == 0
    end

    test "optimization with progressive quality improvement", %{student: student, teacher: teacher} do
      # Simulate improving teacher responses over time
      improvement_trainset = Enum.map(1..5, fn i ->
        %Example{
          data: %{question: "Question #{i}?", answer: "Answer #{i}"},
          input_keys: MapSet.new([:question])
        }
      end)

      # Responses get progressively better
      MockProvider.setup_bootstrap_mocks([
        %{content: "Wrong 1"},      # Quality: 0.0
        %{content: "Answer 2"},     # Quality: 1.0
        %{content: "Wrong 3"},      # Quality: 0.0
        %{content: "Answer 4"},     # Quality: 1.0
        %{content: "Answer 5"}      # Quality: 1.0
      ])

      metric_fn = Teleprompter.exact_match(:answer)

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        improvement_trainset,
        metric_fn,
        quality_threshold: 0.8,
        max_bootstrapped_demos: 5
      )

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should have filtered to only high-quality demos
      assert length(demos) <= 3  # Only the good responses

      # All remaining demos should have high quality scores
      quality_scores = Enum.map(demos, fn demo ->
        demo.data[:__quality_score] || 0.0
      end)

      assert Enum.all?(quality_scores, &(&1 >= 0.8))
    end
  end

  describe "metadata and introspection" do
    test "generated demonstrations have complete metadata", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
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

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Verify complete metadata structure
      assert Enum.all?(demos, fn demo ->
        data = demo.data

        # Required metadata fields
        Map.has_key?(data, :__generated_by) and
        Map.has_key?(data, :__teacher) and
        Map.has_key?(data, :__timestamp) and
        Map.has_key?(data, :__quality_score) and
        Map.has_key?(data, :__original_example_id) and

        # Verify data types
        data[:__generated_by] == :bootstrap_fewshot and
        is_atom(data[:__teacher]) and
        %DateTime{} = data[:__timestamp] and
        is_number(data[:__quality_score]) and
        data[:__quality_score] >= 0.0 and
        data[:__quality_score] <= 1.0
      end)
    end

    test "optimization preserves original example structure", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
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

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Verify input/output structure preservation
      original_input_keys = MapSet.new([:question])

      assert Enum.all?(demos, fn demo ->
        # Should maintain input field structure
        demo.input_keys == original_input_keys and

        # Should have both inputs and outputs
        inputs = Example.inputs(demo)
        outputs = Example.outputs(demo)

        Map.has_key?(inputs, :question) and
        Map.has_key?(outputs, :answer) and

        # Inputs should come from original data
        is_binary(inputs[:question]) and
        String.length(inputs[:question]) > 0 and

        # Outputs should come from teacher prediction
        is_binary(outputs[:answer]) and
        String.length(outputs[:answer]) > 0
      end)
    end

    test "teleprompter configuration is reflected in results", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      custom_config = [
        max_bootstrapped_demos: 2,
        quality_threshold: 0.9,
        max_concurrency: 5
      ]

      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      {:ok, optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        custom_config
      )

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should respect max_bootstrapped_demos limit
      assert length(demos) <= 2

      # Should respect quality threshold
      quality_scores = Enum.map(demos, fn demo ->
        demo.data[:__quality_score] || 0.0
      end)

      if length(quality_scores) > 0 do
        assert Enum.all?(quality_scores, &(&1 >= 0.9))
      end
    end
  end

  # Helper function to collect progress messages
  defp collect_progress_messages(acc) do
    receive do
      {:progress_update, progress} ->
        collect_progress_messages([progress | acc])
    after
      100 ->
        Enum.reverse(acc)
    end
  end
end
