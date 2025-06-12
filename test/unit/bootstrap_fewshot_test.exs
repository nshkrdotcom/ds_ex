defmodule DSPEx.Teleprompter.BootstrapFewShotTest do
  use ExUnit.Case, async: true

  @moduletag :group_1

  alias DSPEx.{Example, Teleprompter}
  alias DSPEx.Teleprompter.BootstrapFewShot

  # Mock programs for testing
  defmodule MockTeacherProgram do
    use DSPEx.Program

    defstruct [:name]

    @impl true
    def forward(_program, %{question: question}, _opts) do
      # Simple mock: answer based on question content
      answer =
        cond do
          String.contains?(question, "2+2") -> "4"
          String.contains?(question, "3+3") -> "6"
          String.contains?(question, "capital") -> "Paris"
          true -> "I don't know"
        end

      {:ok, %{answer: answer}}
    end
  end

  defmodule MockStudentProgram do
    use DSPEx.Program

    defstruct [:demos]

    @impl true
    def forward(%__MODULE__{demos: demos}, _inputs, _opts) do
      # Simple mock that just returns first demo answer if available
      case demos do
        [demo | _] -> {:ok, Example.outputs(demo)}
        [] -> {:ok, %{answer: "no demo available"}}
      end
    end
  end

  defmodule FailingTeacherProgram do
    use DSPEx.Program

    defstruct [:name]

    @impl true
    def forward(_program, _inputs, _opts) do
      {:error, :teacher_failed}
    end
  end

  setup do
    teacher = %MockTeacherProgram{}
    student = %MockStudentProgram{demos: []}

    trainset = [
      Example.new(%{question: "What is 2+2?", answer: "4", __id: 1})
      |> Example.with_inputs([:question]),
      Example.new(%{question: "What is 3+3?", answer: "6", __id: 2})
      |> Example.with_inputs([:question]),
      Example.new(%{question: "What is the capital of France?", answer: "Paris", __id: 3})
      |> Example.with_inputs([:question])
    ]

    metric_fn = Teleprompter.exact_match(:answer)

    %{
      teacher: teacher,
      student: student,
      trainset: trainset,
      metric_fn: metric_fn
    }
  end

  describe "new/1" do
    test "creates teleprompter with default options" do
      teleprompter = BootstrapFewShot.new()

      assert teleprompter.max_bootstrapped_demos == 4
      assert teleprompter.max_labeled_demos == 16
      assert teleprompter.quality_threshold == 0.7
      assert teleprompter.max_concurrency == 20
    end

    test "creates teleprompter with custom options" do
      teleprompter =
        BootstrapFewShot.new(
          max_bootstrapped_demos: 8,
          quality_threshold: 0.9,
          max_concurrency: 10
        )

      assert teleprompter.max_bootstrapped_demos == 8
      assert teleprompter.quality_threshold == 0.9
      assert teleprompter.max_concurrency == 10
    end
  end

  describe "compile/5 with struct" do
    test "successfully optimizes student program", %{
      teacher: teacher,
      student: student,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      teleprompter = BootstrapFewShot.new(max_bootstrapped_demos: 2)

      {:ok, optimized} =
        BootstrapFewShot.compile(teleprompter, student, teacher, trainset, metric_fn, [])

      # Should have wrapped student in OptimizedProgram with demos
      assert %DSPEx.OptimizedProgram{program: %MockStudentProgram{}, demos: demos} = optimized
      assert is_list(demos)
      assert length(demos) <= 2

      # Each demo should have the required structure
      for demo <- demos do
        assert %Example{} = demo
        assert Map.has_key?(demo.data, :__generated_by)
        assert Map.has_key?(demo.data, :__quality_score)
      end
    end
  end

  describe "compile/5 with options" do
    test "successfully optimizes student program", %{
      teacher: teacher,
      student: student,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 2,
          quality_threshold: 0.5
        )

      # Should have wrapped student in OptimizedProgram with demos
      assert %DSPEx.OptimizedProgram{program: %MockStudentProgram{}, demos: demos} = optimized
      assert is_list(demos)
      assert length(demos) <= 2
    end

    test "handles progress callback", %{
      teacher: teacher,
      student: student,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      progress_callback = fn progress ->
        send(self(), {:progress, progress})
        :ok
      end

      {:ok, _optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 1,
          progress_callback: progress_callback
        )

      # Should have received progress updates (any phase is fine)
      assert_received {:progress, %{phase: _phase}}
    end

    test "returns error for invalid inputs" do
      {:error, :invalid_student_program} =
        BootstrapFewShot.compile(
          "invalid",
          %MockTeacherProgram{},
          [],
          fn _, _ -> 1.0 end
        )

      {:error, :invalid_teacher_program} =
        BootstrapFewShot.compile(
          %MockStudentProgram{demos: []},
          "invalid",
          [],
          fn _, _ -> 1.0 end
        )

      {:error, :invalid_or_empty_trainset} =
        BootstrapFewShot.compile(
          %MockStudentProgram{demos: []},
          %MockTeacherProgram{},
          [],
          fn _, _ -> 1.0 end
        )

      {:error, :invalid_metric_function} =
        BootstrapFewShot.compile(
          %MockStudentProgram{demos: []},
          %MockTeacherProgram{},
          [Example.new(%{})],
          "invalid"
        )
    end

    test "handles teacher failures gracefully", %{
      student: student,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      failing_teacher = %FailingTeacherProgram{}

      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          failing_teacher,
          trainset,
          metric_fn,
          teacher_retries: 1
        )

      # Should succeed but with no demos since teacher always fails
      assert %DSPEx.OptimizedProgram{program: %MockStudentProgram{}, demos: []} = optimized
    end

    test "filters out low quality demonstrations", %{
      teacher: teacher,
      student: student,
      trainset: trainset
    } do
      # Use a metric that always returns low scores
      low_quality_metric = fn _example, _prediction -> 0.1 end

      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          low_quality_metric,
          # Higher than what metric returns
          quality_threshold: 0.8
        )

      # Should have no demos due to quality threshold
      assert %DSPEx.OptimizedProgram{program: %MockStudentProgram{}, demos: []} = optimized
    end

    test "limits number of demonstrations", %{
      teacher: teacher,
      student: student,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          # Limit to 1 demo
          max_bootstrapped_demos: 1
        )

      assert %DSPEx.OptimizedProgram{program: %MockStudentProgram{}, demos: demos} = optimized
      assert length(demos) <= 1
    end
  end

  describe "program without native demo support" do
    defmodule NonDemoProgram do
      use DSPEx.Program

      defstruct [:name]

      @impl true
      def forward(%__MODULE__{}, _inputs, _opts) do
        {:ok, %{answer: "generic answer"}}
      end
    end

    test "wraps program without demo support", %{
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      non_demo_student = %NonDemoProgram{name: "test"}

      {:ok, optimized} =
        BootstrapFewShot.compile(
          non_demo_student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 1
        )

      # Should be wrapped or have demos added
      assert Map.has_key?(optimized, :demos)
    end
  end

  describe "edge cases" do
    test "handles empty demonstration results", %{student: student, trainset: trainset} do
      # Teacher that produces outputs that don't match any metric
      always_wrong_teacher = %MockTeacherProgram{}
      never_match_metric = fn _example, _prediction -> 0.0 end

      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          always_wrong_teacher,
          trainset,
          never_match_metric,
          quality_threshold: 0.5
        )

      # Should still succeed but with no demos
      assert %DSPEx.OptimizedProgram{program: %MockStudentProgram{}, demos: []} = optimized
    end

    test "handles concurrent processing limits", %{
      teacher: teacher,
      student: student,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          # Very limited concurrency
          max_concurrency: 1,
          max_bootstrapped_demos: 1
        )

      # Should still work with limited concurrency
      assert %DSPEx.OptimizedProgram{program: %MockStudentProgram{}, demos: demos} = optimized
      assert is_list(demos)
    end
  end
end
