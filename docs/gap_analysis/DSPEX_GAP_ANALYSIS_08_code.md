# Part III: Missing Infrastructure Components

## 8. **NEW: Convergence Detection**

```elixir
defmodule DSPEx.Teleprompter.SIMBA.Convergence do
  @moduledoc """
  Convergence detection for SIMBA optimization.
  
  Implements multiple convergence criteria:
  - Score plateau detection
  - Performance variance analysis  
  - Improvement rate analysis
  """
  
  @type convergence_state :: %{
    best_scores: [float()],
    improvement_history: [float()],
    plateau_count: non_neg_integer(),
    last_improvement_step: non_neg_integer(),
    converged?: boolean(),
    convergence_reason: atom() | nil
  }
  
  @spec new() :: convergence_state()
  def new() do
    %{
      best_scores: [],
      improvement_history: [],
      plateau_count: 0,
      last_improvement_step: 0,
      converged?: false,
      convergence_reason: nil
    }
  end
  
  @spec update(convergence_state(), float(), non_neg_integer()) :: convergence_state()
  def update(state, current_best_score, step) do
    updated_scores = [current_best_score | state.best_scores] |> Enum.take(10)  # Keep last 10
    
    improvement = calculate_improvement(updated_scores)
    updated_improvements = [improvement | state.improvement_history] |> Enum.take(5)
    
    # Check for improvement
    {plateau_count, last_improvement} = if improvement > 0.01 do  # Configurable threshold
      {0, step}
    else
      {state.plateau_count + 1, state.last_improvement_step}
    end
    
    # Check convergence conditions
    {converged?, reason} = check_convergence(updated_scores, updated_improvements, plateau_count, step - last_improvement)
    
    %{
      best_scores: updated_scores,
      improvement_history: updated_improvements,
      plateau_count: plateau_count,
      last_improvement_step: last_improvement,
      converged?: converged?,
      convergence_reason: reason
    }
  end
  
  defp calculate_improvement(scores) do
    case scores do
      [current, previous | _] -> current - previous
      _ -> 0.0
    end
  end
  
  defp check_convergence(scores, improvements, plateau_count, steps_since_improvement) do
    cond do
      # Plateau detection: no improvement for many steps
      plateau_count >= 5 ->
        {true, :score_plateau}
      
      # No improvement for too long
      steps_since_improvement >= 8 ->
        {true, :no_improvement}
      
      # Very small improvements consistently
      length(improvements) >= 3 and Enum.all?(improvements, &(&1 < 0.005)) ->
        {true, :minimal_improvement}

      # High performance achieved (if we have a target)
      length(scores) >= 3 and List.first(scores) >= 0.95 ->
        {true, :target_achieved}
      
      # Score variance is very low (stuck in local optimum)
      length(scores) >= 5 and calculate_score_variance(scores) < 0.001 ->
        {true, :low_variance}
      
      # Otherwise, continue optimization
      true ->
        {false, nil}
    end
  end
  
  defp calculate_score_variance(scores) when length(scores) < 2, do: 1.0
  defp calculate_score_variance(scores) do
    mean = Enum.sum(scores) / length(scores)
    variance = scores
      |> Enum.map(fn score -> :math.pow(score - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(scores))
    
    :math.sqrt(variance)  # Return standard deviation
  end
end
```