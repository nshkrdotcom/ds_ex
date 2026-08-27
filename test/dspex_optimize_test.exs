defmodule DSPEx.OptimizeTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "question -> answer"
  end

  defmodule Teacher do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, inputs, _opts) do
      {:ok, %{answer: Map.get(inputs, :question) |> to_string() |> String.upcase()}}
    end
  end

  test "optimize defaults to bootstrap teleprompter" do
    student = DSPEx.Predict.new(Sig)
    teacher = %Teacher{signature: Sig}

    metric = DSPEx.Metrics.exact_match(:answer)

    examples = [
      DSPEx.Example.new(%{question: "hi", answer: "HI"}, [:question]),
      DSPEx.Example.new(%{question: "bye", answer: "BYE"}, [:question])
    ]

    {:ok, optimized} =
      DSPEx.optimize(student, examples,
        teacher: teacher,
        metric: metric,
        max_demos: 1,
        retry_delay_ms: 0
      )

    assert %DSPEx.OptimizedProgram{} = optimized
    assert length(DSPEx.OptimizedProgram.get_demos(optimized)) == 1
    assert optimized.metadata.teleprompter == :bootstrap_fewshot
  end

  test "optimize surfaces missing teacher or metric" do
    student = DSPEx.Predict.new(Sig)

    examples = [
      DSPEx.Example.new(%{question: "hi", answer: "HI"}, [:question])
    ]

    assert {:error, :teacher_required} =
             DSPEx.optimize(student, examples, metric: DSPEx.Metrics.exact_match(:answer))

    assert {:error, :metric_required} = DSPEx.optimize(student, examples, teacher: student)
  end
end
