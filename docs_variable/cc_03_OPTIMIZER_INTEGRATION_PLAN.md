# DSPEx Optimizer Integration Plan for Variable System

## Executive Summary

This document outlines how to integrate the Variable abstraction system with all DSPEx optimizers (SIMBA, BEACON, BootstrapFewShot) to enable any optimizer to tune any discrete parameter automatically. The integration provides a unified interface where optimizers can discover and optimize over module selections, hyperparameters, and configuration choices without optimizer-specific modifications.

## Integration Architecture

### 1. Universal Optimizer Interface

```elixir
defmodule DSPEx.Teleprompter.VariableAware do
  @moduledoc """
  Mixin behavior that adds Variable optimization capabilities to any teleprompter
  """

  defmacro __using__(_opts) do
    quote do
      alias DSPEx.Variable
      alias DSPEx.Variable.Space
      alias DSPEx.Variable.Optimizer

      def compile_with_variables(program, training_data, metric_fn, opts \\ []) do
        variable_space = extract_variable_space(program, opts)
        
        if Variable.Space.empty?(variable_space) do
          # No variables defined, use standard optimization
          compile(program, training_data, metric_fn, opts)
        else
          # Variable-aware optimization
          optimize_with_variable_space(program, training_data, metric_fn, variable_space, opts)
        end
      end

      def optimize_with_variable_space(program, training_data, metric_fn, variable_space, opts) do
        # Create variable-aware optimization context
        context = create_optimization_context(variable_space, opts)
        
        # Run optimizer-specific variable optimization
        run_variable_optimization(program, training_data, metric_fn, context, opts)
      end

      # Override in implementing modules
      def run_variable_optimization(program, training_data, metric_fn, context, opts) do
        raise "Must implement run_variable_optimization/5 in #{__MODULE__}"
      end

      defp extract_variable_space(program, opts) do
        program_variables = if function_exported?(program.__struct__, :variable_space, 0) do
          program.variable_space()
        else
          Variable.Space.new()
        end
        
        # Add optimizer-specific variables
        optimizer_variables = get_optimizer_variables(opts)
        
        # Add global variables (model selection, etc.)
        global_variables = get_global_variables(opts)
        
        Variable.Space.merge([program_variables, optimizer_variables, global_variables])
      end

      defp create_optimization_context(variable_space, opts) do
        %{
          search_strategy: determine_search_strategy(variable_space, opts),
          evaluation_budget: Keyword.get(opts, :evaluation_budget, 20),
          parallelization: Keyword.get(opts, :parallel_evaluations, 4),
          caching: Keyword.get(opts, :cache_evaluations, true),
          early_stopping: Keyword.get(opts, :early_stopping, true)
        }
      end
    end
  end
end
```

### 2. SIMBA Variable Integration

```elixir
defmodule DSPEx.Teleprompter.SIMBA.VariableOptimization do
  use DSPEx.Teleprompter.VariableAware

  def run_variable_optimization(program, training_data, metric_fn, context, opts) do
    variable_space = context.variable_space
    
    # SIMBA-specific variable optimization approach
    case context.search_strategy do
      :stochastic_sampling -> 
        run_stochastic_variable_search(program, training_data, metric_fn, variable_space, opts)
      :guided_sampling ->
        run_guided_variable_search(program, training_data, metric_fn, variable_space, opts)
      :hybrid ->
        run_hybrid_variable_search(program, training_data, metric_fn, variable_space, opts)
    end
  end

  defp run_stochastic_variable_search(program, training_data, metric_fn, variable_space, opts) do
    num_variable_candidates = Keyword.get(opts, :num_variable_candidates, 8)
    num_rounds = Keyword.get(opts, :variable_search_rounds, 3)
    
    best_config = nil
    best_score = 0.0
    
    for round <- 1..num_rounds, reduce: {best_config, best_score} do
      {current_best_config, current_best_score} ->
        
        # Generate variable configurations for this round
        variable_configs = generate_variable_configurations(variable_space, num_variable_candidates, round)
        
        # Evaluate configurations in parallel
        evaluated_configs = evaluate_variable_configurations(
          program, training_data, metric_fn, variable_configs
        )
        
        # Find best configuration this round
        round_best = Enum.max_by(evaluated_configs, fn config -> config.score end)
        
        if round_best.score > current_best_score do
          # Update global best and bias future sampling
          update_variable_sampling_bias(variable_space, round_best.configuration)
          {round_best.configuration, round_best.score}
        else
          {current_best_config, current_best_score}
        end
    end
    
    # Apply best variable configuration and run standard SIMBA
    optimized_program = apply_variable_configuration(program, best_config)
    
    # Run SIMBA on the configured program
    DSPEx.Teleprompter.SIMBA.compile(optimized_program, training_data, metric_fn, opts)
  end

  defp generate_variable_configurations(variable_space, num_candidates, round) do
    sampling_strategy = if round == 1, do: :uniform, else: :biased
    
    1..num_candidates
    |> Enum.map(fn _ ->
      sample_variable_configuration(variable_space, sampling_strategy)
    end)
    |> ensure_diversity(variable_space)
  end

  defp sample_variable_configuration(variable_space, strategy) do
    variable_space.variables
    |> Enum.reduce(%{}, fn {name, variable}, config ->
      value = sample_variable_value(variable, strategy)
      Map.put(config, name, value)
    end)
  end

  defp sample_variable_value(%{type: :choice, constraints: %{choices: choices}}, :uniform) do
    Enum.random(choices)
  end

  defp sample_variable_value(%{type: :choice, constraints: %{choices: choices}} = variable, :biased) do
    # Use accumulated performance data to bias sampling
    bias_weights = get_choice_bias_weights(variable.name, choices)
    weighted_random_choice(choices, bias_weights)
  end

  defp sample_variable_value(%{type: :float, constraints: %{range: {min, max}}}, _strategy) do
    min + :rand.uniform() * (max - min)
  end

  defp sample_variable_value(%{type: :module, constraints: %{modules: modules}}, strategy) do
    # Similar to choice but with module-specific logic
    sample_module_choice(modules, strategy)
  end
end
```

### 3. BEACON Variable Integration

```elixir
defmodule DSPEx.Teleprompter.BEACON.VariableOptimization do
  use DSPEx.Teleprompter.VariableAware

  def run_variable_optimization(program, training_data, metric_fn, context, opts) do
    variable_space = context.variable_space
    
    # Create Bayesian optimization search space
    bo_search_space = create_bayesian_search_space(variable_space)
    
    # Initialize Bayesian optimizer with variable space
    optimizer = initialize_variable_aware_bayesian_optimizer(bo_search_space, opts)
    
    # Run Bayesian optimization over variables
    best_variable_config = run_bayesian_variable_optimization(
      optimizer, program, training_data, metric_fn, opts
    )
    
    # Apply best variable configuration
    configured_program = apply_variable_configuration(program, best_variable_config)
    
    # Run standard BEACON on configured program
    DSPEx.Teleprompter.BEACON.compile(configured_program, training_data, metric_fn, opts)
  end

  defp create_bayesian_search_space(variable_space) do
    variable_space.variables
    |> Enum.map(fn {name, variable} ->
      case variable.type do
        :float -> 
          {name, :continuous, variable.constraints.range}
        :integer -> 
          {name, :discrete, variable.constraints.range}
        :choice -> 
          {name, :categorical, variable.constraints.choices}
        :module ->
          # Convert modules to categorical choices
          module_names = Enum.map(variable.constraints.modules, &module_to_string/1)
          {name, :categorical, module_names}
        :boolean ->
          {name, :categorical, [true, false]}
      end
    end)
  end

  defp run_bayesian_variable_optimization(optimizer, program, training_data, metric_fn, opts) do
    num_iterations = Keyword.get(opts, :bayesian_iterations, 15)
    
    # Bayesian optimization loop
    for iteration <- 1..num_iterations, reduce: optimizer do
      current_optimizer ->
        # Get next configuration to evaluate
        next_config = BayesianOptimizer.suggest_next(current_optimizer)
        
        # Evaluate configuration
        score = evaluate_variable_configuration_score(
          program, training_data, metric_fn, next_config
        )
        
        # Update optimizer with result
        BayesianOptimizer.update(current_optimizer, next_config, score)
    end
    
    # Get best configuration found
    BayesianOptimizer.get_best_configuration(optimizer)
  end

  defp evaluate_variable_configuration_score(program, training_data, metric_fn, config) do
    configured_program = apply_variable_configuration(program, config)
    
    # Evaluate on subset for efficiency
    sample_data = Enum.take_random(training_data, min(5, length(training_data)))
    
    scores = Enum.map(sample_data, fn example ->
      try do
        output = configured_program.forward(example.inputs)
        metric_fn.(output, example.outputs)
      rescue
        _ -> 0.0  # Penalize configurations that cause errors
      end
    end)
    
    Enum.sum(scores) / length(scores)
  end
end
```

### 4. BootstrapFewShot Variable Integration

```elixir
defmodule DSPEx.Teleprompter.BootstrapFewShot.VariableOptimization do
  use DSPEx.Teleprompter.VariableAware

  def run_variable_optimization(program, training_data, metric_fn, context, opts) do
    variable_space = context.variable_space
    
    # For BootstrapFewShot, we can optimize variables alongside example selection
    case determine_bootstrap_variable_strategy(variable_space, opts) do
      :sequential ->
        run_sequential_variable_bootstrap(program, training_data, metric_fn, variable_space, opts)
      :interleaved ->
        run_interleaved_variable_bootstrap(program, training_data, metric_fn, variable_space, opts)
      :parallel ->
        run_parallel_variable_bootstrap(program, training_data, metric_fn, variable_space, opts)
    end
  end

  defp run_sequential_variable_bootstrap(program, training_data, metric_fn, variable_space, opts) do
    # First optimize variables
    best_variable_config = optimize_variables_for_bootstrap(
      program, training_data, metric_fn, variable_space, opts
    )
    
    # Then run bootstrap with optimized configuration
    configured_program = apply_variable_configuration(program, best_variable_config)
    
    DSPEx.Teleprompter.BootstrapFewShot.compile(configured_program, training_data, metric_fn, opts)
  end

  defp run_interleaved_variable_bootstrap(program, training_data, metric_fn, variable_space, opts) do
    max_bootstrap_rounds = Keyword.get(opts, :max_bootstrap_rounds, 3)
    
    current_program = program
    current_variable_config = get_default_variable_configuration(variable_space)
    
    for round <- 1..max_bootstrap_rounds, reduce: current_program do
      program_acc ->
        # Optimize variables for current program state
        variable_config = optimize_variables_for_current_state(
          program_acc, training_data, metric_fn, variable_space
        )
        
        # Apply variable configuration
        configured_program = apply_variable_configuration(program_acc, variable_config)
        
        # Run one round of bootstrap
        {:ok, improved_program} = DSPEx.Teleprompter.BootstrapFewShot.compile(
          configured_program, training_data, metric_fn, 
          Keyword.put(opts, :max_bootstrap_rounds, 1)
        )
        
        improved_program
    end
  end
end
```

### 5. Universal Variable Configuration System

```elixir
defmodule DSPEx.Variable.ConfigurationManager do
  @moduledoc """
  Manages variable configurations across all optimizers with caching and validation
  """

  defstruct [
    :configurations,    # Map of config_hash => {config, evaluation_results}
    :cache,            # ETS table for fast lookups
    :validation_rules, # Configuration validation rules
    :dependencies      # Variable dependency resolution
  ]

  def new(opts \\ []) do
    cache_table = :ets.new(:variable_config_cache, [:set, :public])
    
    %__MODULE__{
      configurations: %{},
      cache: cache_table,
      validation_rules: Keyword.get(opts, :validation_rules, []),
      dependencies: %{}
    }
  end

  def apply_variable_configuration(program, variable_config) do
    # Validate configuration
    validated_config = validate_configuration(variable_config, program)
    
    # Resolve dependencies
    resolved_config = resolve_variable_dependencies(validated_config)
    
    # Apply configuration to program
    apply_configuration_to_program(program, resolved_config)
  end

  defp validate_configuration(config, program) do
    variable_space = get_program_variable_space(program)
    
    # Check all required variables are present
    required_variables = get_required_variables(variable_space)
    missing_variables = required_variables -- Map.keys(config)
    
    if length(missing_variables) > 0 do
      raise "Missing required variables: #{inspect(missing_variables)}"
    end
    
    # Validate each variable value
    Enum.each(config, fn {name, value} ->
      variable = variable_space.variables[name]
      validate_variable_value(variable, value)
    end)
    
    config
  end

  defp resolve_variable_dependencies(config) do
    # Handle conditional variables
    resolved = resolve_conditional_variables(config)
    
    # Handle composite variables
    resolve_composite_variables(resolved)
  end

  defp apply_configuration_to_program(program, config) do
    # Apply different types of configuration
    program
    |> apply_module_selections(config)
    |> apply_parameter_values(config)
    |> apply_strategy_configurations(config)
  end

  defp apply_module_selections(program, config) do
    config
    |> Enum.filter(fn {_name, value} -> is_module(value) end)
    |> Enum.reduce(program, fn {name, module}, prog_acc ->
      case name do
        :adapter -> %{prog_acc | adapter: module}
        :reasoning_module -> %{prog_acc | reasoning_module: module}
        :client -> %{prog_acc | client: module}
        _ -> prog_acc
      end
    end)
  end

  defp apply_parameter_values(program, config) do
    parameter_config = 
      config
      |> Enum.filter(fn {_name, value} -> not is_module(value) end)
      |> Map.new()
    
    %{program | variable_config: parameter_config}
  end
end
```

### 6. Cross-Optimizer Variable Coordination

```elixir
defmodule DSPEx.Variable.CrossOptimizerCoordination do
  @moduledoc """
  Coordinates variable optimization across multiple optimizers for ensemble approaches
  """

  def run_multi_optimizer_variable_search(program, training_data, metric_fn, opts \\ []) do
    optimizers = Keyword.get(opts, :optimizers, [:simba, :beacon, :bootstrap])
    coordination_strategy = Keyword.get(opts, :coordination, :parallel)
    
    case coordination_strategy do
      :parallel -> 
        run_parallel_multi_optimizer_search(program, training_data, metric_fn, optimizers, opts)
      :sequential ->
        run_sequential_multi_optimizer_search(program, training_data, metric_fn, optimizers, opts)
      :competitive ->
        run_competitive_multi_optimizer_search(program, training_data, metric_fn, optimizers, opts)
    end
  end

  defp run_parallel_multi_optimizer_search(program, training_data, metric_fn, optimizers, opts) do
    # Run all optimizers in parallel with variable optimization
    optimizer_tasks = 
      optimizers
      |> Enum.map(fn optimizer ->
        Task.async(fn ->
          run_single_optimizer_with_variables(optimizer, program, training_data, metric_fn, opts)
        end)
      end)
    
    # Collect results
    results = 
      optimizer_tasks
      |> Task.await_many(300_000)  # 5 minute timeout
    
    # Select best result across all optimizers
    best_result = select_best_multi_optimizer_result(results)
    
    {:ok, best_result.program, best_result.configuration}
  end

  defp run_single_optimizer_with_variables(optimizer, program, training_data, metric_fn, opts) do
    case optimizer do
      :simba -> 
        DSPEx.Teleprompter.SIMBA.VariableOptimization.compile_with_variables(
          program, training_data, metric_fn, opts
        )
      :beacon ->
        DSPEx.Teleprompter.BEACON.VariableOptimization.compile_with_variables(
          program, training_data, metric_fn, opts
        )
      :bootstrap ->
        DSPEx.Teleprompter.BootstrapFewShot.VariableOptimization.compile_with_variables(
          program, training_data, metric_fn, opts
        )
    end
  end

  defp run_competitive_multi_optimizer_search(program, training_data, metric_fn, optimizers, opts) do
    # Start all optimizers and let them compete with shared variable insights
    shared_variable_knowledge = create_shared_variable_knowledge_store()
    
    optimizer_processes = 
      optimizers
      |> Enum.map(fn optimizer ->
        spawn_link(fn ->
          run_competitive_optimizer_process(
            optimizer, program, training_data, metric_fn, 
            shared_variable_knowledge, opts
          )
        end)
      end)
    
    # Monitor and coordinate the competitive search
    coordinate_competitive_search(optimizer_processes, shared_variable_knowledge, opts)
  end
end
```

### 7. Performance Optimization and Caching

```elixir
defmodule DSPEx.Variable.PerformanceOptimization do
  @moduledoc """
  Performance optimizations for variable-aware optimization including caching,
  parallelization, and early stopping
  """

  def evaluate_configurations_efficiently(program, training_data, metric_fn, configurations, opts \\ []) do
    # Use various performance optimizations
    configurations
    |> filter_cached_configurations(opts)
    |> parallelize_evaluations(program, training_data, metric_fn, opts)
    |> apply_early_stopping(opts)
    |> cache_results(opts)
  end

  defp filter_cached_configurations(configurations, opts) do
    if Keyword.get(opts, :use_cache, true) do
      configurations
      |> Enum.reject(fn config ->
        config_hash = hash_configuration(config)
        cached_result_exists?(config_hash)
      end)
    else
      configurations
    end
  end

  defp parallelize_evaluations(configurations, program, training_data, metric_fn, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    
    configurations
    |> Task.async_stream(
      fn config ->
        evaluate_single_configuration_with_timeout(program, training_data, metric_fn, config, opts)
      end,
      max_concurrency: max_concurrency,
      timeout: Keyword.get(opts, :evaluation_timeout, 30_000)
    )
    |> Enum.map(fn 
      {:ok, result} -> result
      {:exit, :timeout} -> %{configuration: nil, score: 0.0, error: :timeout}
    end)
    |> Enum.reject(fn result -> result.configuration == nil end)
  end

  defp apply_early_stopping(evaluated_configs, opts) do
    if Keyword.get(opts, :early_stopping, false) do
      threshold = Keyword.get(opts, :early_stopping_threshold, 0.95)
      
      # Sort by score and check if we have a sufficiently good result
      sorted_configs = Enum.sort_by(evaluated_configs, fn config -> config.score end, :desc)
      
      case sorted_configs do
        [best | _] when best.score >= threshold ->
          # Early stopping triggered
          [best]
        _ ->
          evaluated_configs
      end
    else
      evaluated_configs  
    end
  end

  defp evaluate_single_configuration_with_timeout(program, training_data, metric_fn, config, opts) do
    timeout = Keyword.get(opts, :single_evaluation_timeout, 10_000)
    
    task = Task.async(fn ->
      evaluate_single_configuration(program, training_data, metric_fn, config)
    end)
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> %{configuration: config, score: 0.0, error: :timeout}
    end
  end
end
```

## Integration Testing Strategy

### 1. Optimizer Compatibility Tests

```elixir
defmodule DSPEx.Variable.IntegrationTest do
  use ExUnit.Case

  test "all optimizers work with variable system" do
    program = create_test_program_with_variables()
    training_data = create_test_training_data()
    metric_fn = &test_metric_function/2
    
    # Test SIMBA integration
    {:ok, simba_result, simba_config} = 
      DSPEx.Teleprompter.SIMBA.VariableOptimization.compile_with_variables(
        program, training_data, metric_fn
      )
    
    assert simba_result != nil
    assert simba_config != %{}
    
    # Test BEACON integration
    {:ok, beacon_result, beacon_config} = 
      DSPEx.Teleprompter.BEACON.VariableOptimization.compile_with_variables(
        program, training_data, metric_fn
      )
    
    assert beacon_result != nil
    assert beacon_config != %{}
    
    # Test BootstrapFewShot integration
    {:ok, bootstrap_result, bootstrap_config} = 
      DSPEx.Teleprompter.BootstrapFewShot.VariableOptimization.compile_with_variables(
        program, training_data, metric_fn
      )
    
    assert bootstrap_result != nil
    assert bootstrap_config != %{}
  end

  test "variable configurations improve performance" do
    program = create_test_program_with_variables()
    training_data = create_test_training_data()
    metric_fn = &test_metric_function/2
    
    # Baseline without variable optimization
    {:ok, baseline_program} = DSPEx.Teleprompter.SIMBA.compile(
      program, training_data, metric_fn
    )
    baseline_score = evaluate_program(baseline_program, training_data, metric_fn)
    
    # With variable optimization
    {:ok, optimized_program, _config} = 
      DSPEx.Teleprompter.SIMBA.VariableOptimization.compile_with_variables(
        program, training_data, metric_fn
      )
    optimized_score = evaluate_program(optimized_program, training_data, metric_fn)
    
    # Variable optimization should improve performance
    assert optimized_score >= baseline_score
  end
end
```

### 2. Performance Benchmarks

```elixir
defmodule DSPEx.Variable.PerformanceBenchmark do
  def run_comprehensive_benchmarks do
    results = %{
      variable_overhead: measure_variable_overhead(),
      optimization_quality: measure_optimization_quality(),
      convergence_speed: measure_convergence_speed(),
      memory_usage: measure_memory_usage()
    }
    
    generate_benchmark_report(results)
  end

  defp measure_variable_overhead do
    # Compare optimization time with and without variables
    program = create_benchmark_program()
    training_data = create_benchmark_data()
    metric_fn = &benchmark_metric/2
    
    # Without variables
    {time_baseline, _} = :timer.tc(fn ->
      DSPEx.Teleprompter.SIMBA.compile(program, training_data, metric_fn)
    end)
    
    # With variables
    program_with_vars = add_variables_to_program(program)
    {time_with_vars, _} = :timer.tc(fn ->
      DSPEx.Teleprompter.SIMBA.VariableOptimization.compile_with_variables(
        program_with_vars, training_data, metric_fn
      )
    end)
    
    overhead_percentage = ((time_with_vars - time_baseline) / time_baseline) * 100
    %{baseline_time: time_baseline, variable_time: time_with_vars, overhead: overhead_percentage}
  end
end
```

## Deployment Strategy

### Phase 1: Core Integration (Weeks 1-2)
- Implement `DSPEx.Teleprompter.VariableAware` behavior
- Create basic variable configuration management
- Add variable support to SIMBA

### Phase 2: Extended Optimizer Support (Weeks 3-4)
- Implement BEACON variable integration
- Add BootstrapFewShot variable support
- Create cross-optimizer coordination

### Phase 3: Performance Optimization (Weeks 5-6)
- Implement caching and parallelization
- Add early stopping mechanisms
- Optimize memory usage

### Phase 4: Testing and Validation (Weeks 7-8)
- Comprehensive integration testing
- Performance benchmarking
- Documentation and examples

This integration plan ensures that any optimizer in DSPEx can automatically tune any discrete parameter, fulfilling Omar Khattab's vision for a unified parameter optimization system.