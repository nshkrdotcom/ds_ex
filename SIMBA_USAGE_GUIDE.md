# DSPy SIMBA Implementation Usage GuideAdd commentMore actions

## Overview

This guide demonstrates how to use the faithful DSPy SIMBA (Stochastic Introspective Mini-Batch Ascent) implementation in DSPEx. This implementation follows the original DSPy algorithm exactly, using stochastic hill-climbing with trajectory analysis rather than Bayesian optimization.

## Quick Start

### Basic Usage

```elixir
# Define your signature
defmodule QASignature do
  @moduledoc "Answer questions accurately"
  use DSPEx.Signature, "question -> answer"
end

# Create student and teacher programs
student = DSPEx.Predict.new(QASignature, :gemini)
teacher = DSPEx.Predict.new(QASignature, :openai)  # Stronger model as teacher

# Prepare training data
trainset = [
  DSPEx.Example.new(%{question: "What is 2+2?", answer: "4"}, [:question]),
  DSPEx.Example.new(%{question: "Capital of France?", answer: "Paris"}, [:question]),
  # ... more examples
]

# Define evaluation metric
metric_fn = fn example, prediction ->
  expected = DSPEx.Example.outputs(example)[:answer]
  actual = prediction[:answer]
  if String.downcase(expected) == String.downcase(actual), do: 1.0, else: 0.0
end

# Create and configure SIMBA teleprompter
teleprompter = DSPEx.Teleprompter.SIMBA.new(
  bsize: 32,              # Mini-batch size
  num_candidates: 6,      # Candidate programs per iteration
  max_steps: 8,           # Optimization steps
  max_demos: 4,           # Max demonstrations per predictor
  strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo]
)

# Run optimization
case teleprompter.compile(student, teacher, trainset, metric_fn) do
  {:ok, optimized_program} ->
    # Use the optimized program
    IO.inspect(optimized_program)
    {:ok, result} = DSPEx.Program.forward(optimized_program, %{question: "What is 3+3?"})
    IO.inspect(result)
  {:error, reason} ->
    IO.puts("Optimization failed: #{inspect(reason)}")
end
```

### Error Handling

When running the optimization process, it's important to handle potential errors. The `compile/4` function returns a tagged tuple: `{:ok, optimized_program}` on success, or `{:error, reason}` on failure.

```elixir
# ... (setup student, teacher, trainset, metric_fn as above) ...

teleprompter = DSPEx.Teleprompter.SIMBA.new(
  bsize: 32,
  num_candidates: 6,
  strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo]
)

case teleprompter.compile(student, teacher, trainset, metric_fn) do
  {:ok, optimized_program} ->
    IO.puts("Optimization successful!")
    # Proceed to use the optimized_program
    {:ok, result} = DSPEx.Program.forward(optimized_program, %{question: "Test question"})
    IO.inspect(result)

  {:error, %{reason: :max_steps_reached, message: msg, program: _program_at_failure}} ->
    IO.puts("Optimization stopped: #{msg}")
    # You might want to use the program_at_failure or log more details

  {:error, %{reason: :no_improvement, message: msg, program: _program_at_failure}} ->
    IO.puts("Optimization could not find improvements: #{msg}")

  {:error, reason} ->
    IO.puts("An unexpected error occurred during optimization: #{inspect(reason)}")
end
```

## Algorithm Configuration

### Core Parameters

```elixir
teleprompter = DSPEx.Teleprompter.SIMBA.new(
  # Mini-batch size - smaller batches = more granular optimization
  bsize: 32,
  
  # Number of candidate programs generated per iteration
  num_candidates: 6,
  
  # Maximum optimization steps to run
  max_steps: 8,
  
  # Maximum demonstrations to keep per predictor
  max_demos: 4,
  
  # Maximum character length for demo input fields
  demo_input_field_maxlen: 100_000,
  
  # Strategies to apply for program improvement
  strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo],
  
  # Temperature for trajectory sampling (lower = less exploration)
  temperature_for_sampling: 0.2,
  
  # Temperature for candidate selection (lower = more greedy)
  temperature_for_candidates: 0.2,
  
  # Optional progress callback function
  progress_callback: &IO.inspect/1
)
```

### Strategy Configuration

Currently, the main strategy is `DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo`, which creates demonstrations from successful execution trajectories:

```elixir
# Basic append_demo strategy
strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo]

# You can implement custom strategies by creating modules that implement
# the DSPEx.Teleprompter.SIMBA.Strategy behaviour
# e.g., strategies: [MyCustomStrategy, DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo]
```

## Advanced Usage

### Chain of Thought Optimization

```elixir
defmodule ChainOfThoughtSignature do
  @moduledoc "Solve problems with step-by-step reasoning"
  use DSPEx.Signature, "problem -> reasoning, answer"
end

# Multi-criteria metric that rewards both correct answers and reasoning
metric_fn = fn example, prediction ->
  expected_answer = DSPEx.Example.outputs(example)[:answer]
  predicted_answer = prediction[:answer]
  reasoning = prediction[:reasoning] || ""
  
  answer_correct = String.downcase(expected_answer) == String.downcase(predicted_answer)
  has_reasoning = String.length(reasoning) > 20
  
  cond do
    answer_correct and has_reasoning -> 1.0
    answer_correct -> 0.7
    has_reasoning -> 0.3
    true -> 0.0
  end
end

# Configure for more complex reasoning tasks
teleprompter = DSPEx.Teleprompter.SIMBA.new(
  bsize: 16,              # Smaller batches for complex examples
  num_candidates: 8,      # More candidates for exploration
  max_steps: 12,          # More steps for complex optimization
  max_demos: 6,           # More demonstrations for reasoning patterns
  temperature_for_sampling: 0.3  # Slightly more exploration
)
```

### Performance Tracking

```elixir
# Track optimization progress
progress_callback = fn progress ->
  case progress do
    %{phase: :trajectory_sampling, completed: completed, total: total} ->
      IO.puts("Sampling trajectories: #{completed}/#{total}")
    
    %{phase: :bucket_analysis, buckets_created: count} ->
      IO.puts("Created #{count} performance buckets")
    
    %{phase: :strategy_application, candidates_generated: count} ->
      IO.puts("Generated #{count} candidate programs")
    
    _ ->
      IO.puts("Progress: #{inspect(progress)}")
  end
end

teleprompter = DSPEx.Teleprompter.SIMBA.new(
  progress_callback: progress_callback
)
```

### Performance Analysis

```elixir
alias DSPEx.Teleprompter.SIMBA.Performance

# After optimization, analyze the improvement
{:ok, optimized} = teleprompter.compile(student, teacher, trainset, metric_fn)

improvement_metrics = Performance.calculate_improvement(
  student,      # original program
  optimized,    # optimized program  
  trainset,     # test examples
  metric_fn     # evaluation metric
)

IO.puts("Performance Analysis:")
IO.puts("Original Score: #{improvement_metrics.original_score}")
IO.puts("Optimized Score: #{improvement_metrics.improved_score}")
IO.puts("Improvement: #{Float.round(improvement_metrics.relative_improvement * 100, 1)}%")
```

## Understanding the Algorithm

### How SIMBA Works

1. **Trajectory Sampling**: SIMBA executes your program on mini-batches with different model configurations to generate execution "trajectories"

2. **Bucket Analysis**: Trajectories are grouped into "buckets" based on performance, identifying which examples show improvement potential

3. **Strategy Application**: Simple strategies (like `append_demo`) analyze successful trajectories and create new program variants

4. **Selection**: The best-performing candidates are kept and the process repeats

### Key Differences from Bayesian Optimization

- **Stochastic Hill-Climbing**: Uses simple heuristics rather than mathematical optimization
- **Trajectory-Based**: Focuses on execution patterns rather than parameter space exploration  
- **Mini-Batch Oriented**: Processes data in small batches for efficiency
- **Strategy-Driven**: Uses interpretable rules for program improvement

## Best Practices

### Training Data

```elixir
# Good training examples have:
# 1. Clear input-output relationships
# 2. Diverse scenarios
# 3. Consistent quality

trainset = [
  # Varied question types
  DSPEx.Example.new(%{question: "Math: What is 5+7?", answer: "12"}, [:question]),
  DSPEx.Example.new(%{question: "Geography: Capital of Japan?", answer: "Tokyo"}, [:question]),
  DSPEx.Example.new(%{question: "Science: What gas do plants breathe?", answer: "Carbon dioxide"}, [:question]),
  
  # Include edge cases
  DSPEx.Example.new(%{question: "Tricky: What's 0 divided by 0?", answer: "Undefined"}, [:question])
]
```

### Metric Functions

```elixir
# Simple exact match
exact_match = fn example, prediction ->
  expected = DSPEx.Example.outputs(example)[:answer]
  actual = prediction[:answer]
  if expected == actual, do: 1.0, else: 0.0
end

# Fuzzy string matching
fuzzy_match = fn example, prediction ->
  expected = String.downcase(DSPEx.Example.outputs(example)[:answer] || "")
  actual = String.downcase(prediction[:answer] || "")
  
  cond do
    expected == actual -> 1.0
    String.contains?(actual, expected) or String.contains?(expected, actual) -> 0.7
    true -> 0.0
  end
end

# Multi-criteria evaluation
multi_criteria = fn example, prediction ->
  # Weight different aspects
  answer_score = evaluate_answer(example, prediction) * 0.7
  reasoning_score = evaluate_reasoning(prediction) * 0.3
  answer_score + reasoning_score
end
```

### Configuration Guidelines

```elixir
# For quick development/testing
quick_config = DSPEx.Teleprompter.SIMBA.new(
  max_steps: 2,
  bsize: 8,
  num_candidates: 3
)

# For production optimization  
production_config = DSPEx.Teleprompter.SIMBA.new(
  max_steps: 10,
  bsize: 32,
  num_candidates: 8,
  max_demos: 6
)

# For complex reasoning tasks
reasoning_config = DSPEx.Teleprompter.SIMBA.new(
  max_steps: 15,
  bsize: 16,
  num_candidates: 10,
  max_demos: 8,
  temperature_for_sampling: 0.3
)
```

## Troubleshooting

### Common Issues

**Low improvement scores:**
```elixir
# Try adjusting these parameters:
teleprompter = DSPEx.Teleprompter.SIMBA.new(
  max_steps: 12,           # More optimization steps
  num_candidates: 10,      # More exploration
  temperature_for_sampling: 0.4 # More diversity in samplingAdd commentMore actions
)
```

**Optimization taking too long:**
```elixir
# Reduce computational load:
teleprompter = DSPEx.Teleprompter.SIMBA.new(
  max_steps: 4,           # Fewer steps
  bsize: 16,              # Smaller batches
  num_candidates: 4       # Fewer candidates
)
```

**Poor quality demonstrations:**
```elixir
# Increase quality thresholds:
teleprompter = DSPEx.Teleprompter.SIMBA.new(
  max_demos: 3,           # Fewer, higher-quality demos
  # Implement stricter metric function
)
```

### Debugging

```elixir
# Enable detailed progress tracking
teleprompter = DSPEx.Teleprompter.SIMBA.new(
  progress_callback: fn progress ->
    IO.puts("#{DateTime.utc_now()} - #{inspect(progress)}")
  end
)

# Analyze trajectory quality
alias DSPEx.Teleprompter.SIMBA.{Trajectory, Bucket, Performance}

# Check if your metric function works correctly
test_example = List.first(trainset)
{:ok, test_prediction} = DSPEx.Program.forward(student, DSPEx.Example.inputs(test_example))
test_score = metric_fn.(test_example, test_prediction)
IO.puts("Test metric score: #{test_score}")
```

## Integration with Existing DSPEx Code

The SIMBA implementation integrates seamlessly with existing DSPEx programs:

```elixir
# Works with any DSPEx.Program implementation
programs_to_optimize = [
  DSPEx.Predict.new(MySignature, :gemini),
  DSPEx.PredictStructured.new(MySignature, :gemini),
  my_custom_program
]

# Works with existing OptimizedProgram wrappers
existing_optimized = DSPEx.OptimizedProgram.new(base_program, demos)
{:ok, further_optimized} = teleprompter.compile(existing_optimized, teacher, trainset, metric_fn)

# Maintains compatibility with other teleprompters
bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new()
{:ok, bootstrap_optimized} = bootstrap.compile(student, teacher, trainset, metric_fn)

# Can further optimize with SIMBA
{:ok, simba_optimized} = teleprompter.compile(bootstrap_optimized, teacher, trainset, metric_fn)
```

This implementation provides a faithful reproduction of the DSPy SIMBA algorithm while maintaining DSPEx's Elixir idioms and performance characteristics.
