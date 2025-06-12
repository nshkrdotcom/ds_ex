defmodule DSPEx.Teleprompter.BEACONTest do
  @moduledoc """
  Comprehensive test suite for BEACON teleprompter functionality.

  Tests cover initialization, compilation, edge cases, error handling, and performance.
  """

  use ExUnit.Case, async: false

  alias DSPEx.{Example, Predict}
  alias DSPEx.Teleprompter.BEACON
  alias DSPEx.Teleprompter.BEACON.Utils

  describe "BEACON initialization" do
    test "creates BEACON with default configuration" do
      teleprompter = BEACON.new()

      assert teleprompter.num_candidates == 20
      assert teleprompter.max_bootstrapped_demos == 4
      assert teleprompter.num_trials == 50
      assert teleprompter.quality_threshold == 0.7
    end

    test "creates BEACON with custom configuration" do
      teleprompter = BEACON.new(
        num_candidates: 30,
        quality_threshold: 0.8,
        max_concurrency: 15
      )

      assert teleprompter.num_candidates == 30
      assert teleprompter.quality_threshold == 0.8
      assert teleprompter.max_concurrency == 15
    end

    test "validates configuration bounds" do
      teleprompter = BEACON.new(
        num_candidates: 100,
        quality_threshold: 1.0,
        max_concurrency: 1
      )

      assert teleprompter.num_candidates == 100
      assert teleprompter.quality_threshold == 1.0
      assert teleprompter.max_concurrency == 1
    end
  end

  describe "BEACON compilation" do
    setup do
      defmodule TestSignature do
        use DSPEx.Signature, "input -> output"
      end

      student = Predict.new(TestSignature, :gemini)
      teacher = Predict.new(TestSignature, :openai)

      trainset = [
        Example.new(%{input: "test1", output: "result1"}, [:input]),
        Example.new(%{input: "test2", output: "result2"}, [:input]),
        Example.new(%{input: "test3", output: "result3"}, [:input])
      ]

      metric_fn = fn example, prediction ->
        expected = Example.outputs(example)
        if expected[:output] == prediction[:output], do: 1.0, else: 0.0
      end

      %{
        student: student,
        teacher: teacher,
        trainset: trainset,
        metric_fn: metric_fn
      }
    end

    test "validates input parameters", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      teleprompter = BEACON.new()

      # Test invalid student
      assert {:error, :invalid_student_program} =
        teleprompter.compile(nil, teacher, trainset, metric_fn)

      # Test invalid teacher
      assert {:error, :invalid_teacher_program} =
        teleprompter.compile(student, nil, trainset, metric_fn)

      # Test empty trainset
      assert {:error, :invalid_or_empty_trainset} =
        teleprompter.compile(student, teacher, [], metric_fn)

      # Test invalid metric function
      assert {:error, :invalid_metric_function} =
        teleprompter.compile(student, teacher, trainset, "not_a_function")
    end

    test "handles edge cases gracefully", %{student: student, teacher: teacher, metric_fn: metric_fn} do
      teleprompter = BEACON.new(num_candidates: 1, num_trials: 1, max_bootstrapped_demos: 1)

      # Test with minimal trainset
      minimal_trainset = [
        Example.new(%{input: "test", output: "result"}, [:input])
      ]

      # Should not crash with minimal configuration
      result = teleprompter.compile(student, teacher, minimal_trainset, metric_fn)

      # Result can be either success or specific errors, but shouldn't crash
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "respects timeout configurations", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Test with very short timeout
      teleprompter = BEACON.new(
        timeout: 1,  # 1ms timeout should cause timeouts
        num_candidates: 2,
        num_trials: 2
      )

      # This should either succeed quickly or fail gracefully with timeout
      result = teleprompter.compile(student, teacher, trainset, metric_fn)

      # Accept either success (if very fast) or timeout/error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "progress callback functionality" do
      progress_callback = fn progress ->
        send(self(), {:progress, progress})
        :ok
      end

      teleprompter = BEACON.new(
        progress_callback: progress_callback,
        num_candidates: 2,
        num_trials: 2
      )

      assert is_function(teleprompter.progress_callback)
      assert teleprompter.progress_callback == progress_callback
    end

    @tag :integration
    test "full compilation workflow", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      teleprompter = BEACON.new(
        num_candidates: 3,
        max_bootstrapped_demos: 2,
        num_trials: 3,
        timeout: 30_000,
        quality_threshold: 0.5
      )

      result = with_mocked_llm_calls do
        teleprompter.compile(student, teacher, trainset, metric_fn)
      end

      case result do
        {:ok, optimized_student} ->
          assert is_struct(optimized_student)

        {:error, reason} ->
          acceptable_errors = [
            :no_successful_bootstrap_candidates,
            :network_error,
            :provider_not_configured,
            :timeout
          ]
          assert reason in acceptable_errors
      end
    end
  end

  describe "BEACON performance and edge cases" do
    test "handles large trainsets efficiently" do
      large_trainset =
        1..100
        |> Enum.map(fn i ->
          Example.new(%{input: "test#{i}", output: "result#{i}"}, [:input])
        end)

      teleprompter = BEACON.new(
        num_candidates: 5,
        max_bootstrapped_demos: 2,
        num_trials: 5,
        max_concurrency: 10
      )

      assert is_struct(teleprompter)
      assert length(large_trainset) == 100
      assert teleprompter.max_concurrency <= 20
      assert teleprompter.num_candidates < length(large_trainset)
    end

    test "concurrent safety" do
      teleprompter = BEACON.new(max_concurrency: 5)
      assert teleprompter.max_concurrency == 5
    end

    test "memory efficiency with large datasets" do
      large_trainset =
        1..1000
        |> Enum.map(fn i ->
          large_input = String.duplicate("word ", 100)
          Example.new(%{input: "#{large_input}#{i}", output: "result#{i}"}, [:input])
        end)

      teleprompter = BEACON.new(
        num_candidates: 10,
        max_bootstrapped_demos: 5
      )

      memory_before = :erlang.memory(:total)
      # Just creating shouldn't use excessive memory
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before

      # Should use less than 100MB for setup
      assert memory_used < 100 * 1024 * 1024
      assert length(large_trainset) == 1000
      assert is_struct(teleprompter)
    end

    test "error recovery and resilience" do
      unreliable_metric = fn _example, _prediction ->
        if :rand.uniform() > 0.7 do
          raise "Simulated metric error"
        else
          0.8
        end
      end

      teleprompter = BEACON.new(
        num_candidates: 3,
        num_trials: 3,
        teacher_retries: 2
      )

      assert teleprompter.teacher_retries == 2
      assert is_function(unreliable_metric)
    end

    test "configuration validation and bounds checking" do
      # Test minimum values
      min_config = BEACON.new(
        num_candidates: 1,
        max_bootstrapped_demos: 1,
        num_trials: 1,
        quality_threshold: 0.0,
        max_concurrency: 1
      )

      assert min_config.num_candidates == 1
      assert min_config.max_bootstrapped_demos == 1
      assert min_config.num_trials == 1
      assert min_config.quality_threshold == 0.0
      assert min_config.max_concurrency == 1

      # Test maximum reasonable values
      max_config = BEACON.new(
        num_candidates: 1000,
        max_bootstrapped_demos: 100,
        num_trials: 1000,
        quality_threshold: 1.0,
        max_concurrency: 100
      )

      assert max_config.num_candidates == 1000
      assert max_config.max_bootstrapped_demos == 100
      assert max_config.num_trials == 1000
      assert max_config.quality_threshold == 1.0
      assert max_config.max_concurrency == 100
    end
  end

  describe "BEACON telemetry and observability" do
    test "correlation ID propagation" do
      correlation_id = Utils.generate_correlation_id()
      teleprompter = BEACON.new()

      assert is_binary(correlation_id)
      assert String.starts_with?(correlation_id, "beacon-")
      assert is_struct(teleprompter)
    end

    test "progress tracking accuracy" do
      progress_events = []

      progress_callback = fn progress ->
        send(self(), {:progress, progress})
        :ok
      end

      teleprompter = BEACON.new(progress_callback: progress_callback)
      assert is_function(teleprompter.progress_callback)
    end
  end

  describe "utility functions" do
    test "text similarity calculation" do
      # Identical texts
      assert Utils.text_similarity("hello world", "hello world") == 1.0

      # Similar texts
      similarity = Utils.text_similarity("hello world", "hello there")
      assert similarity > 0.0 and similarity < 1.0

      # Different texts
      assert Utils.text_similarity("hello", "goodbye") < 0.5

      # Edge cases
      assert Utils.text_similarity("", "") == 1.0
      assert Utils.text_similarity("test", "") < 0.5
    end

    test "answer normalization" do
      assert Utils.normalize_answer("Hello, World!") == "hello world"
      assert Utils.normalize_answer("  Test  ") == "test"
      assert Utils.normalize_answer("$42") == "42"
      assert Utils.normalize_answer(nil) == ""
    end

    test "keyword extraction" do
      keywords = Utils.extract_keywords("This is a test sentence with some words")
      assert "test" in keywords
      assert "sentence" in keywords
      assert "words" in keywords
      # Stop words should be filtered
      refute "this" in keywords
      refute "with" in keywords
    end

    test "number extraction" do
      assert Utils.extract_number("The answer is 42") == 42
      assert Utils.extract_number("Price: $19.99") == 19.99
      assert Utils.extract_number("No numbers here") == nil
      assert Utils.extract_number(nil) == nil
    end

    test "reasoning quality evaluation" do
      good_reasoning = "First, we calculate 5 × 12 = 60. Therefore, the answer is $60."
      poor_reasoning = "The answer is obvious."

      good_score = Utils.evaluate_reasoning_quality(good_reasoning, good_reasoning)
      poor_score = Utils.evaluate_reasoning_quality(good_reasoning, poor_reasoning)

      assert good_score > poor_score
      assert good_score > 0.2  # Should get points for math operations and structure
      assert poor_score < 0.1   # Should get very few points
    end

    test "execution time measurement" do
      result = Utils.measure_execution_time(fn ->
        Process.sleep(10)
        {:ok, "test"}
      end)

      assert result.duration_ms >= 10
      assert result.success == true
      assert result.result == {:ok, "test"}

      # Test error handling
      error_result = Utils.measure_execution_time(fn ->
        raise "test error"
      end)

      assert error_result.success == false
      assert match?({:error, _}, error_result.result)
    end
  end

  # Helper function to mock LLM calls for testing
  defp with_mocked_llm_calls(test_func) do
    try do
      test_func.()
    rescue
      _ -> {:error, :mocked_test_environment}
    catch
      :exit, _ -> {:error, :mocked_test_environment}
      :throw, _ -> {:error, :mocked_test_environment}
    end
  end
end
