# DSPy SIMBA Implementation Plan for DSPEx

## Executive Summary

This document outlines the implementation of DSPy's SIMBA (Stochastic Introspective Mini-Batch Ascent) algorithm in DSPEx. Unlike the current DSPEx "SIMBA" which is actually a Bayesian optimizer, this implementation will faithfully reproduce the stochastic hill-climbing algorithm from the original DSPy library.

## 1. Algorithm Overview

### DSPy SIMBA Core Concepts

**SIMBA** = **S**tochastic **I**ntrospective **M**ini-**B**atch **A**scent

The algorithm follows this pattern:
1. **Trajectory Sampling**: Run programs with different configurations on mini-batches
2. **Bucket Analysis**: Group execution traces by performance quality
3. **Strategy Application**: Use simple strategies to create new candidate programs
4. **Selection**: Keep the best performing candidates and iterate

### Key Differences from Current DSPEx Implementation

| Current DSPEx "SIMBA" | True DSPy SIMBA |
|----------------------|-----------------|
| Bayesian optimization with acquisition functions | Stochastic hill-climbing with trajectory analysis |
| Instruction generation via LLM | Demo-based optimization primarily |
| Gaussian Process surrogate models | Simple performance-based selection |
| Complex mathematical optimization | Heuristic strategy application |

## 2. Technical Design

### 2.1 Core Architecture

```
DSPEx.Teleprompter.SIMBA
├── Core Algorithm Loop
├── Trajectory Sampling
├── Bucket Analysis
├── Strategy System
└── Performance Tracking
```

### 2.2 Key Components

#### A. Trajectory Management
- **Trajectory**: A complete execution trace through a program
- **Bucket**: Collections of trajectories grouped by performance
- **Strategy**: Rules for creating new programs from successful trajectories

#### B. Strategy System
The heart of SIMBA - simple rules that create program variants:
- `append_a_demo`: Add successful input/output pairs as demonstrations
- `modify_instruction`: Adjust program instructions based on performance feedback
- `prune_demos`: Remove underperforming demonstrations
- Custom strategies for specific use cases

#### C. Performance Evaluation
- Mini-batch based evaluation for efficiency
- Score-based trajectory ranking
- Statistical analysis of improvement patterns

### 2.3 Data Structures

```elixir
# Trajectory representation
%Trajectory{
  program: %DSPEx.Program{},
  inputs: map(),
  outputs: map(),
  trace: [step],
  score: float(),
  metadata: map()
}

# Bucket for grouping trajectories
%Bucket{
  trajectories: [%Trajectory{}],
  performance_stats: %{min: float(), max: float(), avg: float()},
  strategy_applicable: boolean()
}

# Strategy definition
%Strategy{
  name: atom(),
  apply_fn: function(),
  conditions: [condition],
  priority: integer()
}
```

## 3. Implementation Guide

### 3.1 Module Structure

```
dspex/teleprompter/
├── simba_v2.ex                    # Main SIMBA algorithm
├── simba_v2/
│   ├── trajectory.ex              # Trajectory management
│   ├── bucket.ex                  # Bucket analysis
│   ├── strategy.ex                # Strategy system
│   ├── strategies/
│   │   ├── append_demo.ex         # Demo addition strategy
│   │   ├── modify_instruction.ex  # Instruction modification
│   │   └── prune_demos.ex         # Demo pruning
│   ├── performance.ex             # Performance tracking
│   └── utils.ex                   # Utility functions
```

### 3.2 Configuration Options

```elixir
%SIMBA{
  bsize: 32,                    # Mini-batch size
  num_candidates: 6,            # Candidate programs per iteration
  max_steps: 8,                 # Maximum optimization steps
  max_demos: 4,                 # Maximum demos per predictor
  strategies: [:append_demo, :modify_instruction],
  temperature_sampling: 0.2,    # Temperature for program selection
  temperature_candidates: 0.2   # Temperature for candidate generation
}
```

## 4. Core Algorithm Implementation

### 4.1 Main SIMBA Loop

```elixir
def compile(teleprompter, student, teacher, trainset, metric_fn, opts) do
  # Initialize
  correlation_id = generate_correlation_id()
  programs = [student]  # Start with baseline
  program_scores = %{}
  
  # Data shuffling for mini-batch processing
  shuffled_data = Enum.shuffle(trainset)
  
  for step <- 1..teleprompter.max_steps do
    # Step 1: Get next mini-batch
    batch = get_next_batch(shuffled_data, step, teleprompter.bsize)
    
    # Step 2: Sample trajectories
    trajectories = sample_trajectories(programs, batch, teleprompter)
    
    # Step 3: Create buckets
    buckets = create_buckets(trajectories, metric_fn)
    
    # Step 4: Apply strategies
    new_candidates = apply_strategies(buckets, teleprompter.strategies)
    
    # Step 5: Evaluate candidates
    candidate_scores = evaluate_candidates(new_candidates, batch, metric_fn)
    
    # Step 6: Update program pool
    programs = update_programs(programs, new_candidates, candidate_scores)
    program_scores = update_scores(program_scores, candidate_scores)
  end
  
  # Return best program
  best_program = select_best_program(programs, program_scores)
  {:ok, best_program}
end
```

### 4.2 Trajectory Sampling

```elixir
defp sample_trajectories(programs, batch, teleprompter) do
  # For each example in batch, for each candidate model variant
  for example <- batch,
      {program, model_config} <- prepare_program_variants(programs, teleprompter) do
    
    # Execute program with tracing
    case execute_with_trace(program, example, model_config) do
      {:ok, outputs, trace} ->
        score = teleprompter.metric_fn.(example, outputs)
        
        %Trajectory{
          program: program,
          inputs: DSPEx.Example.inputs(example),
          outputs: outputs,
          trace: trace,
          score: score,
          metadata: %{
            model_config: model_config,
            example_id: example.id
          }
        }
        
      {:error, _reason} ->
        # Create failed trajectory
        %Trajectory{
          program: program,
          inputs: DSPEx.Example.inputs(example),
          outputs: %{},
          trace: [],
          score: 0.0,
          metadata: %{failed: true}
        }
    end
  end
end
```

### 4.3 Bucket Creation

```elixir
defp create_buckets(trajectories, metric_fn) do
  # Group trajectories by example
  trajectories_by_example = Enum.group_by(trajectories, &(&1.metadata.example_id))
  
  Enum.map(trajectories_by_example, fn {_example_id, example_trajectories} ->
    # Sort by score (highest first)
    sorted = Enum.sort_by(example_trajectories, &(-&1.score))
    
    # Calculate statistics
    scores = Enum.map(sorted, &(&1.score))
    max_score = Enum.max(scores)
    min_score = Enum.min(scores)
    avg_score = Enum.sum(scores) / length(scores)
    
    # Determine if bucket shows improvement potential
    max_to_min_gap = max_score - min_score
    max_to_avg_gap = max_score - avg_score
    
    %Bucket{
      trajectories: sorted,
      performance_stats: %{
        min: min_score,
        max: max_score,
        avg: avg_score,
        max_to_min_gap: max_to_min_gap,
        max_to_avg_gap: max_to_avg_gap
      },
      strategy_applicable: max_to_min_gap > 0.1  # Threshold for strategy application
    }
  end)
  |> Enum.sort_by(&(-&1.performance_stats.max_to_min_gap))  # Best buckets first
end
```

### 4.4 Strategy Application

```elixir
defmodule DSPEx.Teleprompter.SIMBA.Strategies.AppendDemo do
  @behaviour DSPEx.Teleprompter.SIMBA.Strategy
  
  def apply(bucket, source_program, _opts) do
    # Get the best trajectory from the bucket
    best_trajectory = List.first(bucket.trajectories)
    
    if best_trajectory.score > 0.7 do  # Quality threshold
      # Create new demo from successful trajectory
      demo = DSPEx.Example.new(
        Map.merge(best_trajectory.inputs, best_trajectory.outputs),
        Map.keys(best_trajectory.inputs)
      )
      
      # Add demo to program
      case source_program do
        %{demos: existing_demos} ->
          new_demos = [demo | existing_demos] |> Enum.take(4)  # Limit demos
          {:ok, %{source_program | demos: new_demos}}
          
        _ ->
          # Wrap with OptimizedProgram if needed
          {:ok, DSPEx.OptimizedProgram.new(source_program, [demo])}
      end
    else
      {:skip, "Trajectory score too low for demo creation"}
    end
  end
end
```

## 5. Testing Strategy

### 5.1 Unit Tests

```elixir
defmodule DSPEx.Teleprompter.SIMBATest do
  use ExUnit.Case
  
  describe "trajectory sampling" do
    test "creates trajectories for each example-program pair" do
      # Test trajectory creation
    end
    
    test "handles program execution failures gracefully" do
      # Test error handling
    end
  end
  
  describe "bucket analysis" do
    test "groups trajectories by performance correctly" do
      # Test bucket creation logic
    end
    
    test "calculates performance statistics accurately" do
      # Test stats calculation
    end
  end
  
  describe "strategy application" do
    test "append_demo strategy adds successful examples" do
      # Test demo addition
    end
    
    test "strategies respect quality thresholds" do
      # Test quality gating
    end
  end
end
```

### 5.2 Integration Tests

```elixir
defmodule DSPEx.Teleprompter.SIMBAIntegrationTest do
  use ExUnit.Case
  
  test "end-to-end optimization improves program performance" do
    # Create test signature, program, and dataset
    # Run SIMBA optimization
    # Verify improvement
  end
  
  test "handles various program types correctly" do
    # Test with different DSPEx.Program implementations
  end
end
```

## 6. Performance Considerations

### 6.1 Optimization Targets

- **Trajectory Sampling**: Use Task.async_stream for concurrent execution
- **Bucket Analysis**: Optimize sorting and grouping operations
- **Strategy Application**: Cache expensive computations
- **Memory Management**: Limit trajectory storage and implement cleanup

### 6.2 Telemetry Integration

```elixir
# Emit telemetry events throughout the algorithm
:telemetry.execute([:dspex, :simba, :trajectory, :sampled], measurements, metadata)
:telemetry.execute([:dspex, :simba, :bucket, :created], measurements, metadata)
:telemetry.execute([:dspex, :simba, :strategy, :applied], measurements, metadata)
```

## 7. Migration Plan

### 7.1 Renaming Current Implementation

1. Rename current `DSPEx.Teleprompter.SIMBA` to `DSPEx.Teleprompter.BayesianOptimizer`
2. Update all references and documentation
3. Preserve existing functionality for backward compatibility

### 7.2 Implementation Phases

**Phase 1**: Core Algorithm (Week 1-2)
- Implement main SIMBA loop
- Basic trajectory sampling
- Simple bucket analysis

**Phase 2**: Strategy System (Week 2-3)
- Implement core strategies
- Strategy registration and dispatch
- Performance optimization

**Phase 3**: Integration & Testing (Week 3-4)
- Comprehensive testing
- Performance tuning
- Documentation updates

**Phase 4**: Advanced Features (Week 4+)
- Custom strategy development
- Advanced trajectory analysis
- Production optimizations

## 8. Examples and Usage

### 8.1 Basic Usage

```elixir
# Create SIMBA teleprompter
teleprompter = DSPEx.Teleprompter.SIMBA.new(
  bsize: 32,
  num_candidates: 6,
  max_steps: 8,
  strategies: [:append_demo, :modify_instruction]
)

# Optimize program
{:ok, optimized} = teleprompter.compile(
  student_program,
  teacher_program,
  training_examples,
  metric_fn
)
```

### 8.2 Custom Strategy Example

```elixir
defmodule MyCustomStrategy do
  @behaviour DSPEx.Teleprompter.SIMBA.Strategy
  
  def apply(bucket, source_program, opts) do
    # Custom optimization logic
    # Return {:ok, new_program} or {:skip, reason}
  end
end

# Use custom strategy
teleprompter = DSPEx.Teleprompter.SIMBA.new(
  strategies: [:append_demo, MyCustomStrategy]
)
```

## 9. Success Metrics

### 9.1 Functional Correctness
- [ ] Algorithm produces improving programs over iterations
- [ ] Trajectory sampling captures execution details correctly
- [ ] Bucket analysis identifies performance patterns
- [ ] Strategies create meaningful program variants

### 9.2 Performance Benchmarks
- [ ] Optimization completes within reasonable time bounds
- [ ] Memory usage remains within acceptable limits
- [ ] Concurrent execution scales appropriately
- [ ] Telemetry provides useful insights

### 9.3 Integration Quality
- [ ] Seamless integration with existing DSPEx components
- [ ] Backward compatibility maintained
- [ ] Documentation is comprehensive and accurate
- [ ] Test coverage exceeds 90%

This implementation plan provides a roadmap for creating a faithful DSPy SIMBA implementation in DSPEx while maintaining the library's Elixir idioms and performance characteristics.
