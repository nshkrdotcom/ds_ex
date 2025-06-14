# Part III: Missing Infrastructure Components (Continued)

## 8. **NEW: Convergence Detection (Continued)**

```elixir
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

## 9. **NEW: Advanced Evaluation System**

```elixir
defmodule DSPEx.Teleprompter.SIMBA.Evaluation do
  @moduledoc """
  Advanced evaluation system for SIMBA with comprehensive metrics and analysis.
  """
  
  alias DSPEx.{Program, Example}
  
  @type evaluation_result :: %{
    score: float(),
    detailed_scores: map(),
    execution_time: non_neg_integer(),
    memory_usage: non_neg_integer(),
    success: boolean(),
    error: any() | nil,
    metadata: map()
  }
  
  @spec evaluate_comprehensive(Program.t(), [Example.t()], function()) :: evaluation_result()
  def evaluate_comprehensive(program, examples, metric_fn) do
    start_time = System.monotonic_time()
    {memory_before, _} = :erlang.process_info(self(), [:memory, :heap_size])
    
    # Execute on all examples with detailed tracking
    results = examples
      |> Task.async_stream(
        fn example -> 
          evaluate_single_example_detailed(program, example, metric_fn)
        end,
        max_concurrency: 10,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> %{success: false, score: 0.0, error: reason}
      end)
    
    {memory_after, _} = :erlang.process_info(self(), [:memory, :heap_size])
    execution_time = System.monotonic_time() - start_time
    
    # Aggregate results
    successful_results = Enum.filter(results, & &1.success)
    total_score = if Enum.empty?(successful_results) do
      0.0
    else
      successful_results
      |> Enum.map(& &1.score)
      |> Enum.sum()
      |> Kernel./(length(successful_results))
    end
    
    %{
      score: total_score,
      detailed_scores: calculate_detailed_scores(results),
      execution_time: execution_time,
      memory_usage: memory_after - memory_before,
      success: length(successful_results) > 0,
      error: aggregate_errors(results),
      metadata: %{
        total_examples: length(examples),
        successful_examples: length(successful_results),
        success_rate: length(successful_results) / length(examples),
        score_distribution: calculate_score_distribution(results),
        performance_percentiles: calculate_performance_percentiles(results)
      }
    }
  end
  
  defp evaluate_single_example_detailed(program, example, metric_fn) do
    start_time = System.monotonic_time()
    inputs = Example.inputs(example)
    
    case Program.forward(program, inputs) do
      {:ok, outputs} ->
        score = try do
          metric_fn.(example, outputs)
        rescue
          error -> 
            {:error_in_metric, error}
        catch
          thrown -> 
            {:error_in_metric, thrown}
        end
        
        case score do
          score when is_number(score) ->
            %{
              success: true,
              score: score,
              execution_time: System.monotonic_time() - start_time,
              outputs: outputs,
              error: nil
            }
          error ->
            %{
              success: false,
              score: 0.0,
              execution_time: System.monotonic_time() - start_time,
              outputs: outputs,
              error: error
            }
        end
        
      {:error, reason} ->
        %{
          success: false,
          score: 0.0,
          execution_time: System.monotonic_time() - start_time,
          outputs: %{},
          error: reason
        }
    end
  rescue
    error ->
      %{
        success: false,
        score: 0.0,
        execution_time: System.monotonic_time() - start_time,
        outputs: %{},
        error: {:execution_exception, error}
      }
  end
  
  defp calculate_detailed_scores(results) do
    successful_results = Enum.filter(results, & &1.success)
    scores = Enum.map(successful_results, & &1.score)
    
    if Enum.empty?(scores) do
      %{
        mean: 0.0,
        median: 0.0,
        min: 0.0,
        max: 0.0,
        std_dev: 0.0
      }
    else
      sorted_scores = Enum.sort(scores)
      mean = Enum.sum(scores) / length(scores)
      
      %{
        mean: mean,
        median: calculate_median(sorted_scores),
        min: List.first(sorted_scores),
        max: List.last(sorted_scores),
        std_dev: calculate_standard_deviation(scores, mean)
      }
    end
  end
  
  defp calculate_median(sorted_list) when length(sorted_list) == 0, do: 0.0
  defp calculate_median(sorted_list) do
    len = length(sorted_list)
    mid = div(len, 2)
    
    if rem(len, 2) == 0 do
      (Enum.at(sorted_list, mid - 1) + Enum.at(sorted_list, mid)) / 2
    else
      Enum.at(sorted_list, mid)
    end
  end
  
  defp calculate_standard_deviation(scores, mean) when length(scores) < 2, do: 0.0
  defp calculate_standard_deviation(scores, mean) do
    variance = scores
      |> Enum.map(fn score -> :math.pow(score - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(scores) - 1)
    
    :math.sqrt(variance)
  end
  
  defp aggregate_errors(results) do
    errors = results
      |> Enum.filter(fn result -> not result.success end)
      |> Enum.map(& &1.error)
      |> Enum.group_by(& &1)
      |> Enum.map(fn {error_type, occurrences} -> 
        {error_type, length(occurrences)} 
      end)
    
    if Enum.empty?(errors), do: nil, else: errors
  end
  
  defp calculate_score_distribution(results) do
    scores = results
      |> Enum.filter(& &1.success)
      |> Enum.map(& &1.score)
    
    if Enum.empty?(scores) do
      %{buckets: [], total_count: 0}
    else
      # Create score buckets (0-0.1, 0.1-0.2, ..., 0.9-1.0)
      buckets = 0..9
        |> Enum.map(fn i ->
          lower = i / 10
          upper = (i + 1) / 10
          count = Enum.count(scores, fn score -> score >= lower and score < upper end)
          # Handle the special case for score = 1.0
          count = if i == 9 do
            count + Enum.count(scores, fn score -> score == 1.0 end)
          else
            count
          end
          %{range: "#{lower}-#{upper}", count: count}
        end)
      
      %{buckets: buckets, total_count: length(scores)}
    end
  end
  
  defp calculate_performance_percentiles(results) do
    scores = results
      |> Enum.filter(& &1.success)
      |> Enum.map(& &1.score)
      |> Enum.sort()
    
    if Enum.empty?(scores) do
      %{}
    else
      %{
        p10: calculate_percentile(scores, 0.1),
        p25: calculate_percentile(scores, 0.25),
        p50: calculate_percentile(scores, 0.5),
        p75: calculate_percentile(scores, 0.75),
        p90: calculate_percentile(scores, 0.9),
        p95: calculate_percentile(scores, 0.95),
        p99: calculate_percentile(scores, 0.99)
      }
    end
  end
  
  defp calculate_percentile(sorted_scores, percentile) do
    len = length(sorted_scores)
    index = (len - 1) * percentile
    
    if index == trunc(index) do
      Enum.at(sorted_scores, trunc(index))
    else
      lower_index = floor(index)
      upper_index = ceil(index)
      weight = index - lower_index
      
      lower_value = Enum.at(sorted_scores, lower_index)
      upper_value = Enum.at(sorted_scores, upper_index)
      
      lower_value + weight * (upper_value - lower_value)
    end
  end
end
```

## 10. **NEW: Predictor Mapping System**

```elixir
defmodule DSPEx.Teleprompter.SIMBA.PredictorMapping do
  @moduledoc """
  System for building and managing predictor mappings for program introspection.
  
  This module analyzes programs to extract predictors and create bidirectional
  mappings between predictor names and actual predictor instances.
  """
  
  alias DSPEx.Program
  
  @type predictor_info :: %{
    name: String.t(),
    type: atom(),
    signature: any(),
    instructions: String.t() | nil,
    metadata: map()
  }
  
  @type predictor_mappings :: {
    predictor_to_name :: %{any() => String.t()},
    name_to_predictor :: %{String.t() => any()}
  }
  
  @spec build_predictor_mappings(Program.t()) :: predictor_mappings()
  def build_predictor_mappings(program) do
    predictors = extract_predictors_from_program(program)
    
    predictor_to_name = predictors
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {{predictor, info}, index}, acc ->
        name = generate_predictor_name(info, index)
        Map.put(acc, predictor, name)
      end)
    
    name_to_predictor = predictor_to_name
      |> Enum.reduce(%{}, fn {predictor, name}, acc ->
        Map.put(acc, name, predictor)
      end)
    
    {predictor_to_name, name_to_predictor}
  end
  
  @spec extract_predictors_from_program(Program.t()) :: [{any(), predictor_info()}]
  defp extract_predictors_from_program(program) do
    case program do
      # ChainOfThought program
      %{predictors: predictors} when is_list(predictors) ->
        predictors
        |> Enum.with_index()
        |> Enum.map(fn {predictor, index} ->
          info = analyze_predictor(predictor, "step_#{index}")
          {predictor, info}
        end)
      
      # Single predictor program
      %{predictor: predictor} when not is_nil(predictor) ->
        info = analyze_predictor(predictor, "main")
        [{predictor, info}]
      
      # OptimizedProgram wrapper
      %DSPEx.OptimizedProgram{program: inner_program} ->
        extract_predictors_from_program(inner_program)
      
      # Try to introspect the program structure
      _ ->
        introspect_program_predictors(program)
    end
  end
  
  @spec analyze_predictor(any(), String.t()) :: predictor_info()
  defp analyze_predictor(predictor, default_name) do
    signature = extract_signature(predictor)
    instructions = extract_instructions(predictor)
    predictor_type = determine_predictor_type(predictor)
    
    %{
      name: default_name,
      type: predictor_type,
      signature: signature,
      instructions: instructions,
      metadata: %{
        has_signature: not is_nil(signature),
        has_instructions: not is_nil(instructions),
        extracted_at: DateTime.utc_now()
      }
    }
  end
  
  defp extract_signature(predictor) do
    cond do
      is_map(predictor) and Map.has_key?(predictor, :signature) ->
        predictor.signature
      
      function_exported?(predictor, :signature, 0) ->
        try do
          predictor.signature()
        rescue
          _ -> nil
        end
      
      true ->
        nil
    end
  end
  
  defp extract_instructions(predictor) do
    signature = extract_signature(predictor)
    
    cond do
      is_nil(signature) ->
        nil
      
      function_exported?(signature, :instructions, 0) ->
        try do
          signature.instructions()
        rescue
          _ -> nil
        end
      
      is_map(signature) and Map.has_key?(signature, :instructions) ->
        signature.instructions
      
      true ->
        nil
    end
  end
  
  defp determine_predictor_type(predictor) do
    cond do
      is_map(predictor) and Map.has_key?(predictor, :__struct__) ->
        predictor.__struct__
        |> Module.split()
        |> List.last()
        |> String.downcase()
        |> String.to_atom()
      
      is_function(predictor) ->
        :function
      
      is_atom(predictor) ->
        :module
      
      true ->
        :unknown
    end
  end
  
  defp introspect_program_predictors(program) do
    # Try to find predictor-like fields through introspection
    program_fields = if is_map(program) do
      Map.keys(program)
    else
      []
    end
    
    predictor_fields = Enum.filter(program_fields, fn field ->
      field_name = to_string(field)
      String.contains?(field_name, "predict") or 
      String.contains?(field_name, "forward") or
      String.contains?(field_name, "generate")
    end)
    
    predictor_fields
    |> Enum.map(fn field ->
      predictor = Map.get(program, field)
      info = analyze_predictor(predictor, to_string(field))
      {predictor, info}
    end)
  end
  
  defp generate_predictor_name(info, index) do
    base_name = case info.type do
      :chainofthought -> "cot"
      :generate -> "gen"
      :predict -> "pred"
      :classify -> "cls"
      _ -> "pred"
    end
    
    if info.metadata.has_signature and not is_nil(info.instructions) do
      instruction_summary = info.instructions
        |> String.split()
        |> Enum.take(3)
        |> Enum.join("_")
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9_]/, "")
      
      "#{base_name}_#{index}_#{instruction_summary}"
    else
      "#{base_name}_#{index}"
    end
  end
  
  @spec find_predictor_by_name(predictor_mappings(), String.t()) :: any() | nil
  def find_predictor_by_name({_predictor_to_name, name_to_predictor}, name) do
    Map.get(name_to_predictor, name)
  end
  
  @spec find_name_by_predictor(predictor_mappings(), any()) :: String.t() | nil
  def find_name_by_predictor({predictor_to_name, _name_to_predictor}, predictor) do
    Map.get(predictor_to_name, predictor)
  end
  
  @spec list_all_predictors(predictor_mappings()) :: [String.t()]
  def list_all_predictors({_predictor_to_name, name_to_predictor}) do
    Map.keys(name_to_predictor)
  end
end
```

---

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
