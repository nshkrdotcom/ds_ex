defmodule DSPEx.Teleprompter.BootstrapFewShot do
  @moduledoc """
  Minimal Bootstrap Few-Shot teleprompter.
  """

  @behaviour DSPEx.Teleprompter

  alias DSPEx.{Example, OptimizedProgram, Program}

  @impl DSPEx.Teleprompter
  def compile(student, teacher, trainset, metric_fn, opts \\ []) do
    quality_threshold = Keyword.get(opts, :quality_threshold, 0.0)
    max_demos = Keyword.get(opts, :max_demos, 4)
    max_attempts = Keyword.get(opts, :max_attempts, 1)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, 0)

    with {:ok, {demos, stats}} <-
           generate_demos(teacher, trainset, metric_fn, quality_threshold, %{
             max_attempts: max_attempts,
             retry_delay_ms: retry_delay_ms
           }),
         selected <- Enum.take(demos, max_demos) do
      metadata =
        %{
          teleprompter: :bootstrap_fewshot,
          quality_threshold: quality_threshold,
          max_demos: max_demos,
          max_attempts: max_attempts,
          retry_delay_ms: retry_delay_ms
        }
        |> Map.merge(stats)

      {:ok, OptimizedProgram.new(student, selected, metadata)}
    end
  end

  defp generate_demos(teacher, trainset, metric_fn, threshold, retry_opts) do
    max_attempts = Map.get(retry_opts, :max_attempts, 1)
    retry_delay_ms = Map.get(retry_opts, :retry_delay_ms, 0)

    results =
      trainset
      |> Enum.with_index()
      |> Enum.map(fn {example, idx} ->
        inputs = Example.inputs(example)

        case call_teacher_with_retry(teacher, inputs, max_attempts, retry_delay_ms) do
          {:ok, outputs, attempts} ->
            case safe_metric(metric_fn, example, outputs) do
              {:ok, score} when score >= threshold ->
                demo_data = Map.merge(inputs, outputs)
                {:demo, Example.new(demo_data, MapSet.to_list(example.input_keys)), attempts}

              {:ok, score} ->
                {:skip, %{index: idx, reason: :below_threshold, score: score, attempts: attempts}}

              {:error, reason} ->
                {:skip, %{index: idx, reason: {:metric_error, reason}, attempts: attempts}}
            end

          {:error, reason, attempts} ->
            {:skip, %{index: idx, reason: {:teacher_error, reason}, attempts: attempts}}
        end
      end)

    demos =
      results
      |> Enum.filter(fn result -> match?({:demo, _, _}, result) end)
      |> Enum.map(fn {:demo, demo, _attempts} -> demo end)

    skipped =
      results
      |> Enum.filter(fn result -> match?({:skip, _}, result) end)
      |> Enum.map(fn {:skip, meta} -> meta end)

    total_attempts =
      results
      |> Enum.reduce(0, fn
        {:demo, _demo, attempts}, acc -> acc + attempts
        {:skip, %{attempts: attempts}}, acc -> acc + attempts
      end)

    {:ok, {demos, %{skipped: skipped, total_attempts: total_attempts}}}
  end

  defp call_teacher_with_retry(teacher, inputs, max_attempts, retry_delay_ms) do
    1..max_attempts
    |> Enum.reduce_while({:error, :no_attempt, 0}, fn attempt, _acc ->
      case Program.forward(teacher, inputs) do
        {:ok, outputs} ->
          {:halt, {:ok, outputs, attempt}}

        {:error, reason} ->
          if attempt >= max_attempts do
            {:halt, {:error, reason, attempt}}
          else
            if retry_delay_ms > 0, do: Process.sleep(retry_delay_ms)
            {:cont, {:error, reason, attempt}}
          end
      end
    end)
  end

  defp safe_metric(metric_fn, example, outputs) do
    {:ok, metric_fn.(example, outputs)}
  rescue
    error -> {:error, error}
  end
end
