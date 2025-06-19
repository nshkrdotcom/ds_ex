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
