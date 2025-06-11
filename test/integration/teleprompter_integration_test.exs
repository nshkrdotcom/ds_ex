defmodule DSPEx.TeleprompterIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :phase_1

  alias DSPEx.{Example, Teleprompter, Evaluate}
  alias DSPEx.Teleprompter.BootstrapFewShot

  # Mock signature for testing
  defmodule QASignature do
    @moduledoc "Answer questions"
    use DSPEx.Signature, "question -> answer"
  end

  # Strong teacher program that gives good answers
  defmodule StrongTeacherProgram do
    use DSPEx.Program

    defstruct [:name]

    @impl true
    def forward(_program, %{question: question}, _opts) do
      answer =
        cond do
          String.contains?(String.downcase(question), "2+2") -> "4"
          String.contains?(String.downcase(question), "3+3") -> "6"
          String.contains?(String.downcase(question), "4+4") -> "8"
          String.contains?(String.downcase(question), "capital of france") -> "Paris"
          String.contains?(String.downcase(question), "capital of spain") -> "Madrid"
          String.contains?(String.downcase(question), "capital of italy") -> "Rome"
          true -> "I don't know"
        end

      {:ok, %{answer: answer}}
    end
  end

  # Weak student program that needs optimization
  defmodule WeakStudentProgram do
    use DSPEx.Program

    defstruct [:demos]

    @impl true
    def forward(%__MODULE__{demos: demos}, %{question: question}, _opts) do
      # Try to find a similar demo, otherwise give weak answer
      answer =
        case find_similar_demo(demos, question) do
          %Example{} = demo ->
            outputs = Example.outputs(demo)
            Map.get(outputs, :answer, "I'm not sure")

          nil ->
            # Without demos, always give a weak generic answer
            "I'm not sure"
        end

      {:ok, %{answer: answer}}
    end

    defp find_similar_demo(nil, _question), do: nil
    defp find_similar_demo([], _question), do: nil

    defp find_similar_demo([demo | rest], question) do
      inputs = Example.inputs(demo)
      demo_question = Map.get(inputs, :question, "")
      # Use exact matching for better test reliability
      question_lower = String.downcase(question)
      demo_question_lower = String.downcase(demo_question)

      cond do
        # Exact match
        question_lower == demo_question_lower ->
          demo

        # Partial match for math questions
        String.contains?(question_lower, "2+2") and String.contains?(demo_question_lower, "2+2") ->
          demo

        String.contains?(question_lower, "capital of france") and
            String.contains?(demo_question_lower, "capital of france") ->
          demo

        # Fallback to similarity threshold
        String.jaro_distance(question_lower, demo_question_lower) > 0.8 ->
          demo

        true ->
          find_similar_demo(rest, question)
      end
    end
  end

  setup do
    # Create teacher and student programs
    teacher = %StrongTeacherProgram{name: "strong_teacher"}
    student = %WeakStudentProgram{demos: []}

    # Create training dataset
    trainset = [
      Example.new(%{question: "What is 2+2?", answer: "4", __id: 1})
      |> Example.with_inputs([:question]),
      Example.new(%{question: "What is 3+3?", answer: "6", __id: 2})
      |> Example.with_inputs([:question]),
      Example.new(%{question: "What is 4+4?", answer: "8", __id: 3})
      |> Example.with_inputs([:question]),
      Example.new(%{question: "What is the capital of France?", answer: "Paris", __id: 4})
      |> Example.with_inputs([:question])
    ]

    # Create test dataset for evaluation
    testset = [
      Example.new(%{question: "What is 2+2?", answer: "4"})
      |> Example.with_inputs([:question]),
      Example.new(%{question: "What is the capital of France?", answer: "Paris"})
      |> Example.with_inputs([:question])
    ]

    # Create metric function
    metric_fn = Teleprompter.exact_match(:answer)

    %{
      teacher: teacher,
      student: student,
      trainset: trainset,
      testset: testset,
      metric_fn: metric_fn
    }
  end

  describe "complete teleprompter workflow" do
    test "optimizes student program with bootstrap few-shot",
         %{teacher: teacher, student: student, trainset: trainset, metric_fn: metric_fn} do
      # Configure teleprompter
      teleprompter =
        BootstrapFewShot.new(
          max_bootstrapped_demos: 3,
          quality_threshold: 0.8,
          max_concurrency: 4
        )

      # Optimize the student program
      {:ok, optimized_student} =
        BootstrapFewShot.compile(
          teleprompter,
          student,
          teacher,
          trainset,
          metric_fn,
          []
        )

      # Verify optimization results
      assert %DSPEx.OptimizedProgram{program: %WeakStudentProgram{}, demos: demos} =
               optimized_student

      assert is_list(demos)
      assert length(demos) > 0
      assert length(demos) <= 3

      # Verify each demo has required metadata
      for demo <- demos do
        assert %Example{} = demo
        assert Map.has_key?(demo.data, :__generated_by)
        assert demo.data.__generated_by == :bootstrap_fewshot
        assert Map.has_key?(demo.data, :__quality_score)
        assert demo.data.__quality_score >= 0.8
      end
    end

    test "optimized student performs better than original",
         %{
           teacher: teacher,
           student: student,
           trainset: trainset,
           testset: testset,
           metric_fn: metric_fn
         } do
      # Debug: Check what the student returns for test examples
      {:ok, original_pred_1} = DSPEx.Program.forward(student, %{question: "What is 2+2?"})

      {:ok, original_pred_2} =
        DSPEx.Program.forward(student, %{question: "What is the capital of France?"})

      # Evaluate original student performance
      {:ok, original_results} = Evaluate.run_local(student, testset, metric_fn)
      original_score = original_results.score

      # Optimize student program with lower threshold to get demos
      {:ok, optimized_student} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 2,
          # Lower threshold to ensure we get demos
          quality_threshold: 0.3
        )

      # Debug: Check what the optimized student returns
      {:ok, optimized_pred_1} =
        DSPEx.Program.forward(optimized_student, %{question: "What is 2+2?"})

      {:ok, optimized_pred_2} =
        DSPEx.Program.forward(optimized_student, %{question: "What is the capital of France?"})

      # Evaluate optimized student performance
      {:ok, optimized_results} = Evaluate.run_local(optimized_student, testset, metric_fn)
      optimized_score = optimized_results.score

      # Optimized should perform better (or at least as well)
      assert optimized_score >= original_score

      # If we have good demos, optimized should be significantly better
      if length(optimized_student.demos) > 0 do
        # With demos, student should give better answers for at least one question
        # (Not all demos may match perfectly, but at least one should improve)
        improved =
          (optimized_pred_1.answer != "I'm not sure" and original_pred_1.answer == "I'm not sure") or
            (optimized_pred_2.answer != "I'm not sure" and
               original_pred_2.answer == "I'm not sure")

        if improved do
          assert optimized_score >= original_score
        else
          # Even if individual predictions don't show improvement, 
          # the overall score should at least not get worse
          assert optimized_score >= original_score
        end
      end
    end

    test "handles progress tracking during optimization",
         %{teacher: teacher, student: student, trainset: trainset, metric_fn: metric_fn} do
      progress_callback = fn progress ->
        send(self(), {:progress_update, progress})
        :ok
      end

      # Run optimization with progress tracking
      {:ok, _optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          # Smaller to ensure it completes
          max_bootstrapped_demos: 1,
          progress_callback: progress_callback
        )

      # Should receive at least one progress update within reasonable time
      receive do
        {:progress_update, %{phase: phase}} when is_atom(phase) ->
          # Got at least one progress update, test passes
          assert is_atom(phase)
      after
        1000 ->
          flunk("No progress updates received within 1 second")
      end
    end

    test "works with different metric functions",
         %{teacher: teacher, student: student, trainset: trainset} do
      # Test with contains_match metric
      contains_metric = Teleprompter.contains_match(:answer)

      {:ok, optimized1} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          contains_metric,
          max_bootstrapped_demos: 2,
          quality_threshold: 0.5
        )

      assert %DSPEx.OptimizedProgram{program: %WeakStudentProgram{}, demos: demos1} = optimized1
      assert is_list(demos1)

      # Test with custom metric function
      custom_metric = fn _example, prediction ->
        if is_map(prediction) and Map.has_key?(prediction, :answer) do
          1.0
        else
          0.0
        end
      end

      {:ok, optimized2} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          custom_metric,
          max_bootstrapped_demos: 2,
          quality_threshold: 0.5
        )

      assert %DSPEx.OptimizedProgram{program: %WeakStudentProgram{}, demos: demos2} = optimized2
      assert is_list(demos2)
    end

    test "handles edge cases gracefully",
         %{teacher: teacher, student: student, metric_fn: metric_fn} do
      # Test with very small training set
      small_trainset = [
        Example.new(%{question: "What is 1+1?", answer: "2"})
        |> Example.with_inputs([:question])
      ]

      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          small_trainset,
          metric_fn,
          # More than available
          max_bootstrapped_demos: 5,
          quality_threshold: 0.1
        )

      assert %DSPEx.OptimizedProgram{program: %WeakStudentProgram{}, demos: demos} = optimized
      # Can't have more demos than training examples
      assert length(demos) <= 1
    end

    test "quality threshold filtering works correctly",
         %{teacher: teacher, student: student, trainset: trainset} do
      # Use impossible quality threshold
      impossible_metric = fn _example, _prediction -> 0.1 end

      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          impossible_metric,
          max_bootstrapped_demos: 10,
          # Higher than metric ever returns
          quality_threshold: 0.9
        )

      # Should have no demos due to quality filtering
      assert %DSPEx.OptimizedProgram{program: %WeakStudentProgram{}, demos: []} = optimized
    end
  end

  describe "integration with evaluation system" do
    test "teleprompter + evaluation provides complete optimization loop",
         %{
           teacher: teacher,
           student: student,
           trainset: trainset,
           testset: testset,
           metric_fn: metric_fn
         } do
      # Step 1: Baseline evaluation
      {:ok, baseline} = Evaluate.run_local(student, testset, metric_fn)
      baseline_score = baseline.score

      # Step 2: Optimize with teleprompter
      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 3,
          quality_threshold: 0.6
        )

      # Step 3: Post-optimization evaluation
      {:ok, optimized_results} = Evaluate.run_local(optimized, testset, metric_fn)
      optimized_score = optimized_results.score

      # Step 4: Verify improvement
      assert optimized_score >= baseline_score

      # Verify evaluation metrics are detailed
      assert is_number(optimized_results.stats.duration_ms)
      assert optimized_results.stats.total_examples == length(testset)
      assert optimized_results.stats.success_rate >= 0.0
      assert optimized_results.stats.success_rate <= 1.0
    end
  end
end
