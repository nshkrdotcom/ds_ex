defmodule DSPEx.Evaluate do
  @moduledoc """
  Minimal concurrent evaluator: runs a program over examples with a metric function.
  """

  @type evaluation_result :: %{
          score: float(),
          stats: %{
            total: non_neg_integer(),
            successes: non_neg_integer(),
            failures: non_neg_integer(),
            errors: non_neg_integer()
          }
        }

  @spec run(DSPEx.Program.t(), [DSPEx.Example.t() | map()], (term(), map() -> number()), keyword()) ::
          {:ok, evaluation_result()} | {:error, term()}
  def run(program, examples, metric_fn, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 20)
    timeout = Keyword.get(opts, :timeout, 30_000)
    return_scores? = Keyword.get(opts, :return_scores, false)
    scores_only? = Keyword.get(opts, :scores_only, false)
    return_failures? = Keyword.get(opts, :return_failures, false)

    results =
      examples
      |> Task.async_stream(fn example -> eval_one(program, example, metric_fn) end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    combined = Enum.zip(examples, results)

    scores =
      for {_example, {:ok, {:ok, score}}} <- combined, is_number(score) do
        score
      end

    failure_details =
      [
        for {example, {:ok, {:ok, score}}} <- combined, not is_number(score) do
          %{example: example, reason: :invalid_score}
        end,
        for {example, {:ok, {:error, reason}}} <- combined do
          %{example: example, reason: reason}
        end,
        for {example, {:exit, reason}} <- combined do
          %{example: example, reason: {:exit, reason}}
        end
      ]
      |> List.flatten()

    total = length(results)
    successes = length(scores)
    failures = length(failure_details)
    avg = if successes > 0, do: Enum.sum(scores) / successes, else: 0.0

    base = %{
      score: avg,
      stats: %{total: total, successes: successes, failures: failures, errors: failures}
    }

    base_with_failures =
      if return_failures? do
        Map.put(base, :failures, failure_details)
      else
        base
      end

    cond do
      scores_only? -> {:ok, %{scores: scores}}
      return_scores? -> {:ok, Map.put(base_with_failures, :scores, scores)}
      true -> {:ok, base_with_failures}
    end
  end

  defp eval_one(program, example, metric_fn) do
    inputs =
      case example do
        %DSPEx.Example{} = ex -> DSPEx.Example.inputs(ex)
        %{inputs: map} when is_map(map) -> map
        map when is_map(map) -> map
        _ -> %{}
      end

    case DSPEx.Program.forward(program, inputs) do
      {:ok, outputs} ->
        score = metric_fn.(example, outputs)
        {:ok, score}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, error}
  end
end
