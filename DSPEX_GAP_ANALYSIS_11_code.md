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

## 12. **NEW: Memory-Efficient Trajectory Management**

```elixir
defmodule DSPEx.Teleprompter.SIMBA.TrajectoryManager do
  @moduledoc """
  Memory-efficient trajectory management with selective storage and compression.
  """
  
  use GenServer
  
  alias DSPEx.Teleprompter.SIMBA.Trajectory
  
  @type trajectory_summary :: %{
    score: float(),
    program_type: atom(),
    execution_time: non_neg_integer(),
    success: boolean(),
    hash: binary()
  }
  
  defstruct [
    :max_trajectories,
    :compression_threshold,
    trajectories: [],
    summaries: [],
    total_stored: 0,
    memory_usage: 0
  ]
  
  @type t :: %__MODULE__{
    max_trajectories: pos_integer(),
    compression_threshold: pos_integer(),
    trajectories: [Trajectory.t()],
    summaries: [trajectory_summary()],
    total_stored: non_neg_integer(),
    memory_usage: non_neg_integer()
  }
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def store_trajectory(trajectory) do
    GenServer.call(__MODULE__, {:store_trajectory, trajectory})
  end
  
  def get_recent_trajectories(count \\ 100) do
    GenServer.call(__MODULE__, {:get_recent, count})
  end
  
  def get_trajectory_statistics() do
    GenServer.call(__MODULE__, :get_statistics)
  end
  
  def cleanup_old_trajectories() do
    GenServer.cast(__MODULE__, :cleanup)
  end
  
  # Server Callbacks
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      max_trajectories: Keyword.get(opts, :max_trajectories, 1000),
      compression_threshold: Keyword.get(opts, :compression_threshold, 500)
    }
    
    # Schedule periodic cleanup
    :timer.send_interval(30_000, :cleanup)
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:store_trajectory, trajectory}, _from, state) do
    {updated_state, stored} = store_trajectory_internal(state, trajectory)
    {:reply, stored, updated_state}
  end
  
  def handle_call({:get_recent, count}, _from, state) do
    recent = Enum.take(state.trajectories, count)
    {:reply, recent, state}
  end
  
  def handle_call(:get_statistics, _from, state) do
    stats = calculate_statistics(state)
    {:reply, stats, state}
  end
  
  @impl GenServer
  def handle_cast(:cleanup, state) do
    updated_state = cleanup_trajectories(state)
    {:noreply, updated_state}
  end
  
  @impl GenServer
  def handle_info(:cleanup, state) do
    updated_state = cleanup_trajectories(state)
    {:noreply, updated_state}
  end
  
  # Internal Functions
  
  defp store_trajectory_internal(state, trajectory) do
    # Calculate trajectory hash for deduplication
    trajectory_hash = calculate_trajectory_hash(trajectory)
    
    # Check if we already have this trajectory
    existing_hash = Enum.find(state.summaries, &(&1.hash == trajectory_hash))
    
    if existing_hash do
      {state, false}  # Don't store duplicate
    else
      # Store trajectory and create summary
      summary = create_trajectory_summary(trajectory, trajectory_hash)
      
      updated_trajectories = [trajectory | state.trajectories]
      updated_summaries = [summary | state.summaries]
      
      # Check if we need compression/cleanup
      updated_state = %{state |
        trajectories: updated_trajectories,
        summaries: updated_summaries,
        total_stored: state.total_stored + 1
      }
      
      final_state = if length(updated_trajectories) > state.compression_threshold do
        compress_old_trajectories(updated_state)
      else
        updated_state
      end
      
      {final_state, true}
    end
  end
  
  defp calculate_trajectory_hash(trajectory) do
    hash_data = %{
      inputs: trajectory.inputs,
      outputs: trajectory.outputs,
      program_type: trajectory.metadata[:program_type],
      model_config: trajectory.model_config
    }
    
    hash_data
    |> :erlang.term_to_binary()
    |> :crypto.hash(:sha256)
  end
  
  defp create_trajectory_summary(trajectory, hash) do
    %{
      score: trajectory.score,
      program_type: trajectory.metadata[:program_type] || :unknown,
      execution_time: trajectory.duration,
      success: trajectory.success,
      hash: hash
    }
  end
  
  defp compress_old_trajectories(state) do
    # Keep recent high-performing trajectories, compress the rest
    {keep_full, compress} = state.trajectories
      |> Enum.with_index()
      |> Enum.split_with(fn {trajectory, index} ->
        index < 100 or trajectory.score > 0.8  # Keep recent or high-scoring
      end)
    
    kept_trajectories = Enum.map(keep_full, fn {trajectory, _} -> trajectory end)
    compressed_summaries = Enum.map(compress, fn {trajectory, _} ->
      create_trajectory_summary(trajectory, calculate_trajectory_hash(trajectory))
    end)
    
    %{state |
      trajectories: kept_trajectories,
      summaries: state.summaries ++ compressed_summaries
    }
  end
  
  defp cleanup_trajectories(state) do
    # Remove oldest trajectories if we exceed max_trajectories
    if length(state.trajectories) > state.max_trajectories do
      kept_trajectories = Enum.take(state.trajectories, state.max_trajectories)
      %{state | trajectories: kept_trajectories}
    else
      state
    end
  end
  
  defp calculate_statistics(state) do
    trajectory_scores = Enum.map(state.trajectories, & &1.score)
    summary_scores = Enum.map(state.summaries, & &1.score)
    all_scores = trajectory_scores ++ summary_scores
    
    %{
      total_trajectories: length(state.trajectories),
      total_summaries: length(state.summaries),
      total_stored: state.total_stored,
      memory_usage_estimate: estimate_memory_usage(state),
      score_statistics: if Enum.empty?(all_scores) do
        %{}
      else
        %{
          mean: Enum.sum(all_scores) / length(all_scores),
          min: Enum.min(all_scores),
          max: Enum.max(all_scores),
          count: length(all_scores)
        }
      end
    }
  end
  
  defp estimate_memory_usage(state) do
    # Rough estimate of memory usage
    trajectory_size = length(state.trajectories) * 1024  # Assume ~1KB per trajectory
    summary_size = length(state.summaries) * 100        # Assume ~100B per summary
    trajectory_size + summary_size
  end
end
```

---

# Part V: Configuration & Integration

## 13. **NEW: Enhanced Configuration System**

```elixir
defmodule DSPEx.Teleprompter.SIMBA.Config do
  @moduledoc """
  Enhanced configuration system for SIMBA with validation and presets.
  """
  
  @type strategy_config :: %{
    name: atom(),
    weight: float(),
    params: map()
  }
  
  @type config :: %{
    # Core algorithm parameters
    max_steps: pos_integer(),
    bsize: pos_integer(),
    num_candidates: pos_integer(),
    num_threads: pos_integer(),
    
    # Temperature and sampling
    temperature_for_sampling: float(),
    temperature_for_candidates: float(),
    temperature_schedule: atom(),
    
    # Strategy configuration
    strategies: [strategy_config()],
    strategy_selection: :random | :weighted | :adaptive,
    
    # Convergence and stopping
    convergence_detection: boolean(),
    early_stopping_patience: pos_integer(),
    min_improvement_threshold: float(),
    
    # Performance and memory
    memory_limit_mb: pos_integer(),
    trajectory_retention: pos_integer(),
    evaluation_batch_size: pos_integer(),
    
    # Observability
    telemetry_enabled: boolean(),
    progress_callback: function() | nil,
    correlation_id: String.t(),
    
    # Advanced features
    adaptive_batch_size: boolean(),
    dynamic_candidate_count: boolean(),
    predictor_analysis: boolean()
  }
  
  @default_config %{
    max_steps: 20,
    bsize: 4,
    num_candidates: 8,
    num_threads: 20,
    temperature_for_sampling: 1.4,
    temperature_for_candidates: 0.7,
    temperature_schedule: :cosine,
    strategies: [
      %{name: :append_demo, weight: 0.7, params: %{}},
      %{name: :append_rule, weight: 0.3, params: %{}}
    ],
    strategy_selection: :weighted,
    convergence_detection: true,
    early_stopping_patience: 5,
    min_improvement_threshold: 0.01,
    memory_limit_mb: 512,
    trajectory_retention: 1000,
    evaluation_batch_size: 10,
    telemetry_enabled: true,
    progress_callback: nil,
    correlation_id: nil,
    adaptive_batch_size: false,
    dynamic_candidate_count: false,
    predictor_analysis: true
  }
  
  @spec new(map()) :: {:ok, config()} | {:error, term()}
  def new(opts \\ %{}) do
    config = Map.merge(@default_config, opts)
    
    case validate_config(config) do
      :ok -> 
        {:ok, normalize_config(config)}
      {:error, reason} -> 
        {:error, reason}
    end
  end
  
  @spec get_preset(:fast | :balanced | :thorough | :memory_efficient) :: config()
  def get_preset(:fast) do
    Map.merge(@default_config, %{
      max_steps: 10,
      bsize: 8,
      num_candidates: 4,
      num_threads: 10,
      convergence_detection: false,
      trajectory_retention: 200
    })
  end
