defmodule DSPEx.BootstrapTeacherFailTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "question -> answer"
  end

  defmodule FailingTeacher do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, _inputs, _opts), do: {:error, :oops}
  end

  test "teacher failure produces no demos" do
    student = DSPEx.Predict.new(Sig)
    teacher = %FailingTeacher{signature: Sig}

    examples = [
      DSPEx.Example.new(%{question: "hi", answer: "HI"}, [:question])
    ]

    metric = DSPEx.Metrics.exact_match(:answer)

    {:ok, optimized} =
      DSPEx.Teleprompter.BootstrapFewShot.compile(student, teacher, examples, metric,
        max_demos: 2,
        quality_threshold: 0.0
      )

    assert length(DSPEx.OptimizedProgram.get_demos(optimized)) == 0
  end
end
