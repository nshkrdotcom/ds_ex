# DSPEx Adapter & Module Selection Framework

## Overview

This document details the framework for automatic adapter and module selection in DSPEx, addressing the core question from the DSPy community: "Is JSON tool calling better than MD tool calling? Is Predict vs CoT vs PoT better, cheaper?" The framework provides AI-driven selection based on empirical evaluation across multiple dimensions.

## Problem Statement

### Current Limitations
1. **Manual Selection**: Developers manually choose between adapters (JSON vs Markdown) and reasoning modules (Predict vs CoT vs PoT)
2. **No Empirical Basis**: Choices based on intuition rather than systematic evaluation
3. **Context Ignorance**: Same selection used regardless of task characteristics
4. **Optimization Blind Spots**: Optimizers focus on examples/instructions but ignore module selection

### Target Capabilities
- **Automatic Discovery**: System discovers optimal adapter/module combinations
- **Multi-Dimensional Evaluation**: Performance, cost, latency, reliability assessment
- **Context-Aware Selection**: Different choices for different task types
- **Optimization Integration**: Module selection becomes part of the optimization loop

## Architecture Design

### 1. Module Classification System

```elixir
defmodule DSPEx.Module.Registry do
  @moduledoc """
  Registry for all selectable modules with their capabilities and characteristics
  """

  @type module_category :: :adapter | :reasoning | :signature | :client | :teleprompter
  @type module_characteristic :: :performance | :cost | :complexity | :reliability

  defstruct [
    :modules,           # Map of module_name => module_info
    :categories,        # Map of category => [module_names]
    :capabilities,      # Map of module_name => [capabilities]
    :benchmarks        # Map of module_name => benchmark_results
  ]

  def register_module(registry, module_name, opts \\ []) do
    module_info = %{
      name: module_name,
      category: Keyword.get(opts, :category),
      capabilities: Keyword.get(opts, :capabilities, []),
      cost_profile: Keyword.get(opts, :cost_profile, :medium),
      complexity_level: Keyword.get(opts, :complexity_level, :medium),
      supported_signatures: Keyword.get(opts, :supported_signatures, :all),
      benchmark_results: %{}
    }
    
    %{registry | 
      modules: Map.put(registry.modules, module_name, module_info),
      categories: update_categories(registry.categories, module_info)
    }
  end
end
```

### 2. Adapter Selection Framework

#### JSON vs Markdown Tool Calling

```elixir
defmodule DSPEx.Adapter.Selector do
  @moduledoc """
  Intelligent selection between different adapter types based on task characteristics
  """

  # Register available adapters
  @adapters %{
    json_tool: %{
      module: DSPEx.Adapter.JSONTool,
      strengths: [:structured_output, :type_safety, :parsing_reliability],
      weaknesses: [:token_overhead, :model_specific],
      cost_multiplier: 1.2,
      supported_models: ["gpt-4", "gpt-3.5-turbo", "claude-3"],
      complexity_level: :high
    },
    markdown_tool: %{
      module: DSPEx.Adapter.MarkdownTool,
      strengths: [:model_agnostic, :low_overhead, :human_readable],
      weaknesses: [:parsing_fragility, :format_ambiguity],
      cost_multiplier: 1.0,
      supported_models: :all,
      complexity_level: :medium
    },
    structured_text: %{
      module: DSPEx.Adapter.StructuredText,
      strengths: [:parsing_robustness, :format_flexibility],
      weaknesses: [:moderate_overhead],
      cost_multiplier: 1.1,
      supported_models: :all,
      complexity_level: :medium
    }
  }

  def select_adapter(signature, context, evaluation_criteria \\ [:accuracy, :cost, :latency]) do
    # Analyze signature requirements
    signature_analysis = analyze_signature_requirements(signature)
    
    # Filter compatible adapters
    compatible_adapters = filter_compatible_adapters(@adapters, signature_analysis, context)
    
    # Score adapters based on criteria
    scored_adapters = score_adapters(compatible_adapters, signature_analysis, context, evaluation_criteria)
    
    # Select best adapter
    select_best_adapter(scored_adapters)
  end

  defp analyze_signature_requirements(signature) do
    %{
      output_complexity: calculate_output_complexity(signature.outputs),
      field_count: count_fields(signature.outputs),
      nested_structures: has_nested_structures?(signature.outputs),
      type_constraints: extract_type_constraints(signature.outputs),
      validation_requirements: extract_validation_requirements(signature.outputs)
    }
  end

  defp score_adapters(adapters, signature_analysis, context, criteria) do
    adapters
    |> Enum.map(fn {name, adapter_info} ->
      score = calculate_adapter_score(adapter_info, signature_analysis, context, criteria)
      {name, adapter_info, score}
    end)
    |> Enum.sort_by(fn {_, _, score} -> score end, :desc)
  end

  defp calculate_adapter_score(adapter_info, signature_analysis, context, criteria) do
    Enum.reduce(criteria, 0.0, fn criterion, acc ->
      weight = get_criterion_weight(criterion, context)
      score = score_adapter_for_criterion(adapter_info, signature_analysis, criterion)
      acc + (weight * score)
    end)
  end

  defp score_adapter_for_criterion(adapter_info, signature_analysis, :accuracy) do
    base_score = 
      case {adapter_info.module, signature_analysis.output_complexity} do
        {DSPEx.Adapter.JSONTool, complexity} when complexity > 5 -> 0.9
        {DSPEx.Adapter.MarkdownTool, complexity} when complexity <= 3 -> 0.8
        {DSPEx.Adapter.StructuredText, _} -> 0.85
        _ -> 0.5
      end
    
    # Adjust for specific requirements
    if signature_analysis.nested_structures and adapter_info.module == DSPEx.Adapter.JSONTool do
      base_score + 0.1
    else
      base_score
    end
  end

  defp score_adapter_for_criterion(adapter_info, _signature_analysis, :cost) do
    1.0 / adapter_info.cost_multiplier  # Inverse relationship
  end

  defp score_adapter_for_criterion(adapter_info, signature_analysis, :latency) do
    case adapter_info.complexity_level do
      :low -> 0.9
      :medium -> 0.7
      :high -> 0.5
    end
  end
end
```

### 3. Reasoning Module Selection Framework

#### Predict vs CoT vs PoT Selection

```elixir
defmodule DSPEx.Reasoning.Selector do
  @moduledoc """
  Intelligent selection between reasoning strategies based on task analysis
  """

  @reasoning_modules %{
    predict: %{
      module: DSPEx.Reasoning.Predict,
      strengths: [:speed, :simplicity, :cost_efficiency],
      weaknesses: [:limited_reasoning, :black_box],
      best_for: [:simple_qa, :classification, :direct_lookup],
      token_overhead: 0,
      reasoning_depth: 1,
      cost_multiplier: 1.0
    },
    chain_of_thought: %{
      module: DSPEx.Reasoning.CoT,
      strengths: [:step_by_step_reasoning, :transparency, :debugging],
      weaknesses: [:token_overhead, :verbose_output],
      best_for: [:complex_reasoning, :math_problems, :logical_deduction],
      token_overhead: 50,
      reasoning_depth: 3,
      cost_multiplier: 1.5
    },
    program_of_thought: %{
      module: DSPEx.Reasoning.PoT,
      strengths: [:computational_accuracy, :verifiable_logic, :tool_integration],
      weaknesses: [:complexity, :execution_overhead, :debugging_difficulty],
      best_for: [:mathematical_computation, :data_analysis, :algorithmic_tasks],
      token_overhead: 100,
      reasoning_depth: 4,
      cost_multiplier: 2.0
    },
    react: %{
      module: DSPEx.Reasoning.ReAct,
      strengths: [:tool_calling, :iterative_reasoning, :external_knowledge],
      weaknesses: [:high_latency, :complex_debugging, :cascading_errors],
      best_for: [:information_gathering, :multi_step_tasks, :tool_intensive],
      token_overhead: 150,
      reasoning_depth: 5,
      cost_multiplier: 3.0
    }
  }

  def select_reasoning_module(signature, context, constraints \\ %{}) do
    # Analyze task requirements
    task_analysis = analyze_task_requirements(signature, context)
    
    # Apply constraints (budget, latency, etc.)
    viable_modules = filter_by_constraints(@reasoning_modules, constraints)
    
    # Score modules based on task fit
    scored_modules = score_reasoning_modules(viable_modules, task_analysis, constraints)
    
    # Select optimal module
    select_best_reasoning_module(scored_modules)
  end

  defp analyze_task_requirements(signature, context) do
    %{
      complexity_score: calculate_complexity_score(signature, context),
      reasoning_required: requires_reasoning?(signature, context),
      computational_tasks: has_computational_elements?(signature),
      tool_calling_needed: requires_external_tools?(context),
      transparency_important: requires_transparency?(context),
      input_complexity: analyze_input_complexity(signature.inputs),
      domain: infer_domain(signature, context)
    }
  end

  defp calculate_complexity_score(signature, context) do
    base_complexity = count_fields(signature.outputs) * 0.5
    
    input_complexity = 
      signature.inputs
      |> Map.values()
      |> Enum.reduce(0, fn field, acc ->
        acc + estimate_field_complexity(field)
      end)
    
    context_complexity = estimate_context_complexity(context)
    
    base_complexity + input_complexity + context_complexity
  end

  defp score_reasoning_modules(modules, task_analysis, constraints) do
    modules
    |> Enum.map(fn {name, module_info} ->
      score = calculate_reasoning_score(module_info, task_analysis, constraints)
      {name, module_info, score}
    end)
    |> Enum.sort_by(fn {_, _, score} -> score end, :desc)
  end

  defp calculate_reasoning_score(module_info, task_analysis, constraints) do
    # Base score from task fit
    task_fit_score = calculate_task_fit_score(module_info, task_analysis)
    
    # Constraint penalties
    cost_penalty = calculate_cost_penalty(module_info, constraints)
    latency_penalty = calculate_latency_penalty(module_info, constraints)
    
    # Domain-specific bonuses
    domain_bonus = calculate_domain_bonus(module_info, task_analysis.domain)
    
    task_fit_score - cost_penalty - latency_penalty + domain_bonus
  end

  defp calculate_task_fit_score(module_info, task_analysis) do
    base_score = 
      cond do
        task_analysis.complexity_score > 8 and module_info.reasoning_depth >= 3 -> 0.9
        task_analysis.complexity_score <= 3 and module_info.reasoning_depth == 1 -> 0.9
        task_analysis.computational_tasks and module_info.module == DSPEx.Reasoning.PoT -> 0.95
        task_analysis.tool_calling_needed and module_info.module == DSPEx.Reasoning.ReAct -> 0.9
        true -> 0.5
      end
    
    # Adjust for specific requirements
    if task_analysis.transparency_important and module_info.module in [DSPEx.Reasoning.CoT, DSPEx.Reasoning.PoT] do
      base_score + 0.1
    else
      base_score
    end
  end
end
```

### 4. Comprehensive Module Selection Orchestrator

```elixir
defmodule DSPEx.Module.SelectionOrchestrator do
  @moduledoc """
  Orchestrates selection across all module types for optimal program configuration
  """

  alias DSPEx.Adapter.Selector, as: AdapterSelector
  alias DSPEx.Reasoning.Selector, as: ReasoningSelector
  alias DSPEx.Variable.Evaluator

  def optimize_program_configuration(program, training_data, metric_fn, opts \\ []) do
    # Analyze program requirements
    program_analysis = analyze_program_requirements(program, training_data)
    
    # Generate candidate configurations
    configurations = generate_candidate_configurations(program_analysis, opts)
    
    # Evaluate configurations empirically
    evaluated_configs = evaluate_configurations(program, training_data, metric_fn, configurations)
    
    # Select optimal configuration
    optimal_config = select_optimal_configuration(evaluated_configs, opts)
    
    # Apply configuration to program
    optimized_program = apply_configuration(program, optimal_config)
    
    {:ok, optimized_program, optimal_config}
  end

  defp generate_candidate_configurations(program_analysis, opts) do
    max_candidates = Keyword.get(opts, :max_candidates, 12)
    
    # Generate systematic combinations
    systematic_configs = generate_systematic_combinations(program_analysis)
    
    # Add exploratory configurations
    exploratory_configs = generate_exploratory_configurations(program_analysis)
    
    # Combine and limit
    (systematic_configs ++ exploratory_configs)
    |> Enum.take(max_candidates)
    |> Enum.uniq()
  end

  defp generate_systematic_combinations(program_analysis) do
    adapters = select_top_adapters(program_analysis, 2)
    reasoning_modules = select_top_reasoning_modules(program_analysis, 3)
    
    for adapter <- adapters, reasoning <- reasoning_modules do
      %{
        adapter: adapter,
        reasoning_module: reasoning,
        configuration_type: :systematic
      }
    end
  end

  defp generate_exploratory_configurations(program_analysis) do
    # Generate some "wild card" configurations that might work well
    [
      %{adapter: :json_tool, reasoning_module: :react, configuration_type: :exploratory},
      %{adapter: :markdown_tool, reasoning_module: :program_of_thought, configuration_type: :exploratory},
      %{adapter: :structured_text, reasoning_module: :chain_of_thought, configuration_type: :exploratory}
    ]
  end

  defp evaluate_configurations(program, training_data, metric_fn, configurations) do
    configurations
    |> Task.async_stream(fn config ->
      evaluate_single_configuration(program, training_data, metric_fn, config)
    end, max_concurrency: 4, timeout: 30_000)
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp evaluate_single_configuration(program, training_data, metric_fn, config) do
    # Apply configuration
    configured_program = apply_temporary_configuration(program, config)
    
    # Run subset of training data for efficiency
    sample_size = min(5, length(training_data))
    sample_data = Enum.take_random(training_data, sample_size)
    
    # Measure performance
    start_time = System.monotonic_time(:millisecond)
    
    results = Enum.map(sample_data, fn example ->
      try do
        output = configured_program.forward(example.inputs)
        score = metric_fn.(output, example.outputs)
        {:ok, score}
      catch
        error -> {:error, error}
      end
    end)
    
    end_time = System.monotonic_time(:millisecond)
    
    # Calculate metrics
    successful_results = Enum.filter(results, fn {status, _} -> status == :ok end)
    accuracy = if length(successful_results) > 0 do
      successful_results
      |> Enum.map(fn {:ok, score} -> score end)
      |> Enum.sum()
      |> Kernel./(length(successful_results))
    else
      0.0
    end
    
    %{
      configuration: config,
      accuracy: accuracy,
      success_rate: length(successful_results) / length(results),
      average_latency: (end_time - start_time) / length(sample_data),
      estimated_cost: estimate_configuration_cost(config, sample_data),
      errors: Enum.filter(results, fn {status, _} -> status == :error end)
    }
  end

  defp select_optimal_configuration(evaluated_configs, opts) do
    optimization_criteria = Keyword.get(opts, :optimization_criteria, [:accuracy, :cost, :latency])
    weights = Keyword.get(opts, :criteria_weights, %{accuracy: 0.6, cost: 0.2, latency: 0.2})
    
    evaluated_configs
    |> Enum.map(fn config ->
      composite_score = calculate_composite_score(config, optimization_criteria, weights)
      Map.put(config, :composite_score, composite_score)
    end)
    |> Enum.max_by(fn config -> config.composite_score end)
  end

  defp calculate_composite_score(config, criteria, weights) do
    Enum.reduce(criteria, 0.0, fn criterion, acc ->
      weight = Map.get(weights, criterion, 1.0 / length(criteria))
      score = normalize_criterion_score(config, criterion)
      acc + (weight * score)
    end)
  end

  defp normalize_criterion_score(config, :accuracy), do: config.accuracy
  defp normalize_criterion_score(config, :cost), do: 1.0 / (config.estimated_cost + 0.01)
  defp normalize_criterion_score(config, :latency), do: 1.0 / (config.average_latency + 1.0)
  defp normalize_criterion_score(config, :success_rate), do: config.success_rate
end
```

### 5. Integration with Variable System

```elixir
defmodule DSPEx.Module.VariableIntegration do
  @moduledoc """
  Integrates module selection with the Variable abstraction system
  """

  def create_module_selection_variables(program_analysis) do
    # Create adapter selection variable
    adapter_variable = DSPEx.Variable.choice(
      :adapter, 
      [:json_tool, :markdown_tool, :structured_text],
      description: "Output format adapter selection"
    )
    
    # Create reasoning module variable
    reasoning_variable = DSPEx.Variable.choice(
      :reasoning_module,
      [:predict, :chain_of_thought, :program_of_thought, :react],
      description: "Reasoning strategy selection"
    )
    
    # Create conditional variables based on selections
    temperature_variable = DSPEx.Variable.Conditional.define_conditional_variable(
      :reasoning_temperature,
      :reasoning_module, :chain_of_thought,
      DSPEx.Variable.float(:temperature, range: {0.3, 1.2}),
      DSPEx.Variable.float(:temperature, range: {0.1, 0.8})
    )
    
    [adapter_variable, reasoning_variable, temperature_variable]
  end

  def integrate_with_optimizers do
    # Update SIMBA to include module selection
    # Update BEACON to optimize over module choices
    # Add module selection to all existing optimizers
  end
end
```

## Usage Examples

### 1. Automatic Adapter Selection

```elixir
# Define program with automatic adapter selection
program = DSPEx.Predict.new(MySignature)
  |> DSPEx.Module.SelectionOrchestrator.enable_auto_selection()

# Training will automatically find best adapter
{:ok, optimized, config} = DSPEx.Teleprompter.SIMBA.compile(
  program, training_data, metric_fn
)

# View selected configuration
IO.inspect(config.adapter)  # => :json_tool (or :markdown_tool, etc.)
```

### 2. Multi-Objective Optimization

```elixir
# Optimize for accuracy, cost, and latency
{:ok, optimized, config} = DSPEx.Module.SelectionOrchestrator.optimize_program_configuration(
  program, training_data, metric_fn,
  optimization_criteria: [:accuracy, :cost, :latency],
  criteria_weights: %{accuracy: 0.5, cost: 0.3, latency: 0.2}
)
```

### 3. Constraint-Based Selection

```elixir
# Only consider fast, cheap options
{:ok, optimized, config} = DSPEx.Module.SelectionOrchestrator.optimize_program_configuration(
  program, training_data, metric_fn,
  constraints: %{
    max_latency_ms: 1000,
    max_cost_per_call: 0.01,
    min_accuracy: 0.8
  }
)
```

## Performance Characteristics

### Expected Performance Improvements
- **Accuracy**: 5-15% improvement through optimal module selection
- **Cost Efficiency**: 20-40% cost reduction through appropriate module matching
- **Latency**: 10-30% latency improvement through complexity matching

### Overhead Analysis
- **Selection Overhead**: 2-5 minutes during optimization phase
- **Runtime Overhead**: <1ms per forward pass (cached selections)
- **Memory Overhead**: <10MB for module registry and cached configurations

## Testing Strategy

### 1. Benchmark Suite
```elixir
defmodule DSPEx.Module.BenchmarkSuite do
  def run_comprehensive_benchmarks do
    # Test across different task types
    test_cases = [
      simple_qa_tasks(),
      complex_reasoning_tasks(),
      computational_tasks(),
      structured_output_tasks(),
      multi_step_tasks()
    ]
    
    # Run with all module combinations
    results = run_benchmark_matrix(test_cases)
    
    # Analyze patterns
    analyze_performance_patterns(results)
  end
end
```

### 2. A/B Testing Framework
```elixir
defmodule DSPEx.Module.ABTest do
  def compare_selection_strategies(program, training_data, metric_fn) do
    # Manual selection baseline
    manual_results = run_with_manual_selection(program, training_data, metric_fn)
    
    # Automatic selection
    auto_results = run_with_auto_selection(program, training_data, metric_fn)
    
    # Statistical significance testing
    calculate_significance(manual_results, auto_results)
  end
end
```

This framework provides a comprehensive solution for intelligent adapter and module selection, addressing the core question of optimal configuration discovery while maintaining flexibility and extensibility for future module types.