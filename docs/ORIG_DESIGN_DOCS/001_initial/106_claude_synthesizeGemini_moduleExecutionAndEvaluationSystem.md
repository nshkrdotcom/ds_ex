# DSPEx Module Execution and Evaluation System

## Overview

This document details the implementation of DSPEx's module execution engine and evaluation system, focusing on leveraging OTP's concurrency primitives and the Foundation library's infrastructure for robust, scalable execution.

## Module Execution Architecture

### 1. Program Behaviour and Base Implementation

```elixir
defmodule DSPEx.Program do
  @moduledoc """
  Behaviour defining the contract for all DSPEx program modules.
  
  All executable modules (Predict, ChainOfThought, ReAct, etc.) must implement
  this behaviour to ensure consistent execution patterns and observability.
  """
  
  @doc """
  Execute the program with the given inputs.
  
  This is the primary entry point for all DSPEx modules. It should:
  - Validate inputs according to the module's signature
  - Execute the core logic (potentially involving LM calls)
  - Return a structured Prediction with outputs
  - Handle errors gracefully using Foundation's error system
  """
  @callback forward(program :: struct(), inputs :: map(), opts :: keyword()) ::
    {:ok, DSPEx.Prediction.t()} | {:error, Foundation.Types.Error.t()}
  
  @doc """
  Get the signature associated with this program.
  """
  @callback signature(program :: struct()) :: module()
  
  @doc """
  Configure the program with new parameters (demonstrations, instructions, etc.).
  """
  @callback configure(program :: struct(), config :: map()) :: 
    {:ok, struct()} | {:error, Foundation.Types.Error.t()}
  
  @optional_callbacks [configure: 2]
  
  # Convenience function for calling any program
  def forward(program, inputs, opts \\ []) do
    program.__struct__.forward(program, inputs, opts)
  end
  
  def call(program, inputs, opts \\ []) do
    # Alias for forward to match DSPy naming
    forward(program, inputs, opts)
  end
end
```

### 2. Enhanced Predict Module Implementation

```elixir
defmodule DSPEx.Predict do
  @behaviour DSPEx.Program
  
  defstruct [
    :signature,
    :client,
    :adapter,
    :demos,
    :config
  ]
  
  @impl DSPEx.Program
  def forward(program, inputs, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || Foundation.Utils.generate_correlation_id()
    
    # Create comprehensive execution context
    context = Foundation.ErrorContext.new(__MODULE__, :forward,
      correlation_id: correlation_id,
      metadata: %{
        signature: program.signature,
        client: program.client,
        adapter: program.adapter || DSPEx.Adapter.Chat,
        demo_count: length(program.demos || []),
        input_fields: Map.keys(inputs)
      }
    )
    
    Foundation.ErrorContext.with_context(context, fn ->
      # Start execution telemetry
      start_time = System.monotonic_time()
      
      Foundation.Events.new_event(:module_execution_start, %{
        module_type: :predict,
        signature: program.signature,
        correlation_id: correlation_id,
        timestamp: DateTime.utc_now()
      }, correlation_id: correlation_id)
      |> Foundation.Events.store()
      
      # Execute the prediction pipeline
      result = execute_prediction_pipeline(program, inputs, correlation_id)
      
      # Record execution metrics
      duration = System.monotonic_time() - start_time
      success = match?({:ok, _}, result)
      
      Foundation.Telemetry.emit_histogram(
        [:dspex, :module, :execution_time],
        duration,
        %{
          module_type: :predict,
          signature: program.signature,
          success: success,
          correlation_id: correlation_id
        }
      )
      
      Foundation.Events.new_event(:module_execution_complete, %{
        module_type: :predict,
        signature: program.signature,
        correlation_id: correlation_id,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond),
        success: success
      }, correlation_id: correlation_id)
      |> Foundation.Events.store()
      
      result
    end)
  end
  
  @impl DSPEx.Program
  def signature(program), do: program.signature
  
  @impl DSPEx.Program
  def configure(program, config) do
    updated_program = %{program |
      demos: Map.get(config, :demos, program.demos),
      adapter: Map.get(config, :adapter, program.adapter),
      config: Map.merge(program.config || %{}, config)
    }
    
    {:ok, updated_program}
  end
  
  # --- Private Implementation ---
  
  defp execute_prediction_pipeline(program, inputs, correlation_id) do
    with {:ok, validated_inputs} <- validate_inputs(program.signature, inputs),
         {:ok, messages} <- format_messages(program, validated_inputs, correlation_id),
         {:ok, completion} <- call_lm_client(program.client, messages, correlation_id),
         {:ok, parsed_outputs} <- parse_completion(program, completion, correlation_id),
         {:ok, validated_outputs} <- validate_outputs(program.signature, parsed_outputs) do
      
      prediction = %DSPEx.Prediction{
        signature: program.signature,
        inputs: validated_inputs,
        outputs: validated_outputs,
        raw_completion: completion,
        correlation_id: correlation_id,
        timestamp: DateTime.utc_now(),
        metadata: %{
          adapter: program.adapter || DSPEx.Adapter.Chat,
          demo_count: length(program.demos || [])
        }
      }
      
      {:ok, prediction}
    end
  end
  
  defp validate_inputs(signature, inputs) do
    required_fields = signature.input_fields()
    provided_fields = MapSet.new(Map.keys(inputs))
    required_set = MapSet.new(required_fields)
    
    missing_fields = MapSet.difference(required_set, provided_fields)
    
    case MapSet.size(missing_fields) do
      0 -> {:ok, Map.take(inputs, required_fields)}
      _ -> {:error, DSPEx.Error.validation_error(
        "Missing required input fields: #{Enum.join(missing_fields, ", ")}",
        %{missing_fields: MapSet.to_list(missing_fields)}
      )}
    end
  end
  
  defp validate_outputs(signature, outputs) do
    required_fields = signature.output_fields()
    provided_fields = MapSet.new(Map.keys(outputs))
    required_set = MapSet.new(required_fields)
    
    missing_fields = MapSet.difference(required_set, provided_fields)
    
    case MapSet.size(missing_fields) do
      0 -> {:ok, Map.take(outputs, required_fields)}
      _ -> {:error, DSPEx.Error.validation_error(
        "Missing required output fields: #{Enum.join(missing_fields, ", ")}",
        %{missing_fields: MapSet.to_list(missing_fields)}
      )}
    end
  end
  
  defp format_messages(program, inputs, correlation_id) do
    adapter = program.adapter || DSPEx.Adapter.Chat
    demos = program.demos || []
    
    adapter.format(program.signature, demos, inputs, correlation_id: correlation_id)
  end
  
  defp call_lm_client(client, messages, correlation_id) do
    DSPEx.Client.LM.request(client, messages, correlation_id: correlation_id)
  end
  
  defp parse_completion(program, completion, correlation_id) do
    adapter = program.adapter || DSPEx.Adapter.Chat
    adapter.parse(program.signature, completion, correlation_id: correlation_id)
  end
end
```

### 3. ChainOfThought Implementation

```elixir
defmodule DSPEx.ChainOfThought do
  @behaviour DSPEx.Program
  
  defstruct [
    :signature,
    :client,
    :adapter,
    :demos,
    :config,
    :extended_signature
  ]
  
  def new(signature, client, opts \\ []) do
    # Create extended signature with reasoning field at compile time or runtime
    extended_signature = create_extended_signature(signature)
    
    %__MODULE__{
      signature: signature,
      client: client,
      adapter: Keyword.get(opts, :adapter, DSPEx.Adapter.Chat),
      demos: Keyword.get(opts, :demos, []),
      config: Keyword.get(opts, :config, %{}),
      extended_signature: extended_signature
    }
  end
  
  @impl DSPEx.Program
  def forward(program, inputs, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || Foundation.Utils.generate_correlation_id()
    
    context = Foundation.ErrorContext.new(__MODULE__, :forward,
      correlation_id: correlation_id,
      metadata: %{
        signature: program.signature,
        extended_signature: program.extended_signature
      }
    )
    
    Foundation.ErrorContext.with_context(context, fn ->
      # Create internal predict module with extended signature
      internal_predict = %DSPEx.Predict{
        signature: program.extended_signature,
        client: program.client,
        adapter: program.adapter,
        demos: transform_demos_for_extended_signature(program.demos),
        config: program.config
      }
      
      # Execute prediction with extended signature
      case DSPEx.Predict.forward(internal_predict, inputs, opts) do
        {:ok, prediction} ->
          # Transform prediction back to original signature format
          transformed_prediction = %{prediction |
            signature: program.signature,
            outputs: Map.take(prediction.outputs, program.signature.output_fields()),
            metadata: Map.put(prediction.metadata, :reasoning, Map.get(prediction.outputs, :reasoning))
          }
          
          Foundation.Events.new_event(:chain_of_thought_complete, %{
            signature: program.signature,
            reasoning_length: String.length(Map.get(prediction.outputs, :reasoning, "")),
            correlation_id: correlation_id
          }, correlation_id: correlation_id)
          |> Foundation.Events.store()
          
          {:ok, transformed_prediction}
        
        {:error, error} ->
          {:error, error}
      end
    end)
  end
  
  @impl DSPEx.Program
  def signature(program), do: program.signature
  
  @impl DSPEx.Program
  def configure(program, config) do
    updated_program = %{program |
      demos: Map.get(config, :demos, program.demos),
      adapter: Map.get(config, :adapter, program.adapter),
      config: Map.merge(program.config || %{}, config)
    }
    
    {:ok, updated_program}
  end
  
  # --- Private Implementation ---
  
  defp create_extended_signature(original_signature) do
    # Create a new module that extends the original signature with reasoning
    extended_module_name = Module.concat([original_signature, ChainOfThought])
    
    # Get the original field definitions
    original_inputs = original_signature.input_fields()
    original_outputs = original_signature.output_fields()
    original_instructions = original_signature.instructions()
    
    # Add reasoning as the first output field
    extended_outputs = [:reasoning | original_outputs]
    
    # Enhanced instructions for chain of thought
    extended_instructions = """
    #{original_instructions}
    
    Please think step by step to reach your answer. First, provide your detailed reasoning in the 'reasoning' field, then give your final answer in the appropriate output field(s).
    """
    
    # Create the extended signature module dynamically
    contents = quote do
      @behaviour DSPEx.Signature
      
      def instructions, do: unquote(extended_instructions)
      def input_fields, do: unquote(original_inputs)
      def output_fields, do: unquote(extended_outputs)
    end
    
    Module.create(extended_module_name, contents, Macro.Env.location(__ENV__))
    extended_module_name
  end
  
  defp transform_demos_for_extended_signature(demos) do
    # Transform existing demos to include reasoning field
    demos
    |> Enum.map(fn demo ->
      # Add a synthetic reasoning field if not present
      labels = demo.labels()
      
      enhanced_labels = if Map.has_key?(labels, :reasoning) do
        labels
      else
        # Generate synthetic reasoning based on the answer
        synthetic_reasoning = generate_synthetic_reasoning(labels)
        Map.put(labels, :reasoning, synthetic_reasoning)
      end
      
      %{demo | fields: Map.merge(demo.inputs(), enhanced_labels)}
      |> DSPEx.Example.with_inputs(demo.input_keys)
    end)
  end
  
  defp generate_synthetic_reasoning(labels) do
    # Simple heuristic for generating reasoning from answers
    answer_fields = Map.values(labels)
    |> Enum.join(", ")
    
    "To arrive at this answer (#{answer_fields}), I need to carefully consider the given information and apply logical reasoning."
  end
end
```

## Evaluation System Implementation

### 1. Core Evaluation Engine

```elixir
defmodule DSPEx.Evaluate do
  @moduledoc """
  Concurrent evaluation system for DSPEx programs using OTP Task streams.
  """
  
  defstruct [
    :program,
    :devset,
    :metric,
    :num_threads,
    :display_progress,
    :display_table,
    :return_outputs
  ]
  
  def run(program, devset, metric, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || Foundation.Utils.generate_correlation_id()
    
    config = %__MODULE__{
      program: program,
      devset: devset,
      metric: metric,
      num_threads: Keyword.get(opts, :num_threads, System.schedulers_online() * 2),
      display_progress: Keyword.get(opts, :display_progress, true),
      display_table: Keyword.get(opts, :display_table, false),
      return_outputs: Keyword.get(opts, :return_outputs, false)
    }
    
    context = Foundation.ErrorContext.new(__MODULE__, :run,
      correlation_id: correlation_id,
      metadata: %{
        program_signature: program.signature(program),
        devset_size: length(devset),
        num_threads: config.num_threads
      }
    )
    
    Foundation.ErrorContext.with_context(context, fn ->
      execute_evaluation(config, correlation_id)
    end)
  end
  
  defp execute_evaluation(config, correlation_id) do
    start_time = System.monotonic_time()
    
    Foundation.Events.new_event(:evaluation_start, %{
      program_signature: config.program.signature(config.program),
      devset_size: length(config.devset),
      num_threads: config.num_threads,
      correlation_id: correlation_id
    }, correlation_id: correlation_id)
    |> Foundation.Events.store()
    
    # Create progress tracker if enabled
    progress_pid = if config.display_progress do
      {:ok, pid} = DSPEx.Evaluate.ProgressTracker.start_link(
        total: length(config.devset),
        correlation_id: correlation_id
      )
      pid
    else
      nil
    end
    
    # Execute evaluation using Task.async_stream for optimal concurrency
    results = 
      config.devset
      |> Task.async_stream(
        fn example -> evaluate_single_example(example, config, correlation_id, progress_pid) end,
        max_concurrency: config.num_threads,
        timeout: 300_000,  # 5 minutes per example
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> 
          Logger.warn("Evaluation task failed: #{inspect(reason)}")
          {:error, reason}
      end)
    
    # Stop progress tracker
    if progress_pid, do: GenServer.stop(progress_pid)
    
    # Process results
    {successful_results, failed_results} = partition_results(results)
    
    duration = System.monotonic_time() - start_time
    
    # Calculate metrics
    evaluation_summary = calculate_evaluation_summary(successful_results, failed_results, config.metric)
    
    # Emit final telemetry
    Foundation.Telemetry.emit_histogram(
      [:dspex, :evaluation, :duration],
      duration,
      %{
        devset_size: length(config.devset),
        success_count: length(successful_results),
        failure_count: length(failed_results),
        correlation_id: correlation_id
      }
    )
    
    Foundation.Events.new_event(:evaluation_complete, %{
      program_signature: config.program.signature(config.program),
      devset_size: length(config.devset),
      successful_evaluations: length(successful_results),
      failed_evaluations: length(failed_results),
      average_score: evaluation_summary.average_score,
      duration_ms: System.convert_time_unit(duration, :native, :millisecond),
      correlation_id: correlation_id
    }, correlation_id: correlation_id)
    |> Foundation.Events.store()
    
    # Display results if requested
    if config.display_table do
      display_evaluation_table(evaluation_summary, successful_results)
    end
    
    {:ok, evaluation_summary}
  end
  
  defp evaluate_single_example(example, config, correlation_id, progress_pid) do
    example_correlation_id = "#{correlation_id}_ex_#{Foundation.Utils.generate_id()}"
    
    context = Foundation.ErrorContext.new(__MODULE__, :evaluate_example,
      correlation_id: example_correlation_id,
      metadata: %{parent_correlation_id: correlation_id}
    )
    
    result = Foundation.ErrorContext.with_context(context, fn ->
      # Execute the program on this example
      case DSPEx.Program.forward(config.program, example.inputs(), 
           correlation_id: example_correlation_id) do
        {:ok, prediction} ->
          # Calculate the metric score
          score = apply_metric(config.metric, example, prediction)
          
          evaluation_result = %{
            example: example,
            prediction: config.return_outputs && prediction || nil,
            score: score,
            success: true,
            correlation_id: example_correlation_id
          }
          
          # Update progress
          if progress_pid do
            GenServer.cast(progress_pid, {:increment, score})
          end
          
          {:ok, evaluation_result}
        
        {:error, error} ->
          Logger.warn("Program execution failed for example", 
            error: Foundation.Error.to_string(error),
            correlation_id: example_correlation_id)
          
          evaluation_result = %{
            example: example,
            prediction: nil,
            score: 0.0,
            success: false,
            error: error,
            correlation_id: example_correlation_id
          }
          
          # Update progress
          if progress_pid do
            GenServer.cast(progress_pid, {:increment, 0.0})
          end
          
          {:ok, evaluation_result}
      end
    end)
    
    case result do
      {:ok, eval_result} -> eval_result
      {:error, error} -> 
        %{
          example: example,
          prediction: nil,
          score: 0.0,
          success: false,
          error: error,
          correlation_id: example_correlation_id
        }
    end
  end
  
  defp apply_metric(metric, example, prediction) when is_function(metric, 2) do
    try do
      metric.(example, prediction)
    rescue
      error ->
        Logger.warn("Metric function failed: #{inspect(error)}")
        0.0
    end
  end
  
  defp apply_metric(metric, example, prediction) when is_atom(metric) do
    # Support for built-in metrics
    case metric do
      :exact_match -> exact_match_metric(example, prediction)
      :contains -> contains_metric(example, prediction)
      _ -> 
        Logger.warn("Unknown metric: #{metric}")
        0.0
    end
  end
  
  defp exact_match_metric(example, prediction) do
    # Simple exact match for all output fields
    expected = example.labels()
    actual = prediction.outputs
    
    if maps_equal_normalized?(expected, actual) do
      1.0
    else
      0.0
    end
  end
  
  defp contains_metric(example, prediction) do
    # Check if prediction outputs contain expected labels
    expected = example.labels()
    actual = prediction.outputs
    
    matches = 
      expected
      |> Enum.count(fn {key, expected_value} ->
        actual_value = Map.get(actual, key, "")
        String.contains?(String.downcase(actual_value), String.downcase(expected_value))
      end)
    
    matches / map_size(expected)
  end
  
  defp maps_equal_normalized?(map1, map2) do
    # Normalize strings for comparison (trim, downcase)
    normalize_map(map1) == normalize_map(map2)
  end
  
  defp normalize_map(map) do
    map
    |> Enum.map(fn {k, v} -> 
      {k, String.trim(String.downcase(to_string(v)))} 
    end)
    |> Enum.into(%{})
  end
  
  defp partition_results(results) do
    {successful, failed} = Enum.split_with(results, & &1.success)
    {successful, failed}
  end
  
  defp calculate_evaluation_summary(successful_results, failed_results, metric) do
    total_count = length(successful_results) + length(failed_results)
    success_count = length(successful_results)
    
    scores = Enum.map(successful_results, & &1.score)
    
    average_score = if success_count > 0 do
      Enum.sum(scores) / success_count
    else
      0.0
    end
    
    %{
      total_examples: total_count,
      successful_examples: success_count,
      failed_examples: length(failed_results),
      success_rate: success_count / total_count,
      average_score: average_score,
      min_score: Enum.min(scores ++ [0.0]),
      max_score: Enum.max(scores ++ [0.0]),
      metric: metric,
      individual_scores: scores
    }
  end
  
  defp display_evaluation_table(summary, results) do
    # Simple table display - could be enhanced with a proper table library
    IO.puts("\n=== Evaluation Results ===")
    IO.puts("Total Examples: #{summary.total_examples}")
    IO.puts("Successful: #{summary.successful_examples}")
    IO.puts("Failed: #{summary.failed_examples}")
    IO.puts("Success Rate: #{Float.round(summary.success_rate * 100, 2)}%")
    IO.puts("Average Score: #{Float.round(summary.average_score, 4)}")
    IO.puts("Score Range: #{Float.round(summary.min_score, 4)} - #{Float.round(summary.max_score, 4)}")
    
    if length(results) <= 10 do
      IO.puts("\nIndividual Results:")
      results
      |> Enum.with_index(1)
      |> Enum.each(fn {result, idx} ->
        IO.puts("  #{idx}. Score: #{Float.round(result.score, 4)}")
      end)
    end
    
    IO.puts("========================\n")
  end
end
```

### 2. Progress Tracking for Long Evaluations

```elixir
defmodule DSPEx.Evaluate.ProgressTracker do
  use GenServer
  
  defstruct [
    :total,
    :completed,
    :running_score,
    :start_time,
    :correlation_id,
    :last_update
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  def init(opts) do
    total = Keyword.fetch!(opts, :total)
    correlation_id = Keyword.fetch!(opts, :correlation_id)
    
    state = %__MODULE__{
      total: total,
      completed: 0,
      running_score: 0.0,
      start_time: System.monotonic_time(),
      correlation_id: correlation_id,
      last_update: System.monotonic_time()
    }
    
    # Schedule periodic updates
    Process.send_after(self(), :update_progress, 1000)
    
    {:ok, state}
  end
  
  def handle_cast({:increment, score}, state) do
    new_state = %{state |
      completed: state.completed + 1,
      running_score: state.running_score + score
    }
    
    {:noreply, new_state}
  end
  
  def handle_info(:update_progress, state) do
    if state.completed > 0 do
      progress_pct = (state.completed / state.total) * 100
      avg_score = state.running_score / state.completed
      
      elapsed = System.monotonic_time() - state.start_time
      elapsed_seconds = System.convert_time_unit(elapsed, :native, :second)
      
      rate = state.completed / max(elapsed_seconds, 1)
      eta_seconds = (state.total - state.completed) / max(rate, 0.001)
      
      IO.write("\rProgress: #{state.completed}/#{state.total} (#{Float.round(progress_pct, 1)}%) " <>
               "| Avg Score: #{Float.round(avg_score, 3)} " <>
               "| Rate: #{Float.round(rate, 1)}/s " <>
               "| ETA: #{format_time(eta_seconds)}")
    end
    
    # Schedule next update if not complete
    if state.completed < state.total do
      Process.send_after(self(), :update_progress, 1000)
    else
      IO.puts("\nEvaluation complete!")
    end
    
    {:noreply, state}
  end
  
  defp format_time(seconds) when seconds < 60, do: "#{round(seconds)}s"
  defp format_time(seconds) when seconds < 3600 do
    minutes = div(round(seconds), 60)
    secs = rem(round(seconds), 60)
    "#{minutes}m #{secs}s"
  end
  defp format_time(seconds) do
    hours = div(round(seconds), 3600)
    minutes = div(rem(round(seconds), 3600), 60)
    "#{hours}h #{minutes}m"
  end
end
```

### 3. Built-in Metrics Library

```elixir
defmodule DSPEx.Metrics do
  @moduledoc """
  Built-in evaluation metrics for common DSPEx use cases.
  """
  
  def exact_match(example, prediction) do
    expected = example.labels()
    actual = prediction.outputs
    
    # Normalize for comparison
    expected_norm = normalize_for_comparison(expected)
    actual_norm = normalize_for_comparison(actual)
    
    if expected_norm == actual_norm, do: 1.0, else: 0.0
  end
  
  def contains_answer(example, prediction) do
    # Check if any output field contains the expected answer
    expected = example.labels()
    actual = prediction.outputs
    
    matches = 
      expected
      |> Enum.count(fn {key, expected_value} ->
        actual_value = Map.get(actual, key, "")
        normalized_expected = String.downcase(String.trim(to_string(expected_value)))
        normalized_actual = String.downcase(String.trim(to_string(actual_value)))
        
        String.contains?(normalized_actual, normalized_expected)
      end)
    
    if matches > 0, do: 1.0, else: 0.0
  end
  
  def field_accuracy(field_name) do
    fn example, prediction ->
      expected = Map.get(example.labels(), field_name)
      actual = Map.get(prediction.outputs, field_name)
      
      if normalize_string(expected) == normalize_string(actual) do
        1.0
      else
        0.0
      end
    end
  end
  
  def semantic_similarity(field_name, threshold \\ 0.8) do
    fn example, prediction ->
      expected = Map.get(example.labels(), field_name, "")
      actual = Map.get(prediction.outputs, field_name, "")
      
      # Simple similarity based on word overlap (could be enhanced with embeddings)
      similarity = calculate_word_overlap_similarity(expected, actual)
      
      if similarity >= threshold, do: 1.0, else: 0.0
    end
  end
  
  def answer_relevance(example, prediction) do
    # Check if the answer is relevant to the question
    question = Map.get(example.inputs(), :question, "")
    answer = Map.get(prediction.outputs, :answer, "")
    
    # Simple heuristic: check for question words in answer
    question_words = extract_key_words(question)
    answer_words = extract_key_words(answer)
    
    overlap = MapSet.intersection(question_words, answer_words)
    overlap_ratio = MapSet.size(overlap) / max(MapSet.size(question_words), 1)
    
    min(overlap_ratio * 2, 1.0)  # Scale up but cap at 1.0
  end
  
  # Composite metrics
  def multi_field_accuracy(fields) when is_list(fields) do
    fn example, prediction ->
      scores = 
        fields
        |> Enum.map(fn field -> field_accuracy(field).(example, prediction) end)
      
      Enum.sum(scores) / length(scores)
    end
  end
  
  def weighted_average(metric_weights) when is_list(metric_weights) do
    fn example, prediction ->
      total_weight = metric_weights |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      
      weighted_sum = 
        metric_weights
        |> Enum.map(fn {metric_fn, weight} ->
          metric_fn.(example, prediction) * weight
        end)
        |> Enum.sum()
      
      weighted_sum / total_weight
    end
  end
  
  # --- Private Helper Functions ---
  
  defp normalize_for_comparison(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {k, normalize_string(v)} end)
    |> Enum.into(%{})
  end
  
  defp normalize_string(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
  end
  
  defp calculate_word_overlap_similarity(text1, text2) do
    words1 = extract_key_words(text1)
    words2 = extract_key_words(text2)
    
    intersection = MapSet.intersection(words1, words2)
    union = MapSet.union(words1, words2)
    
    if MapSet.size(union) == 0 do
      0.0
    else
      MapSet.size(intersection) / MapSet.size(union)
    end
  end
  
  defp extract_key_words(text) do
    # Simple word extraction (could be enhanced with NLP)
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split()
    |> Enum.reject(&(&1 in ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by"]))
    |> MapSet.new()
  end
end
```

### 4. Integration with Foundation Events for Evaluation Monitoring

```elixir
defmodule DSPEx.Evaluate.Monitor do
  @moduledoc """
  Real-time monitoring and alerting for evaluation runs using Foundation events.
  """
  
  use GenServer
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Subscribe to evaluation events
    Foundation.Events.subscribe([
      :evaluation_start,
      :evaluation_complete,
      :module_execution_start,
      :module_execution_complete
    ])
    
    state = %{
      active_evaluations: %{},
      evaluation_stats: %{}
    }
    
    {:ok, state}
  end
  
  def handle_info({:foundation_event, %{event_type: :evaluation_start} = event}, state) do
    correlation_id = event.correlation_id
    
    eval_info = %{
      start_time: DateTime.utc_now(),
      devset_size: event.data.devset_size,
      program_signature: event.data.program_signature,
      completed_count: 0,
      error_count: 0
    }
    
    new_state = %{state | 
      active_evaluations: Map.put(state.active_evaluations, correlation_id, eval_info)
    }
    
    # Emit monitoring telemetry
    Foundation.Telemetry.emit_gauge([:dspex, :monitoring, :active_evaluations], 
      map_size(new_state.active_evaluations))
    
    {:noreply, new_state}
  end
  
  def handle_info({:foundation_event, %{event_type: :evaluation_complete} = event}, state) do
    correlation_id = event.correlation_id
    
    case Map.get(state.active_evaluations, correlation_id) do
      nil -> {:noreply, state}
      eval_info ->
        # Calculate final statistics
        duration = DateTime.diff(DateTime.utc_now(), eval_info.start_time, :second)
        
        final_stats = %{
          duration_seconds: duration,
          devset_size: event.data.devset_size,
          successful_count: event.data.successful_evaluations,
          failed_count: event.data.failed_evaluations,
          average_score: event.data.average_score,
          throughput: event.data.devset_size / max(duration, 1)
        }
        
        # Store historical stats
        new_evaluation_stats = Map.put(state.evaluation_stats, correlation_id, final_stats)
        
        # Remove from active evaluations
        new_active = Map.delete(state.active_evaluations, correlation_id)
        
        # Emit completion telemetry
        Foundation.Telemetry.emit_gauge([:dspex, :monitoring, :active_evaluations], 
          map_size(new_active))
        
        Foundation.Telemetry.emit_gauge([:dspex, :monitoring, :evaluation_throughput], 
          final_stats.throughput)
        
        # Check for performance alerts
        check_performance_alerts(final_stats)
        
        {:noreply, %{state | 
          active_evaluations: new_active,
          evaluation_stats: new_evaluation_stats
        }}
    end
  end
  
  def handle_info({:foundation_event, %{event_type: :module_execution_complete} = event}, state) do
    # Update counters for active evaluations
    parent_correlation_id = get_in(event.metadata, [:parent_correlation_id])
    
    if parent_correlation_id && Map.has_key?(state.active_evaluations, parent_correlation_id) do
      eval_info = Map.get(state.active_evaluations, parent_correlation_id)
      
      updated_eval_info = if event.data.success do
        %{eval_info | completed_count: eval_info.completed_count + 1}
      else
        %{eval_info | 
          completed_count: eval_info.completed_count + 1,
          error_count: eval_info.error_count + 1
        }
      end
      
      new_state = %{state |
        active_evaluations: Map.put(state.active_evaluations, parent_correlation_id, updated_eval_info)
      }
      
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  def handle_info({:foundation_event, _event}, state) do
    # Ignore other events
    {:noreply, state}
  end
  
  defp check_performance_alerts(stats) do
    # Alert if throughput is unusually low
    if stats.throughput < 0.1 do  # Less than 0.1 examples per second
      Logger.warn("Low evaluation throughput detected: #{stats.throughput} examples/sec")
    end
    
    # Alert if error rate is high
    error_rate = stats.failed_count / (stats.successful_count + stats.failed_count)
    if error_rate > 0.1 do  # More than 10% errors
      Logger.warn("High evaluation error rate: #{Float.round(error_rate * 100, 1)}%")
    end
    
    # Alert if average score is unusually low (could indicate model issues)
    if stats.average_score < 0.1 do
      Logger.warn("Low average evaluation score: #{stats.average_score}")
    end
  end
end
```

This comprehensive execution and evaluation system provides DSPEx with a robust, concurrent, and observable foundation for running and assessing language model programs at scale, leveraging OTP's strengths and the Foundation library's infrastructure capabilities.
