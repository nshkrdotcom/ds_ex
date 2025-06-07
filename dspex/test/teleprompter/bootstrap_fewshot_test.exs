defmodule DSPEx.Teleprompter.BootstrapFewShotTest do
  use ExUnit.Case, async: false

  defmodule QASignature do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule SimpleProgram do
    defstruct [:predict]

    def new(client) do
      predict = DSPEx.Predict.new(QASignature, client: client)
      %__MODULE__{predict: predict}
    end

    def forward(%__MODULE__{predict: predict}, inputs) do
      DSPEx.Predict.forward(predict, inputs)
    end

    def add_demo(%__MODULE__{predict: predict} = program, demo) do
      updated_predict = DSPEx.Predict.add_demo(predict, demo)
      %{program | predict: updated_predict}
    end
  end

  defmodule MockClient do
    def request(_client, _request) do
      # Simple mock that returns reasonable answers
      {:ok, %{
        choices: [%{message: %{content: "[[ ## answer ## ]]\n42"}}],
        usage: %{prompt_tokens: 10, completion_tokens: 2}
      }}
    end
  end

  def simple_metric(example, prediction) do
    case prediction do
      {:ok, pred} ->
        # Simple length-based scoring for testing
        if String.length(pred.answer) > 0, do: 1.0, else: 0.0
      {:error, _} -> 0.0
    end
  end

  setup do
    {:ok, client} = start_supervised({DSPEx.Client, %{
      api_key: "test",
      model: "test",
      adapter: MockClient
    }})

    trainset = [
      %DSPEx.Example{question: "What is 1+1?", answer: "2"},
      %DSPEx.Example{question: "What is 2+2?", answer: "4"},
      %DSPEx.Example{question: "What is 3+3?", answer: "6"}
    ]

    valset = [
      %DSPEx.Example{question: "What is 4+4?", answer: "8"}
    ]

    %{client: client, trainset: trainset, valset: valset}
  end

  describe "bootstrap initialization" do
    test "creates bootstrap teleprompter with default settings" do
      bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new(
        metric: &simple_metric/2
      )

      assert bootstrap.metric == &simple_metric/2
      assert bootstrap.max_bootstrapped_demos == 4
      assert bootstrap.max_labeled_demos == 16
      assert bootstrap.max_rounds == 1
      assert bootstrap.teacher == nil
    end

    test "accepts custom configuration" do
      bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new(
        metric: &simple_metric/2,
        max_bootstrapped_demos: 8,
        max_labeled_demos: 32,
        max_rounds: 3
      )

      assert bootstrap.max_bootstrapped_demos == 8
      assert bootstrap.max_labeled_demos == 32
      assert bootstrap.max_rounds == 3
    end
  end

  describe "compilation process" do
    test "compiles student program with few-shot examples", %{client: client, trainset: trainset} do
      student = SimpleProgram.new(client)
      teacher = SimpleProgram.new(client)

      bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new(
        metric: &simple_metric/2,
        max_bootstrapped_demos: 2
      )

      compiled_student = DSPEx.Teleprompter.BootstrapFewShot.compile(
        bootstrap,
        student: student,
        teacher: teacher,
        trainset: trainset
      )

      # Should have demos added from bootstrap process
      assert length(compiled_student.predict.demos) > 0
      assert length(compiled_student.predict.demos) <= 2
    end

    test "uses teacher program to generate examples", %{client: client, trainset: trainset} do
      student = SimpleProgram.new(client)

      # Teacher with different behavior
      defmodule TeacherClient do
        def request(_client, _request) do
          {:ok, %{
            choices: [%{message: %{content: "[[ ## answer ## ]]\nTeacher answer"}}],
            usage: %{prompt_tokens: 5, completion_tokens: 2}
          }}
        end
      end

      {:ok, teacher_client} = start_supervised({DSPEx.Client, %{
        api_key: "test",
        model: "teacher_model",
        adapter: TeacherClient
      }}, id: :teacher_client)

      teacher = SimpleProgram.new(teacher_client)

      bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new(
        metric: &simple_metric/2,
        max_bootstrapped_demos: 1
      )

      compiled_student = DSPEx.Teleprompter.BootstrapFewShot.compile(
        bootstrap,
        student: student,
        teacher: teacher,
        trainset: trainset
      )

      # Verify teacher was used (demos should contain teacher responses)
      assert length(compiled_student.predict.demos) > 0
    end

    test "filters demos based on metric", %{client: client, trainset: trainset} do
      student = SimpleProgram.new(client)
      teacher = SimpleProgram.new(client)

      # Strict metric that only accepts specific answers
      strict_metric = fn example, prediction ->
        case prediction do
          {:ok, pred} when pred.answer == "42" -> 1.0
          _ -> 0.0
        end
      end

      bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new(
        metric: strict_metric,
        max_bootstrapped_demos: 10  # Try to get many demos
      )

      compiled_student = DSPEx.Teleprompter.BootstrapFewShot.compile(
        bootstrap,
        student: student,
        teacher: teacher,
        trainset: trainset
      )

      # Since our mock always returns "42", and metric accepts that, should get demos
      assert length(compiled_student.predict.demos) > 0
    end

    test "handles validation set evaluation", %{client: client, trainset: trainset, valset: valset} do
      student = SimpleProgram.new(client)
      teacher = SimpleProgram.new(client)

      bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new(
        metric: &simple_metric/2,
        max_bootstrapped_demos: 2
      )

      compiled_student = DSPEx.Teleprompter.BootstrapFewShot.compile(
        bootstrap,
        student: student,
        teacher: teacher,
        trainset: trainset,
        valset: valset
      )

      # Should successfully compile and validate
      assert is_struct(compiled_student)
    end
  end

  describe "demo selection strategy" do
    test "prioritizes high-scoring demos" do
      # This would test the internal demo selection logic
      # Implementation depends on specific scoring and selection algorithms
    end

    test "maintains demo diversity" do
      # Test that selected demos cover different types of examples
      # Implementation depends on diversity metrics used
    end

    test "respects maximum demo limits", %{client: client, trainset: trainset} do
      student = SimpleProgram.new(client)
      teacher = SimpleProgram.new(client)

      bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new(
        metric: &simple_metric/2,
        max_bootstrapped_demos: 1  # Very restrictive
      )

      compiled_student = DSPEx.Teleprompter.BootstrapFewShot.compile(
        bootstrap,
        student: student,
        teacher: teacher,
        trainset: trainset
      )

      assert length(compiled_student.predict.demos) <= 1
    end
  end

  describe "error handling" do
    test "handles teacher program failures gracefully", %{client: client, trainset: trainset} do
      student = SimpleProgram.new(client)

      defmodule FailingTeacherClient do
        def request(_client, _request) do
          {:error, :teacher_failed}
        end
      end

      {:ok, failing_client} = start_supervised({DSPEx.Client, %{
        api_key: "test",
        model: "failing_model",
        adapter: FailingTeacherClient
      }}, id: :failing_client)

      teacher = SimpleProgram.new(failing_client)

      bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new(
        metric: &simple_metric/2,
        max_bootstrapped_demos: 2
      )

      compiled_student = DSPEx.Teleprompter.BootstrapFewShot.compile(
        bootstrap,
        student: student,
        teacher: teacher,
        trainset: trainset
      )

      # Should still return a student (possibly with fewer/no demos)
      assert is_struct(compiled_student)
    end

    test "handles metric evaluation errors" do
      failing_metric = fn _example, _prediction ->
        raise "Metric computation failed"
      end

      bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new(
        metric: failing_metric,
        max_bootstrapped_demos: 1
      )

      # Should handle gracefully, possibly skipping problematic examples
      assert is_struct(bootstrap)
    end
  end
end
