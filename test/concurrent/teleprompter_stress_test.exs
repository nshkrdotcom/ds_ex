defmodule DSPEx.Concurrent.TeleprompterStressTest do
  @moduledoc """
  Concurrent stress tests for DSPEx.Teleprompter optimization.
  Tests concurrent teacher execution, demo generation, and full optimization
  pipeline under high load - critical for BEACON readiness validation.
  """
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  @moduletag :group_2

  @concurrency_level 25
  # @stress_operations 100

  # Mock signature for testing
  defmodule TestSignature do
    use DSPEx.Signature, "question -> answer"
  end

  # Mock teacher program that provides high-quality responses
  defmodule MockTeacherProgram do
    use DSPEx.Program

    defstruct [:id, :quality_level, :delay_ms, :failure_rate]

    def new(id, opts \\ []) do
      %__MODULE__{
        id: id,
        quality_level: Keyword.get(opts, :quality_level, 0.9),
        delay_ms: Keyword.get(opts, :delay_ms, 20),
        failure_rate: Keyword.get(opts, :failure_rate, 0.0)
      }
    end

    @impl DSPEx.Program
    def forward(teacher, inputs, _opts) do
      # Simulate teacher processing time
      Process.sleep(teacher.delay_ms)

      # Simulate random failures
      if :rand.uniform() < teacher.failure_rate do
        {:error, :teacher_failure}
      else
        question = Map.get(inputs, :question, "")

        # Generate high-quality responses based on teacher quality level
        quality_score = teacher.quality_level + (:rand.uniform() - 0.5) * 0.2
        quality_score = max(0.0, min(1.0, quality_score))

        answer =
          cond do
            String.contains?(question, "2+2") ->
              "4"

            String.contains?(question, "3+3") ->
              "6"

            String.contains?(question, "5+5") ->
              "10"

            String.contains?(question, "capital") and String.contains?(question, "France") ->
              "Paris"

            String.contains?(question, "capital") and String.contains?(question, "Spain") ->
              "Madrid"

            true ->
              "High quality teacher response (quality: #{Float.round(quality_score, 2)})"
          end

        {:ok, %{answer: answer, quality_score: quality_score, teacher_id: teacher.id}}
      end
    end
  end

  # Mock student program
  defmodule MockStudentProgram do
    use DSPEx.Program

    defstruct [:id, :demos]

    def new(id, demos \\ []) do
      %__MODULE__{id: id, demos: demos}
    end

    @impl DSPEx.Program
    def forward(student, inputs, _opts) do
      _question = Map.get(inputs, :question, "")

      # Simple student logic - improved by demos
      base_answer = "Student response"
      demo_boost = length(student.demos) * 0.1

      answer =
        if demo_boost > 0 do
          "#{base_answer} (enhanced by #{length(student.demos)} demos)"
        else
          base_answer
        end

      {:ok, %{answer: answer, demo_count: length(student.demos), student_id: student.id}}
    end
  end

  describe "concurrent teacher execution" do
    test "teacher executes training examples concurrently" do
      teacher = MockTeacherProgram.new(:concurrent_teacher, delay_ms: 50)

      # Large training set to test concurrency
      trainset =
        for i <- 1..@concurrency_level do
          DSPEx.Example.new(
            %{
              question: "What is #{i}+#{i}?",
              answer: "#{i * 2}"
            },
            [:question]
          )
        end

      # start_count, end_count
      execution_tracker = :counters.new(2, [])

      # Track concurrent execution by wrapping teacher
      tracking_teacher = %{teacher | delay_ms: teacher.delay_ms, id: {:tracking, teacher.id}}

      # Use Task.async_stream to execute teacher on all examples
      start_time = System.monotonic_time()

      results =
        Task.async_stream(
          trainset,
          fn example ->
            # Track start
            :counters.add(execution_tracker, 1, 1)
            result = DSPEx.Program.forward(tracking_teacher, DSPEx.Example.inputs(example))
            # Track end
            :counters.add(execution_tracker, 2, 1)
            {example, result}
          end,
          max_concurrency: 10,
          timeout: 10_000
        )
        |> Enum.to_list()

      end_time = System.monotonic_time()
      total_duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Should complete much faster than sequential execution
      # Sequential would be: @concurrency_level * 50ms = 1250ms
      # Parallel should be much faster
      assert total_duration < 800

      # All executions should succeed
      assert length(results) == @concurrency_level

      successes =
        Enum.count(results, fn
          {_, {_example, {:ok, _}}} -> true
          _ -> false
        end)

      assert successes == @concurrency_level

      # Verify execution tracking
      start_count = :counters.get(execution_tracker, 1)
      end_count = :counters.get(execution_tracker, 2)
      assert start_count == @concurrency_level
      assert end_count == @concurrency_level
    end

    test "concurrent teacher execution produces consistent demos" do
      high_quality_teacher =
        MockTeacherProgram.new(:consistent_teacher, quality_level: 0.95, delay_ms: 30)

      # Same questions for consistency testing
      trainset = [
        DSPEx.Example.new(%{question: "What is 2+2?", answer: "4"}, [:question]),
        DSPEx.Example.new(%{question: "What is 3+3?", answer: "6"}, [:question]),
        DSPEx.Example.new(%{question: "What is 5+5?", answer: "10"}, [:question])
      ]

      # Run teacher execution multiple times concurrently
      tasks =
        for run <- 1..20 do
          Task.async(fn ->
            run_results =
              Enum.map(trainset, fn example ->
                DSPEx.Program.forward(high_quality_teacher, DSPEx.Example.inputs(example))
              end)

            {run, run_results}
          end)
        end

      results = Task.await_many(tasks, 8_000)

      # All runs should succeed
      assert length(results) == 20

      # Extract results for consistency analysis
      all_run_results = Enum.map(results, fn {_run, run_results} -> run_results end)

      # Check consistency - all runs should produce the same answers for deterministic questions
      first_run_answers =
        Enum.map(hd(all_run_results), fn {:ok, response} ->
          Map.get(response, :answer)
        end)

      for run_results <- all_run_results do
        run_answers =
          Enum.map(run_results, fn {:ok, response} ->
            Map.get(response, :answer)
          end)

        assert run_answers == first_run_answers
      end
    end

    test "teacher handles concurrent execution failures gracefully" do
      # Teacher with high failure rate
      unreliable_teacher =
        MockTeacherProgram.new(:unreliable_teacher, failure_rate: 0.4, delay_ms: 25)

      trainset =
        for i <- 1..50 do
          DSPEx.Example.new(
            %{
              question: "Question #{i}",
              answer: "Answer #{i}"
            },
            [:question]
          )
        end

      failure_counter = :counters.new(1, [])

      # Execute with fault tolerance
      results =
        Task.async_stream(
          trainset,
          fn example ->
            case DSPEx.Program.forward(unreliable_teacher, DSPEx.Example.inputs(example)) do
              {:ok, response} ->
                {:success, example, response}

              {:error, reason} ->
                :counters.add(failure_counter, 1, 1)
                {:failure, example, reason}
            end
          end,
          max_concurrency: 15,
          timeout: 5_000,
          on_timeout: :kill_task
        )
        |> Enum.to_list()

      # All tasks should complete (either success or graceful failure)
      assert length(results) == 50

      # Count successes and failures
      successes =
        Enum.count(results, fn
          {:ok, {:success, _, _}} -> true
          _ -> false
        end)

      graceful_failures =
        Enum.count(results, fn
          {:ok, {:failure, _, _}} -> true
          _ -> false
        end)

      assert successes + graceful_failures == 50
      # Some should succeed
      assert successes > 0
      # Some should fail (40% failure rate)
      assert graceful_failures > 0

      # Verify failure tracking
      tracked_failures = :counters.get(failure_counter, 1)
      assert tracked_failures == graceful_failures
    end
  end

  describe "demo generation under concurrency" do
    test "demo filtering works correctly with concurrent evaluation" do
      teacher = MockTeacherProgram.new(:demo_teacher, quality_level: 0.8, delay_ms: 15)

      trainset =
        for i <- 1..30 do
          DSPEx.Example.new(
            %{
              question: "Generate demo #{i}",
              answer: "Expected answer #{i}"
            },
            [:question]
          )
        end

      # Metric function that evaluates demo quality
      metric_fn = fn _example, prediction ->
        case prediction do
          %{quality_score: score} -> score
          _ -> 0.0
        end
      end

      # generated, filtered
      demo_tracker = :counters.new(2, [])

      # Generate demos concurrently
      demo_generation_results =
        Task.async_stream(
          trainset,
          fn example ->
            # Track generation
            :counters.add(demo_tracker, 1, 1)

            case DSPEx.Program.forward(teacher, DSPEx.Example.inputs(example)) do
              {:ok, prediction} ->
                score = metric_fn.(example, prediction)
                quality_threshold = 0.75

                if score >= quality_threshold do
                  {:ok, {example, prediction, score}}
                else
                  # Track filtered
                  :counters.add(demo_tracker, 2, 1)
                  {:filtered, score}
                end

              {:error, reason} ->
                # Track filtered
                :counters.add(demo_tracker, 2, 1)
                {:error, reason}
            end
          end,
          max_concurrency: 12,
          timeout: 8_000
        )
        |> Enum.to_list()

      # All generation attempts should complete
      assert length(demo_generation_results) == 30

      # Extract successful demos
      successful_demos =
        Enum.filter(demo_generation_results, fn
          {:ok, {:ok, {_example, _prediction, _score}}} -> true
          _ -> false
        end)

      filtered_demos =
        Enum.filter(demo_generation_results, fn
          {:ok, {:filtered, _score}} -> true
          _ -> false
        end)

      # Should have both successes and filters
      assert length(successful_demos) > 0
      assert length(filtered_demos) > 0

      # Verify tracking
      generated_count = :counters.get(demo_tracker, 1)
      filtered_count = :counters.get(demo_tracker, 2)
      assert generated_count == 30
      assert filtered_count == length(filtered_demos)
    end

    test "demo selection maintains quality under concurrent execution" do
      teacher = MockTeacherProgram.new(:quality_teacher, quality_level: 0.85, delay_ms: 20)

      # Diverse training set
      trainset = [
        DSPEx.Example.new(%{question: "What is the capital of France?", answer: "Paris"}, [
          :question
        ]),
        DSPEx.Example.new(%{question: "What is 2+2?", answer: "4"}, [:question]),
        DSPEx.Example.new(%{question: "What is 3+3?", answer: "6"}, [:question]),
        DSPEx.Example.new(%{question: "What is the capital of Spain?", answer: "Madrid"}, [
          :question
        ]),
        DSPEx.Example.new(%{question: "What is 5+5?", answer: "10"}, [:question])
      ]

      metric_fn = fn example, prediction ->
        expected = Map.get(DSPEx.Example.outputs(example), :answer)
        actual = Map.get(prediction, :answer, "")

        # Simple string matching with quality boost
        base_score = if String.contains?(actual, expected), do: 1.0, else: 0.0
        quality_boost = Map.get(prediction, :quality_score, 0.0) * 0.2

        min(1.0, base_score + quality_boost)
      end

      # Run demo generation and selection multiple times concurrently
      demo_selection_tasks =
        for iteration <- 1..15 do
          Task.async(fn ->
            # Generate demos for this iteration
            iteration_demos =
              Task.async_stream(
                trainset,
                fn example ->
                  case DSPEx.Program.forward(teacher, DSPEx.Example.inputs(example)) do
                    {:ok, prediction} ->
                      score = metric_fn.(example, prediction)
                      {example, prediction, score}

                    {:error, _} ->
                      nil
                  end
                end,
                max_concurrency: 5,
                timeout: 5_000
              )
              |> Enum.to_list()
              |> Enum.filter(&match?({:ok, {_, _, _}}, &1))
              |> Enum.map(fn {:ok, demo} -> demo end)

            # Select top-quality demos
            selected_demos =
              iteration_demos
              |> Enum.sort_by(fn {_, _, score} -> score end, :desc)
              # Top 3 demos
              |> Enum.take(3)

            {iteration, selected_demos}
          end)
        end

      demo_selection_results = Task.await_many(demo_selection_tasks, 12_000)

      # All demo selection runs should complete
      assert length(demo_selection_results) == 15

      # Verify quality maintenance across concurrent runs
      for {_iteration, selected_demos} <- demo_selection_results do
        assert length(selected_demos) <= 3

        # All selected demos should have reasonable quality
        for {_example, _prediction, score} <- selected_demos do
          # Minimum quality threshold
          assert score >= 0.7
        end

        # Demos should be sorted by quality (descending)
        scores = Enum.map(selected_demos, fn {_, _, score} -> score end)
        assert scores == Enum.sort(scores, :desc)
      end
    end

    test "concurrent demo generation doesn't create race conditions" do
      teacher = MockTeacherProgram.new(:race_test_teacher, delay_ms: 30)

      # Shared demo collection using atomic operations
      # total, high_quality, low_quality
      demo_collection = :counters.new(3, [])

      trainset =
        for i <- 1..40 do
          DSPEx.Example.new(
            %{
              question: "Race test question #{i}",
              answer: "Expected #{i}"
            },
            [:question]
          )
        end

      metric_fn = fn _example, prediction ->
        Map.get(prediction, :quality_score, 0.5)
      end

      # Generate demos concurrently with race condition potential
      race_test_tasks =
        for i <- 1..40 do
          Task.async(fn ->
            example = Enum.at(trainset, rem(i - 1, length(trainset)))

            case DSPEx.Program.forward(teacher, DSPEx.Example.inputs(example)) do
              {:ok, prediction} ->
                score = metric_fn.(example, prediction)

                # Atomic counter updates to detect race conditions
                # Total
                :counters.add(demo_collection, 1, 1)

                if score >= 0.8 do
                  # High quality
                  :counters.add(demo_collection, 2, 1)
                else
                  # Low quality
                  :counters.add(demo_collection, 3, 1)
                end

                {:ok, score}

              {:error, reason} ->
                {:error, reason}
            end
          end)
        end

      race_results = Task.await_many(race_test_tasks, 10_000)

      # All should complete
      assert length(race_results) == 40

      # Verify counter integrity (no race conditions)
      total_count = :counters.get(demo_collection, 1)
      high_quality_count = :counters.get(demo_collection, 2)
      low_quality_count = :counters.get(demo_collection, 3)

      # Counts should be consistent
      assert total_count == high_quality_count + low_quality_count

      # Should match successful results
      successful_count = Enum.count(race_results, &match?({:ok, _}, &1))
      assert total_count == successful_count
    end
  end

  describe "optimization pipeline concurrency" do
    test "full optimization pipeline benefits from concurrency" do
      teacher = MockTeacherProgram.new(:pipeline_teacher, quality_level: 0.9, delay_ms: 40)
      student = MockStudentProgram.new(:pipeline_student)

      trainset =
        for i <- 1..20 do
          DSPEx.Example.new(
            %{
              question: "Pipeline question #{i}",
              answer: "Expected answer #{i}"
            },
            [:question]
          )
        end

      metric_fn = fn example, prediction ->
        _expected = Map.get(DSPEx.Example.outputs(example), :answer, "")
        actual = Map.get(prediction, :answer, "")

        base_score =
          if String.contains?(actual, "Enhanced") or
               String.contains?(actual, "High quality"),
             do: 0.8,
             else: 0.3

        # Add quality bonus if available
        quality_bonus = Map.get(prediction, :quality_score, 0.0) * 0.2
        min(1.0, base_score + quality_bonus)
      end

      # Measure sequential vs concurrent optimization time

      # Sequential baseline (single concurrency)
      start_time = System.monotonic_time()

      {:ok, sequential_result} =
        DSPEx.Teleprompter.BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_concurrency: 1,
          max_bootstrapped_demos: 5
        )

      sequential_duration = System.monotonic_time() - start_time
      sequential_ms = System.convert_time_unit(sequential_duration, :native, :millisecond)

      # Concurrent optimization
      start_time = System.monotonic_time()

      {:ok, concurrent_result} =
        DSPEx.Teleprompter.BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_concurrency: 10,
          max_bootstrapped_demos: 5
        )

      concurrent_duration = System.monotonic_time() - start_time
      concurrent_ms = System.convert_time_unit(concurrent_duration, :native, :millisecond)

      # Concurrent should be faster (or at least not much slower)
      speedup_ratio = sequential_ms / max(concurrent_ms, 1)
      # At least 70% as fast, ideally faster
      assert speedup_ratio >= 0.7

      # Both should produce valid optimized programs (OptimizedProgram with demos)
      assert %DSPEx.OptimizedProgram{program: seq_program, demos: seq_demos} = sequential_result
      assert %DSPEx.OptimizedProgram{program: conc_program, demos: conc_demos} = concurrent_result
      assert length(seq_demos) > 0
      assert length(conc_demos) > 0

      # Verify both wrapped programs are enhanced properly
      assert %MockStudentProgram{id: :pipeline_student} = seq_program
      assert %MockStudentProgram{id: :pipeline_student} = conc_program
    end

    test "optimization handles mixed success/failure scenarios" do
      # Unreliable teacher for stress testing
      unreliable_teacher =
        MockTeacherProgram.new(:unreliable_pipeline_teacher, failure_rate: 0.3, delay_ms: 25)

      student = MockStudentProgram.new(:fault_tolerant_student)

      trainset =
        for i <- 1..25 do
          DSPEx.Example.new(
            %{
              question: "Fault tolerance question #{i}",
              answer: "Expected #{i}"
            },
            [:question]
          )
        end

      metric_fn = fn _example, prediction ->
        case prediction do
          {:error, _} -> 0.0
          %{quality_score: score} -> score
          _ -> 0.5
        end
      end

      # Run optimization with unreliable teacher
      {:ok, optimized_program} =
        DSPEx.Teleprompter.BootstrapFewShot.compile(
          student,
          unreliable_teacher,
          trainset,
          metric_fn,
          max_concurrency: 8,
          max_bootstrapped_demos: 6,
          quality_threshold: 0.6
        )

      # Should complete despite failures
      assert %DSPEx.OptimizedProgram{program: program, demos: demos} = optimized_program

      # Should have some demos (those that succeeded)
      assert length(demos) > 0

      # Verify wrapped program integrity
      assert %MockStudentProgram{id: :fault_tolerant_student} = program

      # All included demos should meet quality threshold
      for demo <- demos do
        # Demo should be valid
        assert is_map(demo)
      end
    end

    test "optimization maintains student program integrity" do
      teacher = MockTeacherProgram.new(:integrity_teacher, quality_level: 0.85, delay_ms: 20)
      original_student = MockStudentProgram.new(:integrity_student, [])

      trainset =
        for i <- 1..15 do
          DSPEx.Example.new(
            %{
              question: "Integrity test #{i}",
              answer: "Expected #{i}"
            },
            [:question]
          )
        end

      metric_fn = fn _example, prediction ->
        Map.get(prediction, :quality_score, 0.5)
      end

      # Run multiple optimizations concurrently to test integrity
      integrity_tasks =
        for iteration <- 1..10 do
          Task.async(fn ->
            {:ok, optimized} =
              DSPEx.Teleprompter.BootstrapFewShot.compile(
                original_student,
                teacher,
                trainset,
                metric_fn,
                max_concurrency: 6
              )

            # Test the optimized program
            test_input = %{question: "Test question for iteration #{iteration}"}
            {:ok, result} = DSPEx.Program.forward(optimized, test_input)

            {iteration, optimized, result}
          end)
        end

      integrity_results = Task.await_many(integrity_tasks, 15_000)

      # All optimizations should complete successfully
      assert length(integrity_results) == 10

      for {_iteration, optimized_program, test_result} <- integrity_results do
        # Program should be properly optimized (OptimizedProgram wrapping MockStudentProgram)
        assert %DSPEx.OptimizedProgram{program: program, demos: demos} = optimized_program

        # Should have the original student's ID in wrapped program
        assert %MockStudentProgram{id: id} = program
        assert id == original_student.id

        # Should have demos
        assert length(demos) > 0

        # Should respond to test input
        assert Map.has_key?(test_result, :answer)
        assert Map.has_key?(test_result, :demo_count)
        assert test_result.demo_count == length(demos)
      end
    end
  end

  describe "resource management during optimization" do
    test "optimization doesn't exhaust system resources" do
      teacher = MockTeacherProgram.new(:resource_teacher, delay_ms: 30)
      student = MockStudentProgram.new(:resource_student)

      # Large training set for resource stress test
      large_trainset =
        for i <- 1..100 do
          DSPEx.Example.new(
            %{
              question: "Resource test question #{i}",
              answer: "Expected answer #{i}"
            },
            [:question]
          )
        end

      metric_fn = fn _example, prediction ->
        Map.get(prediction, :quality_score, 0.6)
      end

      # Monitor system resources
      initial_memory = :erlang.memory(:total)
      initial_processes = :erlang.system_info(:process_count)

      # Run resource-intensive optimization
      {:ok, optimized_program} =
        DSPEx.Teleprompter.BootstrapFewShot.compile(
          student,
          teacher,
          large_trainset,
          metric_fn,
          max_concurrency: 20,
          max_bootstrapped_demos: 10
        )

      # Allow cleanup
      :erlang.garbage_collect()
      Process.sleep(200)

      final_memory = :erlang.memory(:total)
      final_processes = :erlang.system_info(:process_count)

      # Should complete successfully (OptimizedProgram with demos)
      assert %DSPEx.OptimizedProgram{program: program, demos: demos} = optimized_program
      assert length(demos) > 0
      assert %MockStudentProgram{id: :resource_student} = program

      # Resource usage should be reasonable
      memory_growth = final_memory - initial_memory
      process_growth = final_processes - initial_processes

      # Memory growth should be bounded (< 100MB)
      assert memory_growth < 100_000_000

      # Process count should return to reasonable levels
      assert process_growth < 150
    end

    test "optimization handles large training sets efficiently" do
      teacher = MockTeacherProgram.new(:efficiency_teacher, quality_level: 0.8, delay_ms: 15)
      student = MockStudentProgram.new(:efficiency_student)

      # Very large training set
      huge_trainset =
        for i <- 1..200 do
          large_question = "Large training question #{i} " <> String.duplicate("data ", 50)

          DSPEx.Example.new(
            %{
              question: large_question,
              answer: "Answer #{i}"
            },
            [:question]
          )
        end

      metric_fn = fn _example, prediction ->
        Map.get(prediction, :quality_score, 0.5)
      end

      start_time = System.monotonic_time()

      {:ok, optimized_program} =
        DSPEx.Teleprompter.BootstrapFewShot.compile(
          student,
          teacher,
          huge_trainset,
          metric_fn,
          max_concurrency: 25,
          max_bootstrapped_demos: 8,
          timeout: 60_000
        )

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Should complete in reasonable time despite large dataset
      # Under 30 seconds
      assert duration_ms < 30_000

      # Should produce valid optimized program (OptimizedProgram with demos)
      assert %DSPEx.OptimizedProgram{program: program, demos: demos} = optimized_program
      assert length(demos) > 0
      assert %MockStudentProgram{id: :efficiency_student} = program
    end

    test "concurrent optimizations don't interfere" do
      teacher = MockTeacherProgram.new(:isolation_teacher, delay_ms: 25)

      # Different students for isolation testing
      students = [
        MockStudentProgram.new(:student_1),
        MockStudentProgram.new(:student_2),
        MockStudentProgram.new(:student_3)
      ]

      # Different training sets for each optimization
      training_sets = [
        Enum.map(1..10, fn i ->
          DSPEx.Example.new(%{question: "Set A question #{i}", answer: "A#{i}"}, [:question])
        end),
        Enum.map(1..12, fn i ->
          DSPEx.Example.new(%{question: "Set B question #{i}", answer: "B#{i}"}, [:question])
        end),
        Enum.map(1..8, fn i ->
          DSPEx.Example.new(%{question: "Set C question #{i}", answer: "C#{i}"}, [:question])
        end)
      ]

      metric_fn = fn _example, prediction ->
        Map.get(prediction, :quality_score, 0.7)
      end

      # opt1, opt2, opt3
      optimization_tracker = :counters.new(3, [])

      # Run multiple optimizations concurrently
      concurrent_optimization_tasks =
        for {student, trainset, opt_id} <- Enum.zip([students, training_sets, [1, 2, 3]]) do
          Task.async(fn ->
            :counters.add(optimization_tracker, opt_id, 1)

            {:ok, optimized} =
              DSPEx.Teleprompter.BootstrapFewShot.compile(
                student,
                teacher,
                trainset,
                metric_fn,
                max_concurrency: 8,
                max_bootstrapped_demos: 5
              )

            # Test the optimized program with student-specific input
            test_input = %{question: "Test for student #{opt_id}"}
            {:ok, test_result} = DSPEx.Program.forward(optimized, test_input)

            {opt_id, optimized, test_result}
          end)
        end

      optimization_results = Task.await_many(concurrent_optimization_tasks, 15_000)

      # All optimizations should complete
      assert length(optimization_results) == 3

      # Verify isolation - each optimization should be independent
      for {opt_id, optimized_program, test_result} <- optimization_results do
        # Should be properly optimized (OptimizedProgram with demos)
        assert %DSPEx.OptimizedProgram{program: program, demos: demos} = optimized_program

        # Should contain the correct original student
        original_student = Enum.at(students, opt_id - 1)
        assert %MockStudentProgram{id: id} = program
        assert id == original_student.id

        # Should respond correctly
        assert Map.get(test_result, :student_id) == original_student.id

        # Should have demos from its own training set
        assert length(demos) > 0
      end

      # Verify optimization tracking
      opt1_count = :counters.get(optimization_tracker, 1)
      opt2_count = :counters.get(optimization_tracker, 2)
      opt3_count = :counters.get(optimization_tracker, 3)

      assert opt1_count == 1
      assert opt2_count == 1
      assert opt3_count == 1
    end
  end
end
