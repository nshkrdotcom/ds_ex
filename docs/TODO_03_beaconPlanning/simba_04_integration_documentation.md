# DSPEx BEACON Integration - Complete Documentation

## Overview

This document provides comprehensive documentation for integrating DSPy.BEACON into your existing DSPEx Elixir codebase. The integration includes a full BEACON teleprompter implementation, Bayesian optimization engine, and extensive examples.

## Architecture

### Core Components

```
DSPEx.Teleprompter.BEACON
├── Main teleprompter implementation
├── Bayesian optimization engine
├── Instruction generation pipeline
├── Demonstration bootstrapping
└── Progress tracking and telemetry

DSPEx.Teleprompter.BEACON.BayesianOptimizer
├── Gaussian Process surrogate modeling
├── Acquisition functions (EI, UCB, PI)
├── Configuration space exploration
└── Convergence detection

DSPEx.Teleprompter.BEACON.Examples
├── Usage examples and patterns
├── Test cases and benchmarks
└── Performance analysis tools
```

### Integration Points

1. **Foundation Services**: Integrated with your existing Foundation telemetry and configuration
2. **DSPEx Programs**: Compatible with all DSPEx.Program implementations
3. **Client Management**: Uses existing DSPEx.Client infrastructure
4. **Telemetry**: Comprehensive telemetry events for monitoring and debugging

## Installation and Setup

### 1. Add BEACON Files to Your Codebase

Place the following files in your DSPEx project:

```
lib/dspex/teleprompter/
├── beacon.ex                    # Main BEACON implementation
├── beacon/
│   ├── bayesian_optimizer.ex   # Bayesian optimization engine
│   ├── examples.ex            # Usage examples
│   └── benchmark.ex           # Performance benchmarks
└── beacon_test.exs             # Test suite
```

### 2. Update Dependencies

Ensure your `mix.exs` includes necessary dependencies:

```elixir
defp deps do
  [
    # Existing dependencies...
    {:req, "~> 0.4.0"},              # HTTP client
    {:jason, "~> 1.4"},             # JSON handling
    {:telemetry, "~> 1.2"},         # Telemetry
    {:foundation, "~> 0.1.3"},      # Your foundation library
    
    # Optional for advanced mathematics
    {:nx, "~> 0.6", optional: true}, # Numerical computing
  ]
end
```

### 3. Configuration

Add BEACON-specific configuration to your application config:

```elixir
# config/config.exs
config :dspex,
  teleprompters: %{
    beacon: %{
      default_instruction_model: :openai,
      default_evaluation_model: :gemini,
      max_concurrent_operations: 20,
      default_timeout: 60_000,
      cache_enabled: true,
      telemetry_detailed: false
    }
  }

# config/dev.exs
config :dspex,
  teleprompters: %{
    beacon: %{
      telemetry_detailed: true,
      max_concurrent_operations: 10,  # Reduced for development
      default_timeout: 30_000
    }
  }

# config/test.exs
config :dspex,
  teleprompters: %{
    beacon: %{
      max_concurrent_operations: 5,
      default_timeout: 5_000,
      cache_enabled: false
    }
  }
```

## Basic Usage

### Quick Start Example

```elixir
# Define your signature
defmodule MySignature do
  @moduledoc "Answer questions with detailed explanations"
  use DSPEx.Signature, "question -> answer, explanation"
end

# Create student and teacher programs
student = DSPEx.Predict.new(MySignature, :gemini)
teacher = DSPEx.Predict.new(MySignature, :openai)

# Prepare training data
trainset = [
  DSPEx.Example.new(%{
    question: "What is photosynthesis?",
    answer: "The process by which plants convert light into energy",
    explanation: "Plants use chlorophyll to capture sunlight and convert CO2 and water into glucose and oxygen"
  }, [:question]),
  # Add more examples...
]

# Define evaluation metric
metric_fn = fn example, prediction ->
  expected = DSPEx.Example.outputs(example)
  
  answer_match = if expected.answer == prediction.answer, do: 0.7, else: 0.0
  explanation_quality = similarity_score(expected.explanation, prediction.explanation) * 0.3
  
  answer_match + explanation_quality
end

# Create and configure BEACON
teleprompter = DSPEx.Teleprompter.BEACON.new(
  num_candidates: 20,
  max_bootstrapped_demos: 4,
  num_trials: 40,
  quality_threshold: 0.75
)

# Optimize the program
{:ok, optimized_student} = teleprompter.compile(
  student, 
  teacher, 
  trainset, 
  metric_fn
)

# Use the optimized program
{:ok, result} = DSPEx.Program.forward(optimized_student, %{
  question: "How do vaccines work?"
})
```

## Advanced Configuration

### Custom Bayesian Optimizer

```elixir
# Configure BEACON with custom Bayesian optimization
teleprompter = DSPEx.Teleprompter.BEACON.new(
  # Core BEACON parameters
  num_candidates: 30,
  max_bootstrapped_demos: 6,
  num_trials: 75,
  quality_threshold: 0.8,
  
  # Performance tuning
  max_concurrency: 25,
  timeout: 120_000,
  teacher_retries: 3,
  
  # Model selection
  instruction_model: :openai,
  evaluation_model: :gemini,
  
  # Progress monitoring
  progress_callback: &custom_progress_handler/1
)

defp custom_progress_handler(progress) do
  case progress.phase do
    :bootstrap_generation ->
      Logger.info("Bootstrap: #{progress.completed}/#{progress.total}")
    
    :bayesian_optimization ->
      Logger.info("Trial #{progress.trial}: Score #{progress.current_score}")
    
    _ ->
      Logger.debug("Phase #{progress.phase}: #{inspect(progress)}")
  end
end
```

### Multi-Objective Optimization

```elixir
# Create metric that optimizes for multiple objectives
multi_objective_metric = fn example, prediction ->
  expected = DSPEx.Example.outputs(example)
  
  # Accuracy (50%)
  accuracy = exact_match_score(expected, prediction) * 0.5
  
  # Relevance (30%)
  relevance = semantic_similarity(expected, prediction) * 0.3
  
  # Brevity (20% - prefer concise answers)
  brevity = brevity_score(prediction) * 0.2
  
  accuracy + relevance + brevity
end
```

## Integration with Existing DSPEx Components

### Using with Custom Programs

```elixir
defmodule CustomReasoningProgram do
  use DSPEx.Program
  
  defstruct [:reasoning_step, :answer_step, :demos, :instruction]
  
  @impl DSPEx.Program
  def forward(program, inputs, _opts) do
    # Multi-step reasoning implementation
    with {:ok, reasoning} <- DSPEx.Program.forward(program.reasoning_step, inputs),
         enriched_inputs = Map.merge(inputs, reasoning),
         {:ok, answer} <- DSPEx.Program.forward(program.answer_step, enriched_inputs) do
      {:ok, answer}
    end
  end
end

# BEACON can optimize complex programs
student = %CustomReasoningProgram{
  reasoning_step: DSPEx.Predict.new(ReasoningSignature, :gemini),
  answer_step: DSPEx.Predict.new(AnswerSignature, :gemini),
  demos: [],
  instruction: nil
}

teacher = %CustomReasoningProgram{
  reasoning_step: DSPEx.Predict.new(ReasoningSignature, :openai),
  answer_step: DSPEx.Predict.new(AnswerSignature, :openai),
  demos: [],
  instruction: nil
}

{:ok, optimized} = teleprompter.compile(student, teacher, trainset, metric_fn)
```

### Integration with Foundation Services

```elixir
# BEACON automatically integrates with Foundation telemetry
:telemetry.attach(
  "beacon-monitoring",
  [:dspex, :teleprompter, :beacon, :stop],
  fn event, measurements, metadata, _config ->
    # Custom monitoring logic
    Foundation.Metrics.increment("beacon.optimizations.completed")
    Foundation.Metrics.histogram("beacon.optimization.duration", measurements.duration)
    
    # Log optimization results
    Foundation.Logger.info("BEACON optimization completed", %{
      correlation_id: metadata.correlation_id,
      duration_ms: measurements.duration,
      success: measurements.success
    })
  end,
  nil
)
```

## Performance Optimization

### Tuning for Different Scales

```elixir
# Small datasets (< 50 examples)
small_scale_config = DSPEx.Teleprompter.BEACON.new(
  num_candidates: 10,
  max_bootstrapped_demos: 3,
  num_trials: 25,
  max_concurrency: 10,
  timeout: 30_000
)

# Medium datasets (50-200 examples)
medium_scale_config = DSPEx.Teleprompter.BEACON.new(
  num_candidates: 20,
  max_bootstrapped_demos: 4,
  num_trials: 50,
  max_concurrency: 20,
  timeout: 60_000
)

# Large datasets (200+ examples)
large_scale_config = DSPEx.Teleprompter.BEACON.new(
  num_candidates: 30,
  max_bootstrapped_demos: 6,
  num_trials: 75,
  max_concurrency: 30,
  timeout: 120_000
)
```

### Memory Management

```elixir
# Configure BEACON for memory-efficient operation
memory_efficient_config = DSPEx.Teleprompter.BEACON.new(
  # Reduce concurrent operations
  max_concurrency: 10,
  
  # Limit demonstration count
  max_bootstrapped_demos: 3,
  max_labeled_demos: 10,
  
  # Use streaming evaluation for large datasets
  evaluation_batch_size: 20,
  
  # Enable garbage collection hints
  gc_after_trials: 10
)
```

## Testing and Validation

### Unit Tests

```elixir
defmodule MyApp.BEACONIntegrationTest do
  use ExUnit.Case, async: false
  
  alias DSPEx.Teleprompter.BEACON
  
  setup do
    # Setup test data
    %{
      student: create_test_student(),
      teacher: create_test_teacher(),
      trainset: create_test_trainset(),
      metric_fn: &test_metric/2
    }
  end
  
  test "BEACON optimization completes successfully", context do
    teleprompter = BEACON.new(
      num_candidates: 3,
      num_trials: 5,
      timeout: 10_000
    )
    
    {:ok, optimized} = teleprompter.compile(
      context.student,
      context.teacher,
      context.trainset,
      context.metric_fn
    )
    
    assert is_struct(optimized)
    
    # Test that optimized program works
    {:ok, result} = DSPEx.Program.forward(optimized, %{input: "test"})
    assert Map.has_key?(result, :output)
  end
end
```

### Integration Tests

```elixir
defmodule MyApp.BEACONIntegrationTest do
  use ExUnit.Case, async: false
  
  @moduletag :integration
  
  test "end-to-end BEACON optimization with real models" do
    # This test requires actual API keys and network access
    if System.get_env("INTEGRATION_TESTS") == "true" do
      run_full_integration_test()
    else
      ExUnit.skip("Integration tests disabled")
    end
  end
end
```

## Monitoring and Debugging

### Telemetry Events

BEACON emits the following telemetry events:

```elixir
# Main optimization events
[:dspex, :teleprompter, :beacon, :start]
[:dspex, :teleprompter, :beacon, :stop]

# Bootstrap generation events
[:dspex, :teleprompter, :beacon, :bootstrap, :start]
[:dspex, :teleprompter, :beacon, :bootstrap, :stop]

# Instruction generation events
[:dspex, :teleprompter, :beacon, :instructions, :start]
[:dspex, :teleprompter, :beacon, :instructions, :stop]

# Bayesian optimization events
[:dspex, :teleprompter, :beacon, :optimization, :start]
[:dspex, :teleprompter, :beacon, :optimization, :stop]

# Individual Bayesian optimizer events
[:dspex, :beacon, :bayesian_optimizer, :start]
[:dspex, :beacon, :bayesian_optimizer, :stop]
[:dspex, :beacon, :bayesian_optimizer, :iteration]
```

### Progress Monitoring

```elixir
defmodule MyApp.BEACONMonitor do
  def setup_monitoring do
    # Real-time progress tracking
    progress_callback = fn progress ->
      case progress.phase do
        :bootstrap_generation ->
          update_progress_bar("Bootstrap", progress.completed, progress.total)
        
        :bayesian_optimization ->
          log_optimization_trial(progress.trial, progress.current_score)
        
        _ ->
          log_generic_progress(progress)
      end
    end
    
    # Telemetry-based monitoring
    :telemetry.attach_many(
      "beacon-monitor",
      [
        [:dspex, :teleprompter, :beacon, :stop],
        [:dspex, :beacon, :bayesian_optimizer, :iteration]
      ],
      &handle_telemetry_event/4,
      %{}
    )
    
    progress_callback
  end
  
  defp handle_telemetry_event([:dspex, :teleprompter, :beacon, :stop], measurements, metadata, _) do
    # Log completion metrics
    MyApp.Metrics.record_optimization_completion(%{
      duration: measurements.duration,
      success: measurements.success,
      correlation_id: metadata.correlation_id
    })
  end
  
  defp handle_telemetry_event([:dspex, :beacon, :bayesian_optimizer, :iteration], measurements, metadata, _) do
    # Track optimization progress
    MyApp.Metrics.record_optimization_iteration(%{
      iteration: measurements.iteration,
      score: measurements.score,
      improvement: measurements.improvement,
      correlation_id: metadata.correlation_id
    })
  end
end
```

## Best Practices

### 1. Metric Design

```elixir
# Good: Comprehensive metric with multiple criteria
good_metric = fn example, prediction ->
  expected = DSPEx.Example.outputs(example)
  
  # Primary objective (60%)
  primary_score = primary_evaluation(expected, prediction) * 0.6
  
  # Secondary objectives (40%)
  relevance_score = relevance_evaluation(expected, prediction) * 0.25
  quality_score = quality_evaluation(prediction) * 0.15
  
  primary_score + relevance_score + quality_score
end

# Avoid: Overly simplistic metrics
avoid_metric = fn example, prediction ->
  expected = DSPEx.Example.outputs(example)
  if expected.answer == prediction.answer, do: 1.0, else: 0.0
end
```

### 2. Training Data Quality

```elixir
# Ensure diverse, high-quality training examples
defp validate_trainset(trainset) do
  # Check diversity
  input_diversity = calculate_input_diversity(trainset)
  output_diversity = calculate_output_diversity(trainset)
  
  # Check quality
  quality_scores = Enum.map(trainset, &assess_example_quality/1)
  avg_quality = Enum.sum(quality_scores) / length(quality_scores)
  
  cond do
    length(trainset) < 10 ->
      {:error, "Trainset too small (minimum 10 examples)"}
    
    input_diversity < 0.5 ->
      {:error, "Insufficient input diversity"}
    
    avg_quality < 0.7 ->
      {:error, "Low average example quality"}
    
    true ->
      :ok
  end
end
```

### 3. Error Handling

```elixir
defp robust_beacon_compilation(student, teacher, trainset, metric_fn) do
  try do
    teleprompter = DSPEx.Teleprompter.BEACON.new(
      num_candidates: 20,
      num_trials: 40,
      timeout: 60_000,
      teacher_retries: 3
    )
    
    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized} ->
        # Validate optimized program
        case validate_optimized_program(optimized, trainset) do
          :ok -> {:ok, optimized}
          {:error, reason} -> {:error, {:validation_failed, reason}}
        end
      
      {:error, reason} ->
        # Log error and potentially retry with different configuration
        Logger.warning("BEACON optimization failed: #{inspect(reason)}")
        
        case reason do
          :no_successful_bootstrap_candidates ->
            retry_with_relaxed_config(student, teacher, trainset, metric_fn)
          
          _ ->
            {:error, reason}
        end
    end
  rescue
    exception ->
      Logger.error("BEACON compilation crashed: #{Exception.format(:error, exception)}")
      {:error, {:crashed, exception}}
  end
end
```

## Troubleshooting

### Common Issues

1. **No Bootstrap Candidates Generated**
   ```elixir
   # Solution: Reduce quality threshold or increase retries
   teleprompter = BEACON.new(
     quality_threshold: 0.5,  # Lower threshold
     teacher_retries: 5,      # More retries
     timeout: 90_000          # Longer timeout
   )
   ```

2. **Slow Optimization**
   ```elixir
   # Solution: Reduce search space or increase concurrency
   teleprompter = BEACON.new(
     num_candidates: 15,      # Fewer candidates
     num_trials: 30,          # Fewer trials
     max_concurrency: 25      # More concurrency
   )
   ```

3. **Memory Issues**
   ```elixir
   # Solution: Reduce batch sizes and enable streaming
   teleprompter = BEACON.new(
     max_concurrency: 10,     # Lower concurrency
     max_bootstrapped_demos: 3, # Fewer demos
     evaluation_batch_size: 10  # Smaller batches
   )
   ```

### Debug Mode

```elixir
# Enable detailed logging for debugging
teleprompter = DSPEx.Teleprompter.BEACON.new(
  progress_callback: fn progress ->
    IO.inspect(progress, label: "BEACON Progress")
    :ok
  end
)

# Set log level for detailed output
Logger.configure(level: :debug)
```

## Performance Benchmarks

Expected performance characteristics:

| Dataset Size | Candidates | Trials | Typical Duration | Memory Usage |
|-------------|------------|--------|------------------|--------------|
| 10-50       | 10         | 25     | 2-5 minutes      | 50-100 MB    |
| 50-100      | 20         | 40     | 5-15 minutes     | 100-200 MB   |
| 100-200     | 25         | 50     | 15-30 minutes    | 200-400 MB   |
| 200+        | 30         | 75     | 30-60 minutes    | 400-800 MB   |

## Migration from Python DSPy

### Key Differences

1. **Concurrency**: Elixir implementation uses Task.async_stream for better concurrency
2. **Error Handling**: Pattern matching and explicit error handling
3. **Telemetry**: Built-in telemetry integration with Foundation
4. **Configuration**: Structured configuration through DSPEx.Services.ConfigManager

### Migration Checklist

- [ ] Convert Python signatures to DSPEx.Signature modules
- [ ] Adapt metric functions to Elixir patterns
- [ ] Update progress callbacks to use Elixir patterns
- [ ] Configure telemetry monitoring
- [ ] Test with smaller datasets first
- [ ] Validate optimization results

## Future Enhancements

Planned improvements for the BEACON integration:

1. **Advanced Bayesian Optimization**
   - Multi-fidelity optimization
   - Constrained optimization
   - Multi-objective Pareto optimization

2. **Distributed Optimization**
   - Cluster-aware optimization
   - Work distribution across nodes
   - Fault-tolerant optimization

3. **Advanced Metrics**
   - Semantic similarity using embeddings
   - LLM-based evaluation metrics
   - Custom metric composition DSL

4. **Performance Optimizations**
   - Streaming evaluation for large datasets
   - Incremental optimization
   - Caching and memoization

## Support and Contributing

For issues, questions, or contributions:

1. Check the test suite for usage patterns
2. Review telemetry events for debugging
3. Use the benchmark module for performance analysis
4. Follow the existing code patterns and documentation standards

The BEACON integration follows DSPEx's architectural patterns and integrates seamlessly with your existing Foundation-based infrastructure.
