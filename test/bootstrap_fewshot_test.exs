defmodule DSPEx.BootstrapFewShotTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "question -> answer"
  end

  defmodule Teacher do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(%__MODULE__{}, inputs, _opts) do
      {:ok, %{answer: Map.get(inputs, :question) |> to_string() |> String.upcase()}}
    end
  end

  defmodule FlakyTeacher do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, inputs, _opts) do
      attempt = Process.get(:flaky_attempt, 0) + 1
      Process.put(:flaky_attempt, attempt)

      if attempt < 2 do
        {:error, :transient}
      else
        {:ok, %{answer: Map.get(inputs, :question)}}
      end
    end
  end

  defmodule WrongTeacher do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, _inputs, _opts) do
      {:ok, %{answer: "nope"}}
    end
  end

  defmodule MixedTeacher do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, inputs, _opts) do
      case Map.get(inputs, :question) do
        "fail" -> {:error, :bad_teacher}
        other -> {:ok, %{answer: to_string(other)}}
      end
    end
  end

  test "compiles optimized program with demos" do
    student = DSPEx.Predict.new(Sig)
    teacher = %Teacher{signature: Sig}

    examples = [
      DSPEx.Example.new(%{question: "hi", answer: "HI"}, [:question]),
      DSPEx.Example.new(%{question: "bye", answer: "BYE"}, [:question])
    ]

    metric = fn example, outputs ->
      expected = DSPEx.Example.get(example, :answer)
      actual = Map.get(outputs, :answer)
      if expected == actual, do: 1.0, else: 0.0
    end

    {:ok, optimized} =
      DSPEx.Teleprompter.BootstrapFewShot.compile(student, teacher, examples, metric,
        max_demos: 2,
        quality_threshold: 0.5
      )

    assert %DSPEx.OptimizedProgram{} = optimized
    assert length(DSPEx.OptimizedProgram.get_demos(optimized)) == 2
  end

  test "returns empty demos when none meet threshold" do
    student = DSPEx.Predict.new(Sig)
    teacher = %Teacher{signature: Sig}

    examples = [
      DSPEx.Example.new(%{question: "hi", answer: "NOPE"}, [:question])
    ]

    metric = DSPEx.Metrics.exact_match(:answer)

    {:ok, optimized} =
      DSPEx.Teleprompter.BootstrapFewShot.compile(student, teacher, examples, metric,
        quality_threshold: 1.0
      )

    assert length(DSPEx.OptimizedProgram.get_demos(optimized)) == 0
  end

  test "respects max_demos" do
    student = DSPEx.Predict.new(Sig)
    teacher = %Teacher{signature: Sig}

    examples =
      Enum.map(1..5, fn i ->
        DSPEx.Example.new(%{question: "#{i}", answer: "#{String.upcase("#{i}")}"}, [:question])
      end)

    metric = DSPEx.Metrics.exact_match(:answer)

    {:ok, optimized} =
      DSPEx.Teleprompter.BootstrapFewShot.compile(student, teacher, examples, metric,
        max_demos: 2,
        quality_threshold: 0.0
      )

    assert length(DSPEx.OptimizedProgram.get_demos(optimized)) == 2
  end

  test "retries teacher failures up to max_attempts and records attempts" do
    Process.put(:flaky_attempt, 0)

    student = DSPEx.Predict.new(Sig)
    teacher = %FlakyTeacher{signature: Sig}

    examples = [
      DSPEx.Example.new(%{question: "hi", answer: "hi"}, [:question])
    ]

    metric = DSPEx.Metrics.exact_match(:answer)

    {:ok, optimized} =
      DSPEx.Teleprompter.BootstrapFewShot.compile(student, teacher, examples, metric,
        max_attempts: 3,
        retry_delay_ms: 0
      )

    assert Process.get(:flaky_attempt) == 2

    meta = DSPEx.OptimizedProgram.get_metadata(optimized)
    assert meta.total_attempts == 2
  end

  test "records skip metadata when below threshold" do
    student = DSPEx.Predict.new(Sig)
    teacher = %WrongTeacher{signature: Sig}

    examples = [
      DSPEx.Example.new(%{question: "hi", answer: "HI"}, [:question])
    ]

    metric = DSPEx.Metrics.exact_match(:answer)

    {:ok, optimized} =
      DSPEx.Teleprompter.BootstrapFewShot.compile(student, teacher, examples, metric,
        max_attempts: 2,
        quality_threshold: 1.0
      )

    meta = DSPEx.OptimizedProgram.get_metadata(optimized)
    [skip | _] = meta.skipped
    assert skip.reason == :below_threshold
    assert skip.attempts >= 1
  end

  test "records metric and teacher skip reasons and truncates demos" do
    student = DSPEx.Predict.new(Sig)
    teacher = %MixedTeacher{signature: Sig}

    examples = [
      DSPEx.Example.new(%{question: "fail", answer: "FAIL"}, [:question]),
      DSPEx.Example.new(%{question: "raise", answer: "RAISE"}, [:question]),
      DSPEx.Example.new(%{question: "ok", answer: "ok"}, [:question])
    ]

    metric = fn example, outputs ->
      case DSPEx.Example.get(example, :answer) do
        "RAISE" -> raise "metric boom"
        expected -> if expected == Map.get(outputs, :answer), do: 1.0, else: 0.0
      end
    end

    {:ok, optimized} =
      DSPEx.Teleprompter.BootstrapFewShot.compile(student, teacher, examples, metric,
        max_demos: 1,
        quality_threshold: 0.0,
        retry_delay_ms: 0
      )

    meta = DSPEx.OptimizedProgram.get_metadata(optimized)

    assert Enum.any?(meta.skipped, &match?(%{reason: {:teacher_error, :bad_teacher}}, &1))
    assert Enum.any?(meta.skipped, &match?(%{reason: {:metric_error, %RuntimeError{}}}, &1))

    assert length(DSPEx.OptimizedProgram.get_demos(optimized)) == 1
    assert meta.demo_count == 1
  end

  test "metadata includes demo_count and retry settings after truncation" do
    student = DSPEx.Predict.new(Sig)
    teacher = %Teacher{signature: Sig}

    examples = [
      DSPEx.Example.new(%{question: "a", answer: "A"}, [:question]),
      DSPEx.Example.new(%{question: "b", answer: "B"}, [:question])
    ]

    metric = DSPEx.Metrics.exact_match(:answer)

    {:ok, optimized} =
      DSPEx.Teleprompter.BootstrapFewShot.compile(student, teacher, examples, metric,
        max_demos: 1,
        max_attempts: 2,
        retry_delay_ms: 0
      )

    meta = DSPEx.OptimizedProgram.get_metadata(optimized)

    assert meta.demo_count == 1
    assert meta.max_attempts == 2
    assert meta.retry_delay_ms == 0
    assert meta.quality_threshold == 0.0
  end

  test "retry delay can be small without hanging" do
    Process.put(:flaky_attempt, 0)

    student = DSPEx.Predict.new(Sig)
    teacher = %FlakyTeacher{signature: Sig}

    examples = [
      DSPEx.Example.new(%{question: "hi", answer: "hi"}, [:question])
    ]

    metric = DSPEx.Metrics.exact_match(:answer)

    start = System.monotonic_time(:millisecond)

    {:ok, _optimized} =
      DSPEx.Teleprompter.BootstrapFewShot.compile(student, teacher, examples, metric,
        max_attempts: 2,
        retry_delay_ms: 1
      )

    duration = System.monotonic_time(:millisecond) - start
    assert duration < 200
  end
end
