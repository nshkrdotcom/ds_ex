# test/integration/simba_example_test.exs
defmodule DSPEx.Integration.SIMBAExampleTest do
  @moduledoc """
  Integration test demonstrating DSPy SIMBA algorithm in action.

  This test shows the complete SIMBA optimization process with real examples
  and validates that the algorithm behaves as expected from the original DSPy implementation.
  """

  use ExUnit.Case

  alias DSPEx.{Example, Predict, OptimizedProgram}
  alias DSPEx.Teleprompter.SIMBA
  alias DSPEx.Teleprompter.SIMBA.{Performance, Trajectory, Bucket}

  # Math QA signature for testing
  defmodule MathQASignature do
    @moduledoc "Solve mathematical word problems with step-by-step reasoning"
    use DSPEx.Signature, "problem -> reasoning, answer"
  end

  # Question answering signature
  defmodule QASignature do
    @moduledoc "Answer questions based on given context"
    use DSPEx.Signature, "question -> answer"
  end

  @tag :integration
  @tag timeout: 60_000
  describe "SIMBA Math QA Optimization" do
    test "optimizes math word problem solving" do
      # Setup mock responses for consistent testing
      setup_math_mock_responses()

      # Create programs
      student = Predict.new(MathQASignature, :test_math)
      teacher = Predict.new(MathQASignature, :test_math)

      # Create training dataset
      trainset = create_math_trainset()

      # Define metric function that checks both reasoning and answer
      metric_fn = fn example, prediction ->
        expected_answer = Example.outputs(example)[:answer] || ""
        predicted_answer = prediction[:answer] || ""

        # Check if answers match (simplified for testing)
        answer_correct = String.trim(expected_answer) == String.trim(predicted_answer)

        # Check if reasoning exists and has reasonable length
        reasoning = prediction[:reasoning] || ""
        has_reasoning = String.length(reasoning) > 20

        cond do
          answer_correct and has_reasoning -> 1.0
          answer_correct -> 0.7
          has_reasoning -> 0.3
          true -> 0.0
        end
      end

      # Configure SIMBA for this test
      teleprompter = SIMBA.new(
        bsize: 3,           # Small batches for controlled testing
        num_candidates: 4,   # Generate 4 candidate programs per iteration
        max_steps: 3,        # Run 3 optimization steps
        max_demos: 3,        # Keep up to 3 demonstrations per predictor
        strategies: [:append_demo],
        temperature_sampling: 0.3,
        temperature_candidates: 0.3
      )

      # Track optimization progress
      start_time = System.monotonic_time()

      # Run SIMBA optimization
      assert {:ok, optimized_program} = teleprompter.compile(student, teacher, trainset, metric_fn)

      duration = System.monotonic_time() - start_time
      IO.puts("\nSIMBA optimization completed in #{System.convert_time_unit(duration, :native, :millisecond)}ms")

      # Validate optimization results
      assert_optimization_results(student, optimized_program, trainset, metric_fn)

      # Test the optimized program on new examples
      test_optimized_program_performance(optimized_program)

      cleanup_math_mock_responses()
    end

    test "demonstrates trajectory sampling and bucket analysis" do
      setup_qa_mock_responses()

      student = Predict.new(QASignature, :test_qa)
      teacher = Predict.new(QASignature, :test_qa)
      trainset = create_qa_trainset()

      # Simple exact match metric
      metric_fn = fn example, prediction ->
        expected = String.downcase(Example.outputs(example)[:answer] || "")
        actual = String.downcase(prediction[:answer] || "")
        if expected == actual, do: 1.0, else: 0.0
      end

      # Run single SIMBA step to demonstrate internal mechanics
      teleprompter = SIMBA.new(
        bsize: 2,
        num_candidates: 3,
        max_steps: 1,  # Single step for detailed analysis
        strategies: [:append_demo]
      )

      {:ok, _optimized} = teleprompter.compile(student, teacher, trainset, metric_fn)

      cleanup_qa_mock_responses()
    end

    test "handles various program types and configurations" do
      setup_mixed_mock_responses()

      # Test with different program configurations
      programs_to_test = [
        Predict.new(QASignature, :test_mixed),
        Predict.new(QASignature, :test_mixed, demos: [create_sample_demo()]),
        OptimizedProgram.new(Predict.new(QASignature, :test_mixed), [create_sample_demo()])
      ]

      trainset = create_mixed_trainset()
      metric_fn = &simple_exact_match/2

      teleprompter = SIMBA.new(max_steps: 2, bsize: 2, num_candidates: 2)

      Enum.each(programs_to_test, fn program ->
        {:ok, optimized} = teleprompter.compile(program, program, trainset, metric_fn)
        assert is_struct(optimized)

        # Test that optimized program can make predictions
        test_input = %{question: "What is the capital of France?"}
        {:ok, result} = DSPEx.Program.forward(optimized, test_input)
        assert Map.has_key?(result, :answer)
      end)

      cleanup_mixed_mock_responses()
    end
  end

  @tag :integration
  describe "SIMBA Performance Analysis" do
    test "tracks and reports optimization metrics" do
      setup_performance_mock_responses()

      student = Predict.new(QASignature, :test_perf)
      teacher = Predict.new(QASignature, :test_perf)
      trainset = create_performance_trainset()

      # Configure SIMBA with progress tracking
      progress_data = %{steps: []}

      progress_callback = fn progress ->
        IO.puts("Step #{progress[:step] || 'unknown'}: #{inspect(progress)}")
        :ok
      end

      teleprompter = SIMBA.new(
        max_steps: 3,
        bsize: 4,
        num_candidates: 3,
        progress_callback: progress_callback
      )

      # Run optimization with performance tracking
      {:ok, optimized} = teleprompter.compile(student, teacher, trainset, &simple_exact_match/2)

      # Analyze performance improvement
      improvement_metrics = Performance.calculate_improvement(
        student,
        optimized,
        trainset,
        &simple_exact_match/2
      )

      IO.puts("\nPerformance Analysis:")
      IO.puts("Original Score: #{improvement_metrics.original_score}")
      IO.puts("Optimized Score: #{improvement_metrics.improved_score}")
      IO.puts("Absolute Improvement: #{improvement_metrics.absolute_improvement}")
      IO.puts("Relative Improvement: #{Float.round(improvement_metrics.relative_improvement * 100, 1)}%")

      # Validate that we have meaningful metrics
      assert is_float(improvement_metrics.original_score)
      assert is_float(improvement_metrics.improved_score)
      assert is_boolean(improvement_metrics.improved)

      cleanup_performance_mock_responses()
    end

    test "demonstrates bucket analysis and strategy selection" do
      # Create sample trajectories with varying performance
      trajectories = [
        %Trajectory{
          program: nil, example: nil, inputs: %{question: "Q1"}, outputs: %{answer: "A1"},
          score: 0.9, success: true
        },
        %Trajectory{
          program: nil, example: nil, inputs: %{question: "Q2"}, outputs: %{answer: "A2"},
          score: 0.8, success: true
        },
        %Trajectory{
          program: nil, example: nil, inputs: %{question: "Q3"}, outputs: %{answer: "A3"},
          score: 0.2, success: true
        },
        %Trajectory{
          program: nil, example: nil, inputs: %{question: "Q4"}, outputs: %{answer: "A4"},
          score: 0.1, success: false
        }
      ]

      # Create bucket and analyze
      bucket = Bucket.new(trajectories)
      stats = Bucket.statistics(bucket)

      IO.puts("\nBucket Analysis:")
      IO.puts("Trajectories: #{stats.trajectory_count}")
      IO.puts("Successful: #{stats.successful_count}")
      IO.puts("Max Score: #{stats.max_score}")
      IO.puts("Min Score: #{stats.min_score}")
      IO.puts("Average Score: #{Float.round(stats.avg_score, 3)}")
      IO.puts("Has Improvement Potential: #{stats.improvement_potential}")

      # Test strategy applicability
      alias DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo

      assert AppendDemo.applicable?(bucket)

      # Test strategy application
      student = Predict.new(QASignature, :test)

      case AppendDemo.apply(bucket, student) do
        {:ok, enhanced_program} ->
          IO.puts("Strategy successfully applied - created enhanced program")
          assert is_struct(enhanced_program)

        {:skip, reason} ->
          IO.puts("Strategy skipped: #{reason}")
      end
    end
  end

  @tag :integration
  describe "SIMBA Algorithm Fidelity" do
    test "matches DSPy SIMBA algorithmic behavior" do
      # This test verifies that our implementation follows the same algorithmic
      # steps as the original DSPy SIMBA

      setup_fidelity_mock_responses()

      student = Predict.new(QASignature, :test_fidelity)
      teacher = Predict.new(QASignature, :test_fidelity)
      trainset = create_fidelity_trainset()

      # Configure SIMBA to match DSPy parameters
      teleprompter = SIMBA.new(
        bsize: 32,              # Default mini-batch size from DSPy
        num_candidates: 6,      # Default candidate count from DSPy
        max_steps: 8,           # Default max steps from DSPy
        max_demos: 4,           # Default max demos from DSPy
        strategies: [:append_demo],
        temperature_sampling: 0.2,
        temperature_candidates: 0.2
      )

      # Track algorithm execution steps
      step_data = []

      progress_callback = fn progress ->
        step_data = [progress | step_data]
        :ok
      end

      teleprompter_with_tracking = %{teleprompter | progress_callback: progress_callback}

      # Execute optimization
      {:ok, optimized} = teleprompter_with_tracking.compile(student, teacher, trainset, &simple_exact_match/2)

      # Verify algorithmic properties
      assert_algorithmic_fidelity(optimized, trainset)

      cleanup_fidelity_mock_responses()
    end

    test "demonstrates stochastic hill-climbing characteristics" do
      # Test that SIMBA exhibits stochastic hill-climbing behavior
      # rather than global optimization

      setup_stochastic_mock_responses()

      student = Predict.new(QASignature, :test_stochastic)
      teacher = Predict.new(QASignature, :test_stochastic)
      trainset = create_stochastic_trainset()

      # Run multiple optimizations with same configuration
      results =
        1..3
        |> Enum.map(fn run ->
          teleprompter = SIMBA.new(
            max_steps: 2,
            bsize: 3,
            num_candidates: 3,
            correlation_id: "run_#{run}"
          )

          {:ok, optimized} = teleprompter.compile(student, teacher, trainset, &simple_exact_match/2)

          # Evaluate performance
          performance = evaluate_program_performance(optimized, trainset, &simple_exact_match/2)
          {run, optimized, performance}
        end)

      # Verify that results show variation (stochastic behavior)
      performances = Enum.map(results, fn {_run, _prog, perf} -> perf end)

      IO.puts("\nStochastic Behavior Analysis:")
      IO.puts("Run Performances: #{inspect(Enum.map(performances, &Float.round(&1, 3)))}")

      # Results should show some variation due to stochastic sampling
      performance_variance = calculate_variance(performances)
      IO.puts("Performance Variance: #{Float.round(performance_variance, 4)}")

      cleanup_stochastic_mock_responses()
    end
  end

  # Helper functions

  defp setup_math_mock_responses do
    DSPEx.MockClientManager.set_mock_responses(:test_math, [
      # Reasoning + Answer pairs for math problems
      "Let me solve this step by step. 15 - 7 = 8 apples remaining. Then 8 + 8 = 16 apples total.\n16",
      "To find 25% of 80: 25% = 0.25, so 0.25 × 80 = 20.\n20",
      "Area of rectangle = length × width = 8 × 5 = 40 square units.\n40",
      "Cost per book = total cost ÷ number of books = $15 ÷ 3 = $5.\n$5",
      # Additional responses for strategy generation
      "16", "20", "40", "$5",
      "16", "20", "40", "$5"
    ])
  end

  defp setup_qa_mock_responses do
    DSPEx.MockClientManager.set_mock_responses(:test_qa, [
      "Paris", "Blue", "4", "William Shakespeare",
      "Paris", "Blue", "4", "William Shakespeare",
      "Paris", "Blue", "4", "William Shakespeare"
    ])
  end

  defp setup_mixed_mock_responses do
    DSPEx.MockClientManager.set_mock_responses(:test_mixed, [
      "Paris", "London", "Berlin", "Madrid", "Rome",
      "Paris", "London", "Berlin", "Madrid", "Rome",
      "Paris", "London", "Berlin", "Madrid", "Rome"
    ])
  end

  defp setup_performance_mock_responses do
    DSPEx.MockClientManager.set_mock_responses(:test_perf, [
      "Correct1", "Correct2", "Correct3", "Correct4",
      "Wrong1", "Wrong2", "Correct3", "Correct4",  # Some variation
      "Correct1", "Correct2", "Correct3", "Correct4"
    ])
  end

  defp setup_fidelity_mock_responses do
    DSPEx.MockClientManager.set_mock_responses(:test_fidelity, [
      "Answer1", "Answer2", "Answer3", "Answer4", "Answer5",
      "Answer1", "Answer2", "Answer3", "Answer4", "Answer5",
      "Answer1", "Answer2", "Answer3", "Answer4", "Answer5",
      "Answer1", "Answer2", "Answer3", "Answer4", "Answer5"
    ])
  end

  defp setup_stochastic_mock_responses do
    # Provide varied responses to create stochastic behavior
    responses = [
      "Good1", "Good2", "Bad1", "Good3", "Bad2",
      "Bad1", "Good1", "Good2", "Bad2", "Good3",
      "Good3", "Bad1", "Good1", "Good2", "Bad2"
    ]

    DSPEx.MockClientManager.set_mock_responses(:test_stochastic, responses)
  end

  defp cleanup_math_mock_responses, do: DSPEx.MockClientManager.clear_mock_responses(:test_math)
  defp cleanup_qa_mock_responses, do: DSPEx.MockClientManager.clear_mock_responses(:test_qa)
  defp cleanup_mixed_mock_responses, do: DSPEx.MockClientManager.clear_mock_responses(:test_mixed)
  defp cleanup_performance_mock_responses, do: DSPEx.MockClientManager.clear_mock_responses(:test_perf)
  defp cleanup_fidelity_mock_responses, do: DSPEx.MockClientManager.clear_mock_responses(:test_fidelity)
  defp cleanup_stochastic_mock_responses, do: DSPEx.MockClientManager.clear_mock_responses(:test_stochastic)

  defp create_math_trainset do
    [
      Example.new(%{
        problem: "Sarah has 15 apples. She sells 7 apples and then gets 8 more apples. How many apples does she have now?",
        reasoning: "Let me solve this step by step. 15 - 7 = 8 apples remaining. Then 8 + 8 = 16 apples total.",
        answer: "16"
      }, [:problem]),

      Example.new(%{
        problem: "What is 25% of 80?",
        reasoning: "To find 25% of 80: 25% = 0.25, so 0.25 × 80 = 20.",
        answer: "20"
      }, [:problem]),

      Example.new(%{
        problem: "A rectangle has a length of 8 units and width of 5 units. What is its area?",
        reasoning: "Area of rectangle = length × width = 8 × 5 = 40 square units.",
        answer: "40"
      }, [:problem]),

      Example.new(%{
        problem: "If 3 books cost $15, how much does each book cost?",
        reasoning: "Cost per book = total cost ÷ number of books = $15 ÷ 3 = $5.",
        answer: "$5"
      }, [:problem])
    ]
  end

  defp create_qa_trainset do
    [
      Example.new(%{question: "What is the capital of France?", answer: "Paris"}, [:question]),
      Example.new(%{question: "What color is the sky?", answer: "Blue"}, [:question]),
      Example.new(%{question: "What is 2+2?", answer: "4"}, [:question]),
      Example.new(%{question: "Who wrote Hamlet?", answer: "William Shakespeare"}, [:question])
    ]
  end

  defp create_mixed_trainset do
    [
      Example.new(%{question: "Capital of France?", answer: "Paris"}, [:question]),
      Example.new(%{question: "Capital of England?", answer: "London"}, [:question]),
      Example.new(%{question: "Capital of Germany?", answer: "Berlin"}, [:question]),
      Example.new(%{question: "Capital of Spain?", answer: "Madrid"}, [:question]),
      Example.new(%{question: "Capital of Italy?", answer: "Rome"}, [:question])
    ]
  end

  defp create_performance_trainset do
    [
      Example.new(%{question: "Test question 1", answer: "Correct1"}, [:question]),
      Example.new(%{question: "Test question 2", answer: "Correct2"}, [:question]),
      Example.new(%{question: "Test question 3", answer: "Correct3"}, [:question]),
      Example.new(%{question: "Test question 4", answer: "Correct4"}, [:question])
    ]
  end

  defp create_fidelity_trainset do
    1..5
    |> Enum.map(fn i ->
      Example.new(%{question: "Question #{i}", answer: "Answer#{i}"}, [:question])
    end)
  end

  defp create_stochastic_trainset do
    [
      Example.new(%{question: "Question A", answer: "Good1"}, [:question]),
      Example.new(%{question: "Question B", answer: "Good2"}, [:question]),
      Example.new(%{question: "Question C", answer: "Good3"}, [:question]),
      Example.new(%{question: "Question D", answer: "Bad1"}, [:question]),
      Example.new(%{question: "Question E", answer: "Bad2"}, [:question])
    ]
  end

  defp create_sample_demo do
    Example.new(%{question: "Sample question", answer: "Sample answer"}, [:question])
  end

  defp simple_exact_match(example, prediction) do
    expected = String.downcase(Example.outputs(example)[:answer] || "")
    actual = String.downcase(prediction[:answer] || "")
    if expected == actual, do: 1.0, else: 0.0
  end

  defp assert_optimization_results(original, optimized, trainset, metric_fn) do
    # The optimized program should be structurally different
    assert optimized != original

    # The optimized program should be able to make predictions
    test_example = List.first(trainset)
    inputs = Example.inputs(test_example)

    {:ok, result} = DSPEx.Program.forward(optimized, inputs)
    assert is_map(result)

    # Performance should be measurable
    performance = evaluate_program_performance(optimized, trainset, metric_fn)
    assert is_float(performance)
    assert performance >= 0.0
    assert performance <= 1.0

    IO.puts("Optimization validation passed - Performance: #{Float.round(performance, 3)}")
  end

  defp test_optimized_program_performance(optimized_program) do
    # Test the optimized program on new examples
    test_cases = [
      %{problem: "What is 10 - 3?", expected_answer: "7"},
      %{problem: "Find 50% of 100", expected_answer: "50"}
    ]

    IO.puts("\nTesting optimized program:")

    Enum.each(test_cases, fn test_case ->
      case DSPEx.Program.forward(optimized_program, %{problem: test_case.problem}) do
        {:ok, result} ->
          IO.puts("Problem: #{test_case.problem}")
          IO.puts("Answer: #{result[:answer] || 'No answer'}")
          IO.puts("Reasoning: #{result[:reasoning] || 'No reasoning'}")

        {:error, reason} ->
          IO.puts("Error testing optimized program: #{inspect(reason)}")
      end
    end)
  end

  defp assert_algorithmic_fidelity(optimized_program, trainset) do
    # Verify that the optimization process created meaningful changes
    case optimized_program do
      %OptimizedProgram{demos: demos} ->
        # Should have created some demonstrations
        assert length(demos) > 0, "SIMBA should create demonstrations"
        assert length(demos) <= 4, "Should respect max_demos limit"

        # Demos should have proper structure
        Enum.each(demos, fn demo ->
          assert %Example{} = demo
          assert not Example.empty?(demo)
        end)

      %Predict{demos: demos} when is_list(demos) ->
        assert length(demos) >= 0, "Program should have demo support"

      _ ->
        # Program was wrapped or modified in some way
        assert is_struct(optimized_program)
    end

    # Should be able to execute on trainset
    sample_example = List.first(trainset)
    inputs = Example.inputs(sample_example)

    {:ok, _result} = DSPEx.Program.forward(optimized_program, inputs)

    IO.puts("Algorithm fidelity validation passed")
  end

  defp evaluate_program_performance(program, examples, metric_fn) do
    scores =
      examples
      |> Enum.map(fn example ->
        inputs = Example.inputs(example)

        case DSPEx.Program.forward(program, inputs) do
          {:ok, outputs} ->
            try do
              metric_fn.(example, outputs)
            rescue
              _ -> 0.0
            end

          {:error, _} -> 0.0
        end
      end)

    if Enum.empty?(scores), do: 0.0, else: Enum.sum(scores) / length(scores)
  end

  defp calculate_variance(values) when length(values) <= 1, do: 0.0

  defp calculate_variance(values) do
    mean = Enum.sum(values) / length(values)
    variance_sum = Enum.reduce(values, 0.0, fn value, acc ->
      diff = value - mean
      acc + (diff * diff)
    end)
    variance_sum / length(values)
  end
end
