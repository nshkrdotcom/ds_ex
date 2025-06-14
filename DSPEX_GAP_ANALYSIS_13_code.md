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

  def get_preset(:balanced) do
    @default_config
  end
  
  def get_preset(:thorough) do
    Map.merge(@default_config, %{
      max_steps: 50,
      bsize: 2,
      num_candidates: 16,
      num_threads: 30,
      early_stopping_patience: 10,
      min_improvement_threshold: 0.005,
      trajectory_retention: 2000,
      adaptive_batch_size: true,
      dynamic_candidate_count: true
    })
  end
  
  def get_preset(:memory_efficient) do
    Map.merge(@default_config, %{
      max_steps: 15,
      bsize: 2,
      num_candidates: 4,
      num_threads: 8,
      memory_limit_mb: 128,
      trajectory_retention: 100,
      evaluation_batch_size: 5
    })
  end
  
  defp validate_config(config) do
    with :ok <- validate_positive_integers(config),
         :ok <- validate_temperature_ranges(config),
         :ok <- validate_strategies(config),
         :ok <- validate_memory_settings(config) do
      :ok
    end
  end
  
  defp validate_positive_integers(config) do
    required_positive = [:max_steps, :bsize, :num_candidates, :num_threads, 
                         :early_stopping_patience, :memory_limit_mb, 
                         :trajectory_retention, :evaluation_batch_size]
    
    invalid_fields = Enum.filter(required_positive, fn field ->
      value = Map.get(config, field)
      not is_integer(value) or value <= 0
    end)
    
    if Enum.empty?(invalid_fields) do
      :ok
    else
      {:error, {:invalid_positive_integers, invalid_fields}}
    end
  end
  
  defp validate_temperature_ranges(config) do
    temp_fields = [:temperature_for_sampling, :temperature_for_candidates, :min_improvement_threshold]
    
    invalid_temps = Enum.filter(temp_fields, fn field ->
      value = Map.get(config, field)
      not is_number(value) or value < 0 or value > 10
    end)
    
    if Enum.empty?(invalid_temps) do
      :ok
    else
      {:error, {:invalid_temperature_ranges, invalid_temps}}
    end
  end
  
  defp validate_strategies(config) do
    strategies = Map.get(config, :strategies, [])
    
    cond do
      not is_list(strategies) ->
        {:error, :strategies_must_be_list}
      
      Enum.empty?(strategies) ->
        {:error, :strategies_cannot_be_empty}
      
      not all_valid_strategies?(strategies) ->
        {:error, :invalid_strategy_format}
      
      true ->
        :ok
    end
  end
  
  defp all_valid_strategies?(strategies) do
    Enum.all?(strategies, fn strategy ->
      is_map(strategy) and
      Map.has_key?(strategy, :name) and
      Map.has_key?(strategy, :weight) and
      Map.has_key?(strategy, :params) and
      is_atom(strategy.name) and
      is_number(strategy.weight) and
      strategy.weight >= 0 and
      strategy.weight <= 1 and
      is_map(strategy.params)
    end)
  end
  
  defp validate_memory_settings(config) do
    memory_limit = Map.get(config, :memory_limit_mb)
    trajectory_retention = Map.get(config, :trajectory_retention)
    
    # Rough estimate: each trajectory ~1KB, so warn if retention might exceed memory limit
    estimated_trajectory_memory = trajectory_retention * 1024 / (1024 * 1024)  # Convert to MB
    
    if estimated_trajectory_memory > memory_limit * 0.8 do
      {:error, {:memory_settings_incompatible, 
        "Trajectory retention (#{trajectory_retention}) may exceed memory limit (#{memory_limit}MB)"}}
    else
      :ok
    end
  end
  
  defp normalize_config(config) do
    config
    |> ensure_correlation_id()
    |> normalize_strategy_weights()
    |> validate_temperature_schedule()
  end
  
  defp ensure_correlation_id(config) do
    if is_nil(config.correlation_id) do
      correlation_id = "simba_" <> Base.encode16(:crypto.strong_rand_bytes(8))
      Map.put(config, :correlation_id, correlation_id)
    else
      config
    end
  end
  
  defp normalize_strategy_weights(config) do
    strategies = config.strategies
    total_weight = Enum.reduce(strategies, 0.0, fn strategy, acc -> 
      acc + strategy.weight 
    end)
    
    if total_weight > 0 do
      normalized_strategies = Enum.map(strategies, fn strategy ->
        %{strategy | weight: strategy.weight / total_weight}
      end)
      
      Map.put(config, :strategies, normalized_strategies)
    else
      # If all weights are 0, distribute equally
      equal_weight = 1.0 / length(strategies)
      normalized_strategies = Enum.map(strategies, fn strategy ->
        %{strategy | weight: equal_weight}
      end)
      
      Map.put(config, :strategies, normalized_strategies)
    end
  end
  
  defp validate_temperature_schedule(config) do
    valid_schedules = [:linear, :exponential, :cosine, :adaptive]
    
    if config.temperature_schedule in valid_schedules do
      config
    else
      Map.put(config, :temperature_schedule, :cosine)  # Default fallback
    end
  end
  
  @spec merge_with_overrides(config(), map()) :: config()
  def merge_with_overrides(base_config, overrides) do
    Map.merge(base_config, overrides)
  end
  
  @spec to_summary(config()) :: map()
  def to_summary(config) do
    %{
      algorithm: %{
        max_steps: config.max_steps,
        batch_size: config.bsize,
        num_candidates: config.num_candidates,
        temperature_schedule: config.temperature_schedule
      },
      strategies: Enum.map(config.strategies, fn s -> 
        "#{s.name}(#{Float.round(s.weight, 2)})" 
      end),
      performance: %{
        num_threads: config.num_threads,
        memory_limit_mb: config.memory_limit_mb,
        trajectory_retention: config.trajectory_retention
      },
      features: %{
        convergence_detection: config.convergence_detection,
        adaptive_batch_size: config.adaptive_batch_size,
        dynamic_candidate_count: config.dynamic_candidate_count,
        predictor_analysis: config.predictor_analysis
      }
    }
  end
end
```