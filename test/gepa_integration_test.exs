defmodule DSPEx.GEPAIntegrationTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "question -> answer"
  end

  defmodule Student do
    use DSPEx.Program
    defstruct [:signature, :instruction]

    @impl DSPEx.Program
    def forward(%__MODULE__{} = prog, inputs, opts) do
      instruction = prog.instruction || Keyword.get(opts, :instruction, "")
      answer = "#{Map.get(inputs, :question)}|#{instruction}"
      {:ok, %{answer: answer}}
    end
  end

  test "gepa teleprompter compiles optimized program via gepa_ex" do
    student = %Student{signature: Sig, instruction: "seed"}

    examples = [
      DSPEx.Example.new(%{question: "hi", answer: "hi|seed"}, [:question]),
      DSPEx.Example.new(%{question: "bye", answer: "bye|seed"}, [:question])
    ]

    metric = DSPEx.Metrics.exact_match(:answer)

    {:ok, optimized} =
      DSPEx.Teleprompter.GEPA.compile(student, student, examples, metric,
        max_metric_calls: 2,
        seed_instruction: "seed",
        reflection_llm: GEPA.LLM.Mock.new()
      )

    assert %DSPEx.OptimizedProgram{} = optimized
    meta = DSPEx.OptimizedProgram.get_metadata(optimized)
    assert meta.teleprompter == :gepa
    assert DSPEx.OptimizedProgram.get_instruction(optimized) |> is_binary()
  end
end
