# Part IV: Performance Optimizations & Advanced Features

## 11. **NEW: Adaptive Temperature Scheduling**

```elixir
defmodule DSPEx.Teleprompter.SIMBA.TemperatureScheduler do
  @moduledoc """
  Adaptive temperature scheduling for SIMBA optimization.
  
  Implements multiple temperature schedules:
  - Linear decay
  - Exponential decay  
  - Cosine annealing
  - Adaptive based on performance
  """
  
  @type schedule_type :: :linear | :exponential | :cosine | :adaptive
  @type scheduler_state :: %{
    initial_temp: float(),
    current_temp: float(),
    schedule_type: schedule_type(),
    step: non_neg_integer(),
    max_steps: non_neg_integer(),
    performance_history: [float()],
    last_improvement: non_neg_integer()
  }
  
  @spec new(schedule_type(), float(), non_neg_integer()) :: scheduler_state()
  def new(schedule_type, initial_temp, max_steps) do
    %{
      initial_temp: initial_temp,
      current_temp: initial_temp,
      schedule_type: schedule_type,
      step: 0,
      max_steps: max_steps,
      performance_history: [],
      last_improvement: 0
    }
  end
  
  @spec update(scheduler_state(), float()) :: scheduler_state()
  def update(state, current_performance) do
    updated_history = [current_performance | state.performance_history] |> Enum.take(10)
    
    # Check for improvement
    last_improvement = if improved?(updated_history) do
      state.step
    else
      state.last_improvement
    end
    
    # Calculate new temperature based on schedule
    new_temp = calculate_temperature(state.schedule_type, state)
    
    %{state |
      current_temp: new_temp,
      step: state.step + 1,
      performance_history: updated_history,
      last_improvement: last_improvement
    }
  end
  
  defp improved?(history) when length(history) < 2, do: true
  defp improved?([current, previous | _]), do: current > previous
  
  defp calculate_temperature(:linear, state) do
    progress = state.step / state.max_steps
    state.initial_temp * (1.0 - progress)
  end
  
  defp calculate_temperature(:exponential, state) do
    decay_rate = 0.95
    state.initial_temp * :math.pow(decay_rate, state.step)
  end
  
  defp calculate_temperature(:cosine, state) do
    progress = state.step / state.max_steps
    min_temp = 0.1
    temp_range = state.initial_temp - min_temp
    min_temp + temp_range * 0.5 * (1 + :math.cos(:math.pi() * progress))
  end
  
  defp calculate_temperature(:adaptive, state) do
    base_temp = calculate_temperature(:cosine, state)
    
    # Adjust based on recent performance
    steps_since_improvement = state.step - state.last_improvement
    
    cond do
      # No recent improvement - increase exploration
      steps_since_improvement > 3 ->
        min(base_temp * 1.5, state.initial_temp)
      
      # Recent improvement - decrease exploration
      steps_since_improvement == 0 ->
        base_temp * 0.8
      
      # Default
      true ->
        base_temp
    end
  end
end
```
