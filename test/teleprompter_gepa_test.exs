defmodule DSPEx.TeleprompterGEPATest do
  use ExUnit.Case

  defmodule SimpleSig do
    @moduledoc false
    use DSPEx.Signature, "question -> answer"
  end

  defmodule InstructionSig do
    @moduledoc false
    use DSPEx.Signature, "question -> answer"
  end

  defmodule InstructionProgram do
    use DSPEx.Program
    defstruct [:signature, :instruction]

    @impl DSPEx.Program
    def forward(%__MODULE__{} = prog, _inputs, opts) do
      answer = Keyword.get(opts, :instruction, prog.instruction || "unset")
      {:ok, %{answer: answer}}
    end
  end

  defmodule CaptureInstructionProgram do
    use DSPEx.Program
    defstruct [:signature, :instruction]

    @impl DSPEx.Program
    def forward(%__MODULE__{} = prog, _inputs, opts) do
      {:ok, %{answer: Keyword.get(opts, :instruction, prog.instruction)}}
    end
  end

  defmodule CountingLLM do
    defstruct []

    def new, do: %__MODULE__{}

    def complete(%__MODULE__{} = _llm, prompt, _opts \\ []) do
      send(self(), {:llm_prompt, prompt})
      {:ok, "custom-" <> Integer.to_string(String.length(prompt))}
    end
  end

  test "GEPA teleprompter returns an optimized program" do
    program = DSPEx.Predict.new(SimpleSig)

    examples = [
      DSPEx.Example.new(%{question: "2+2?", answer: "4"}, [:question])
    ]

    metric = fn example, outputs ->
      expected = DSPEx.Example.get(example, :answer)
      actual = Map.get(outputs, :answer)
      if expected == actual, do: 1.0, else: 0.0
    end

    {:ok, optimized} =
      DSPEx.Teleprompter.GEPA.compile(program, nil, examples, metric,
        max_metric_calls: 5,
        reflection_llm: GEPA.LLM.Mock.new()
      )

    assert %DSPEx.OptimizedProgram{} = optimized
    assert DSPEx.OptimizedProgram.get_instruction(optimized)
  end

  test "GEPA honors reflection llm and best score in metadata" do
    student = %InstructionProgram{signature: InstructionSig}
    teacher = %InstructionProgram{signature: InstructionSig}

    examples = [
      DSPEx.Example.new(%{question: "q", answer: "better"}, [:question])
    ]

    metric = fn example, outputs ->
      expected = DSPEx.Example.get(example, :answer)
      actual = Map.get(outputs, :answer)
      if expected == actual, do: 1.0, else: 0.0
    end

    llm = GEPA.LLM.Mock.new(responses: ["better"])

    {:ok, optimized} =
      DSPEx.Teleprompter.GEPA.compile(student, teacher, examples, metric,
        seed_instruction: "seed",
        reflection_llm: llm,
        max_metric_calls: 2
      )

    assert DSPEx.OptimizedProgram.get_instruction(optimized) == "better"

    meta = DSPEx.OptimizedProgram.get_metadata(optimized)
    assert meta.teleprompter == :gepa
    assert meta.score >= 1.0
  end

  test "GEPA respects max_metric_calls and uses provided reflection llm" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    student = %InstructionProgram{signature: InstructionSig}
    teacher = %InstructionProgram{signature: InstructionSig}

    examples = [
      DSPEx.Example.new(%{question: "q", answer: "ok"}, [:question])
    ]

    metric = fn example, outputs ->
      Agent.update(counter, &(&1 + 1))
      expected = DSPEx.Example.get(example, :answer)
      actual = Map.get(outputs, :answer)
      if expected == actual, do: 1.0, else: 0.0
    end

    reflection_llm = CountingLLM.new()

    {:ok, optimized} =
      DSPEx.Teleprompter.GEPA.compile(student, teacher, examples, metric,
        seed_instruction: "seed",
        reflection_llm: reflection_llm,
        max_metric_calls: 2
      )

    assert_received {:llm_prompt, _prompt}

    meta = DSPEx.OptimizedProgram.get_metadata(optimized)
    calls = Agent.get(counter, & &1)

    assert meta.teleprompter == :gepa
    assert meta.max_metric_calls == 2
    assert meta.total_metric_calls <= meta.max_metric_calls + 1
    assert meta.best_score >= 0.0
    assert calls <= meta.total_metric_calls
  end

  test "optimized program forwards instruction override" do
    student = %CaptureInstructionProgram{signature: InstructionSig, instruction: "seed"}
    teacher = %CaptureInstructionProgram{signature: InstructionSig, instruction: "seed"}

    examples = [
      DSPEx.Example.new(%{question: "q", answer: "override"}, [:question])
    ]

    metric = fn example, outputs ->
      expected = DSPEx.Example.get(example, :answer)
      actual = Map.get(outputs, :answer)
      if expected == actual, do: 1.0, else: 0.0
    end

    {:ok, optimized} =
      DSPEx.Teleprompter.GEPA.compile(student, teacher, examples, metric,
        seed_instruction: "seed",
        reflection_llm: GEPA.LLM.Mock.new(responses: ["override"]),
        max_metric_calls: 3
      )

    {:ok, outputs} = DSPEx.Program.forward(optimized, %{question: "q"})
    assert outputs.answer == "override"
    assert DSPEx.OptimizedProgram.get_instruction(optimized) == "override"
  end
end
