defmodule DSPEx.Teleprompter.GEPA do
  @moduledoc """
  Teleprompter that delegates optimization to GEPA using the instruction text as the search space.
  """

  @behaviour DSPEx.Teleprompter

  alias DSPEx.Teleprompter.GEPAAdapter

  @impl DSPEx.Teleprompter
  def compile(student, _teacher, trainset, metric_fn, opts \\ []) do
    adapter = GEPAAdapter.new(student, metric_fn)

    seed_instruction =
      Keyword.get_lazy(opts, :seed_instruction, fn ->
        if function_exported?(student.signature, :instructions, 0) do
          student.signature.instructions()
        else
          "You are a helpful assistant."
        end
      end)

    seed_candidate = %{"instruction" => seed_instruction}
    valset = Keyword.get(opts, :valset, trainset)
    max_calls = Keyword.get(opts, :max_metric_calls, 50)
    effective_minibatch =
      opts
      |> Keyword.get(:reflection_minibatch_size, 1)
      |> max(1)

    skip_perfect_score =
      if effective_minibatch == 0 do
        false
      else
        Keyword.get(opts, :skip_perfect_score, true)
      end

    reflection_llm =
      case Keyword.get(opts, :reflection_llm) do
        nil ->
          GEPA.LLM.Mock.new()

        llm ->
          llm
      end

    gepa_opts = [
      seed_candidate: seed_candidate,
      trainset: trainset,
      valset: valset,
      adapter: adapter,
      max_metric_calls: max_calls,
      reflection_llm: reflection_llm,
      reflection_minibatch_size: effective_minibatch,
      skip_perfect_score: skip_perfect_score
    ]

    with {:ok, result} <- GEPA.optimize(gepa_opts) do
      candidate = GEPA.Result.best_candidate(result)
      instruction = Map.get(candidate, "instruction", seed_instruction)
      best_score = GEPA.Result.best_score(result)
      total_calls = Map.get(result, :total_num_evals, 0)

      reflection_source =
        cond do
          is_struct(reflection_llm) -> reflection_llm.__struct__
          is_atom(reflection_llm) -> reflection_llm
          true -> nil
        end

      optimized =
        DSPEx.OptimizedProgram.new(
          student,
          [],
          %{
            teleprompter: :gepa,
            score: best_score,
            best_score: best_score,
            max_metric_calls: max_calls,
            total_metric_calls: total_calls,
            reflection_llm: reflection_source,
            seed_instruction: seed_instruction,
            reflection_minibatch_size: effective_minibatch
          }
        )
        |> DSPEx.OptimizedProgram.update_instruction(instruction)

      {:ok, optimized}
    end
  end

end
