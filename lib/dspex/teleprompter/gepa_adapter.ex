defmodule DSPEx.Teleprompter.GEPAAdapter do
  @moduledoc """
  GEPA adapter that evaluates DSPEx programs by treating candidate text as an instruction.
  """

  @behaviour GEPA.Adapter

  defstruct [:program, :metric_fn]

  @type t :: %__MODULE__{program: struct(), metric_fn: (term(), map() -> number())}

  @spec new(struct(), (term(), map() -> number())) :: t()
  def new(program, metric_fn), do: %__MODULE__{program: program, metric_fn: metric_fn}

  def evaluate(%__MODULE__{} = adapter, batch, candidate, capture_traces) do
    instruction = Map.get(candidate, "instruction", "")
    metric_fn = adapter.metric_fn || fn _example, _outputs -> 0.0 end
    program = adapter.program

    results =
      Enum.map(batch, fn example ->
        inputs = extract_inputs(example)

        case DSPEx.Program.forward(program_with_instruction(program, instruction), inputs,
               instruction: instruction
             ) do
          {:ok, outputs} ->
            score = safe_score(metric_fn, example, outputs)
            traj = if capture_traces, do: %{inputs: inputs, outputs: outputs, score: score}, else: nil
            {outputs, score, traj}

          {:error, reason} ->
            traj = if capture_traces, do: %{inputs: inputs, error: reason, score: 0.0}, else: nil
            {%{}, 0.0, traj}
        end
      end)

    {outputs, scores, trajectories} =
      results
      |> Enum.reduce({[], [], []}, fn {out, score, traj}, {outs, scrs, trjs} ->
        {[out | outs], [score | scrs], [traj | trjs]}
      end)

    batch_struct = %GEPA.EvaluationBatch{
      outputs: Enum.reverse(outputs),
      scores: Enum.reverse(scores),
      trajectories: if(capture_traces, do: Enum.reverse(trajectories), else: nil)
    }

    {:ok, batch_struct}
  end

  # Behaviour arity (not used by GEPA engine but satisfies @behaviour)
  @impl GEPA.Adapter
  def evaluate(_batch, _candidate, _capture_traces) do
    {:error, :adapter_required}
  end

  @impl GEPA.Adapter
  def make_reflective_dataset(_candidate, eval_batch, components_to_update) do
    dataset =
      components_to_update
      |> Enum.map(fn component ->
        {component,
         Enum.zip(eval_batch.outputs, eval_batch.scores)
         |> Enum.map(fn {output, score} ->
           %{
              "Inputs" => %{},
             "Generated Outputs" => stringify(output),
             "Feedback" =>
               "Score: #{score}. Improve instruction #{component} to increase exact match."
           }
         end)}
      end)
      |> Enum.into(%{})

    {:ok, dataset}
  end

  # GEPA engine calls arity 4 (adapter first)
  def make_reflective_dataset(_adapter, candidate, eval_batch, components_to_update) do
    make_reflective_dataset(candidate, eval_batch, components_to_update)
  end

  defp extract_inputs(%DSPEx.Example{} = example), do: DSPEx.Example.inputs(example)
  defp extract_inputs(%{inputs: inputs}) when is_map(inputs), do: inputs
  defp extract_inputs(map) when is_map(map), do: map
  defp extract_inputs(_), do: %{}

  defp program_with_instruction(program, instruction) do
    if Map.has_key?(program, :instruction) do
      %{program | instruction: instruction}
    else
      Map.put(program, :instruction, instruction)
    end
  end

  defp safe_score(metric_fn, example, outputs) do
    try do
      metric_fn.(example, outputs)
    rescue
      _ -> 0.0
    end
  end

  defp stringify(map) when is_map(map), do: Jason.encode!(map)
  defp stringify(other), do: to_string(other)
end
