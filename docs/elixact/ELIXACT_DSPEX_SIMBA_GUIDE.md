# SIMBA Teleprompter with Elixact Integration

This guide covers integrating Elixact validation into DSPEx's SIMBA teleprompter for robust optimization.

## Overview

SIMBA with Elixact provides:
- Validated example management
- Performance tracking with structured metrics  
- Strategy optimization with validated parameters
- Type-safe bucket management

## Enhanced Strategy Module

```elixir
defmodule DSPEx.Teleprompter.Simba.Strategy do
  defstruct [:name, :signature, :examples, :performance_metrics, :validation_config]
  
  def new(name, signature, opts \\ []) do
    %__MODULE__{
      name: name,
      signature: signature,
      examples: [],
      performance_metrics: create_initial_metrics(),
      validation_config: DSPEx.Config.ElixactConfig.evaluation_config()
    }
  end
  
  def add_example(%__MODULE__{} = strategy, example) do
    case validate_example(strategy, example) do
      {:ok, validated_example} ->
        {:ok, %{strategy | examples: [validated_example | strategy.examples]}}
      {:error, errors} ->
        {:error, {:example_validation_failed, errors}}
    end
  end
  
  defp validate_example(strategy, example) do
    example_schema = create_example_schema()
    Elixact.EnhancedValidator.validate(example_schema, example, config: strategy.validation_config)
  end
  
  defp create_example_schema do
    fields = [
      {:input, :map, [required: true]},
      {:output, :map, [required: true]},
      {:quality_score, :float, [optional: true, gteq: 0.0, lteq: 1.0]}
    ]
    
    Elixact.Runtime.create_schema(fields, title: "SIMBA_Example_Schema")
  end
end
```

## Performance Tracking

```elixir
defmodule DSPEx.Teleprompter.Simba.Performance do
  defstruct [:strategy_name, :metrics_history, :current_metrics, :validation_config]
  
  def new(strategy_name, opts \\ []) do
    %__MODULE__{
      strategy_name: strategy_name,
      metrics_history: [],
      current_metrics: %{},
      validation_config: DSPEx.Config.ElixactConfig.evaluation_config()
    }
  end
  
  def record_performance(%__MODULE__{} = tracker, metrics) do
    case validate_metrics(tracker, metrics) do
      {:ok, validated_metrics} ->
        updated_tracker = %{tracker | 
          metrics_history: [validated_metrics | tracker.metrics_history],
          current_metrics: validated_metrics
        }
        {:ok, updated_tracker}
      {:error, errors} ->
        {:error, {:metrics_validation_failed, errors}}
    end
  end
  
  defp validate_metrics(tracker, metrics) do
    metrics_schema = create_metrics_schema()
    Elixact.EnhancedValidator.validate(metrics_schema, metrics, config: tracker.validation_config)
  end
  
  defp create_metrics_schema do
    fields = [
      {:accuracy, :float, [required: true, gteq: 0.0, lteq: 1.0]},
      {:f1_score, :float, [required: true, gteq: 0.0, lteq: 1.0]},
      {:latency_ms, :integer, [required: true, gt: 0]},
      {:example_count, :integer, [required: true, gteq: 0]}
    ]
    
    Elixact.Runtime.create_schema(fields, title: "SIMBA_Performance_Metrics")
  end
end
```

## Bucket Management

```elixir
defmodule DSPEx.Teleprompter.Simba.Bucket do
  defstruct [:bucket_id, :examples, :capacity, :selection_strategy, :validation_config]
  
  def new(bucket_id, opts \\ []) do
    %__MODULE__{
      bucket_id: bucket_id,
      examples: [],
      capacity: Keyword.get(opts, :capacity, 100),
      selection_strategy: Keyword.get(opts, :selection_strategy, :quality_based),
      validation_config: DSPEx.Config.ElixactConfig.evaluation_config()
    }
  end
  
  def add_example(%__MODULE__{} = bucket, example) do
    case validate_bucket_example(bucket, example) do
      {:ok, validated_example} ->
        updated_examples = manage_capacity([validated_example | bucket.examples], bucket.capacity)
        {:ok, %{bucket | examples: updated_examples}}
      {:error, errors} ->
        {:error, {:bucket_validation_failed, errors}}
    end
  end
  
  def select_examples(%__MODULE__{} = bucket, count) do
    case bucket.selection_strategy do
      :quality_based -> {:ok, select_by_quality(bucket.examples, count)}
      :random -> {:ok, select_randomly(bucket.examples, count)}
    end
  end
  
  defp validate_bucket_example(bucket, example) do
    schema = create_bucket_example_schema()
    Elixact.EnhancedValidator.validate(schema, example, config: bucket.validation_config)
  end
  
  defp create_bucket_example_schema do
    fields = [
      {:input, :map, [required: true]},
      {:output, :map, [required: true]},
      {:quality_score, :float, [required: true, gteq: 0.0, lteq: 1.0]}
    ]
    
    Elixact.Runtime.create_schema(fields, title: "SIMBA_Bucket_Example")
  end
  
  defp manage_capacity(examples, capacity) do
    if length(examples) > capacity do
      examples |> Enum.sort_by(& &1.quality_score, :desc) |> Enum.take(capacity)
    else
      examples
    end
  end
  
  defp select_by_quality(examples, count) do
    examples |> Enum.sort_by(& &1.quality_score, :desc) |> Enum.take(count)
  end
  
  defp select_randomly(examples, count) do
    examples |> Enum.shuffle() |> Enum.take(count)
  end
end
```

## Main SIMBA Module

```elixir
defmodule DSPEx.Teleprompter.Simba do
  alias DSPEx.Teleprompter.Simba.{Strategy, Performance, Bucket}
  
  defstruct [:signature, :strategy, :performance_tracker, :example_buckets]
  
  def new(signature_module, opts \\ []) do
    signature = signature_module.create_signature()
    strategy_name = Keyword.get(opts, :strategy_name, "default_simba")
    
    %__MODULE__{
      signature: signature,
      strategy: Strategy.new(strategy_name, signature, opts),
      performance_tracker: Performance.new(strategy_name, opts),
      example_buckets: %{primary: Bucket.new(:primary, opts)}
    }
  end
  
  def compile(%__MODULE__{} = simba, training_data) do
    with {:ok, validated_data} <- validate_training_data(training_data),
         {:ok, optimized_strategy} <- optimize_strategy(simba.strategy, validated_data) do
      
      {:ok, %{simba | strategy: optimized_strategy}}
    end
  end
  
  def predict(%__MODULE__{} = simba, input) do
    examples = select_examples(simba, 3)
    enhanced_input = Map.put(input, :examples, examples)
    
    # Use appropriate predictor based on signature
    predictor = create_predictor(simba)
    DSPEx.Predict.BasePredictorWithElixact.predict(predictor, enhanced_input)
  end
  
  defp validate_training_data(data) do
    schema = create_training_data_schema()
    config = DSPEx.Config.ElixactConfig.evaluation_config()
    Elixact.EnhancedValidator.validate(schema, data, config: config)
  end
  
  defp create_training_data_schema do
    fields = [
      {:examples, {:array, :map}, [required: true, min_items: 1]}
    ]
    
    Elixact.Runtime.create_schema(fields, title: "SIMBA_Training_Data")
  end
  
  defp select_examples(simba, count) do
    primary_bucket = Map.get(simba.example_buckets, :primary)
    
    case Bucket.select_examples(primary_bucket, count) do
      {:ok, examples} -> examples
      {:error, _} -> []
    end
  end
  
  defp create_predictor(simba) do
    %DSPEx.Predict.BasePredictorWithElixact{
      signature: simba.signature,
      examples: simba.strategy.examples,
      config: %{}
    }
  end
end
```

This SIMBA integration provides validated optimization with Elixact's robust validation capabilities. 