defmodule DSPEx.Teleprompter.GEPAMock do
  @moduledoc false

  @behaviour GEPA.Adapter

  defstruct []

  @impl GEPA.Adapter
  def evaluate(_batch, _candidate, _capture_traces) do
    {:ok,
     %GEPA.EvaluationBatch{
       outputs: [%{}],
       scores: [1.0],
       trajectories: nil
     }}
  end

  @impl GEPA.Adapter
  def make_reflective_dataset(_candidate, _eval_batch, components_to_update) do
    dataset =
      components_to_update
      |> Enum.map(fn c -> {c, []} end)
      |> Enum.into(%{})

    {:ok, dataset}
  end

  @impl GEPA.Adapter
  def propose_new_texts(_candidate, _dataset, components_to_update) do
    {:ok, Map.new(components_to_update, &{&1, ""})}
  end
end
