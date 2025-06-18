# DSPEx Predict Module Integration with Elixact

This guide covers integrating Elixact's validation capabilities into DSPEx's predict modules, focusing on Chain of Thought (CoT) and ReACT patterns.

## Overview

DSPEx's predict modules leverage Elixact to provide:
- Validated inputs before LLM calls
- Structured outputs with automatic repair
- Multi-step validation for complex reasoning
- Provider-specific optimization
- Intelligent error recovery

## Base Predictor Architecture

```elixir
defmodule DSPEx.Predict.BasePredictorWithElixact do
  alias DSPEx.Signature.Elixact, as: SignatureElixact
  
  defstruct [:signature, :client, :config, :examples, :retry_config]
  
  def new(signature_module, opts \\ []) do
    %__MODULE__{
      signature: signature_module.create_signature(),
      client: Keyword.get(opts, :client),
      config: build_predictor_config(opts),
      examples: Keyword.get(opts, :examples, []),
      retry_config: build_retry_config(opts)
    }
  end
  
  def predict(%__MODULE__{} = predictor, input) do
    with {:ok, validated_input} <- validate_input(predictor, input),
         {:ok, llm_response} <- call_llm_with_retry(predictor, validated_input),
         {:ok, validated_output} <- validate_output_with_repair(predictor, llm_response) do
      {:ok, validated_output}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_input(predictor, input) do
    case SignatureElixact.validate_input(predictor.signature, input) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, {:input_validation_failed, errors}}
    end
  end
  
  defp validate_output_with_repair(predictor, output) do
    case SignatureElixact.validate_output(predictor.signature, output) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> attempt_output_repair(predictor, output, errors)
    end
  end
end
```

## Chain of Thought Integration

```elixir
defmodule DSPEx.Predict.ChainOfThought do
  use DSPEx.Predict.BasePredictorWithElixact
  
  defstruct [:signature, :client, :config, :reasoning_steps, :step_validation_enabled]
  
  def new(signature_module, opts \\ []) do
    base = DSPEx.Predict.BasePredictorWithElixact.new(signature_module, opts)
    
    %__MODULE__{
      signature: base.signature,
      client: base.client,
      config: base.config,
      reasoning_steps: Keyword.get(opts, :reasoning_steps, 3),
      step_validation_enabled: Keyword.get(opts, :step_validation, true)
    }
  end
  
  def predict(%__MODULE__{} = predictor, input) do
    with {:ok, validated_input} <- validate_input(predictor, input),
         {:ok, reasoning_chain} <- generate_reasoning_chain(predictor, validated_input),
         {:ok, final_answer} <- synthesize_final_answer(predictor, reasoning_chain),
         {:ok, validated_output} <- validate_final_output(predictor, final_answer) do
      
      result = Map.put(validated_output, :reasoning_chain, reasoning_chain)
      {:ok, result}
    end
  end
  
  defp generate_reasoning_chain(predictor, input) do
    Enum.reduce_while(1..predictor.reasoning_steps, {:ok, []}, fn step_num, {:ok, acc_steps} ->
      case generate_reasoning_step(predictor, input, acc_steps, step_num) do
        {:ok, step} ->
          case validate_reasoning_step(step) do
            {:ok, validated_step} -> {:cont, {:ok, acc_steps ++ [validated_step]}}
            {:error, reason} -> {:halt, {:error, {:step_validation_failed, step_num, reason}}}
          end
        {:error, reason} -> {:halt, {:error, {:step_generation_failed, step_num, reason}}}
      end
    end)
  end
  
  defp validate_reasoning_step(step) do
    step_schema = create_reasoning_step_schema()
    config = DSPEx.Config.ElixactConfig.llm_output_config()
    Elixact.EnhancedValidator.validate(step_schema, step, config: config)
  end
  
  defp create_reasoning_step_schema do
    fields = [
      {:step_number, :integer, [required: true, gt: 0]},
      {:observation, :string, [required: true, min_length: 10]},
      {:reasoning, :string, [required: true, min_length: 20]},
      {:conclusion, :string, [required: true, min_length: 5]},
      {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]}
    ]
    
    Elixact.Runtime.create_schema(fields, title: "Reasoning_Step_Schema")
  end
end
```

## ReACT Integration

```elixir
defmodule DSPEx.Predict.ReACT do
  use DSPEx.Predict.BasePredictorWithElixact
  
  defstruct [:signature, :client, :config, :tools, :max_iterations, :action_validation_enabled]
  
  def new(signature_module, opts \\ []) do
    base = DSPEx.Predict.BasePredictorWithElixact.new(signature_module, opts)
    
    %__MODULE__{
      signature: base.signature,
      client: base.client,
      config: base.config,
      tools: Keyword.get(opts, :tools, []),
      max_iterations: Keyword.get(opts, :max_iterations, 5),
      action_validation_enabled: Keyword.get(opts, :action_validation, true)
    }
  end
  
  def predict(%__MODULE__{} = predictor, input) do
    with {:ok, validated_input} <- validate_input(predictor, input),
         {:ok, react_trace} <- execute_react_loop(predictor, validated_input),
         {:ok, final_answer} <- extract_final_answer(predictor, react_trace),
         {:ok, validated_output} <- validate_final_output(predictor, final_answer) do
      
      result = Map.merge(validated_output, %{
        react_trace: react_trace,
        iteration_count: length(react_trace)
      })
      
      {:ok, result}
    end
  end
  
  defp execute_react_loop(predictor, input) do
    initial_state = %{
      input: input,
      observations: [],
      actions_taken: [],
      final_answer: nil
    }
    
    execute_react_iterations(predictor, initial_state, [], 1)
  end
  
  defp execute_react_iterations(predictor, state, trace, iteration) when iteration <= predictor.max_iterations do
    case execute_react_iteration(predictor, state, iteration) do
      {:ok, :finished, final_state} -> {:ok, trace ++ [final_state]}
      {:ok, :continue, new_state} -> 
        execute_react_iterations(predictor, new_state, trace ++ [new_state], iteration + 1)
      {:error, reason} -> {:error, {:react_iteration_failed, iteration, reason}}
    end
  end
  
  defp execute_react_iteration(predictor, state, iteration) do
    with {:ok, reasoning} <- generate_reasoning(predictor, state, iteration),
         {:ok, action} <- determine_action(predictor, state, reasoning),
         {:ok, validated_action} <- validate_action(predictor, action),
         {:ok, observation} <- execute_action(predictor, validated_action),
         {:ok, updated_state} <- update_state(state, reasoning, validated_action, observation) do
      
      if action.type == :final_answer do
        {:ok, :finished, updated_state}
      else
        {:ok, :continue, updated_state}
      end
    end
  end
  
  defp validate_action(predictor, action) do
    if predictor.action_validation_enabled do
      action_schema = create_action_schema(predictor.tools)
      config = DSPEx.Config.ElixactConfig.llm_output_config()
      Elixact.EnhancedValidator.validate(action_schema, action, config: config)
    else
      {:ok, action}
    end
  end
  
  defp create_action_schema(tools) do
    tool_choices = Enum.map(tools, & &1.name) ++ ["final_answer"]
    
    fields = [
      {:type, :string, [required: true, choices: tool_choices]},
      {:reasoning, :string, [required: true, min_length: 10]},
      {:parameters, :map, [optional: true]},
      {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]}
    ]
    
    Elixact.Runtime.create_schema(fields, title: "ReACT_Action_Schema")
  end
end
```

## Error Recovery Strategies

```elixir
defmodule DSPEx.Predict.ValidationPipeline do
  def intelligent_output_repair(signature, output, errors) do
    repaired_output = output
    |> fix_type_coercion_errors(errors)
    |> fix_missing_required_fields(signature, errors)
    |> fix_format_errors(errors)
    |> fix_constraint_violations(errors)
    
    config = DSPEx.Config.ElixactConfig.llm_output_config(signature.provider)
    Elixact.EnhancedValidator.validate(signature.output_schema, repaired_output, config: config)
  end
  
  defp fix_type_coercion_errors(output, errors) do
    Enum.reduce(errors, output, fn error, acc ->
      case error.code do
        :type when error.expected == :float and is_binary(error.actual) ->
          case Float.parse(error.actual) do
            {float_val, _} -> put_in(acc, error.path, float_val)
            :error -> acc
          end
        :type when error.expected == :integer and is_binary(error.actual) ->
          case Integer.parse(error.actual) do
            {int_val, _} -> put_in(acc, error.path, int_val)
            :error -> acc
          end
        :type when error.expected == :boolean and is_binary(error.actual) ->
          case String.downcase(error.actual) do
            "true" -> put_in(acc, error.path, true)
            "false" -> put_in(acc, error.path, false)
            _ -> acc
          end
        _ -> acc
      end
    end)
  end
end
```

## Performance Optimization

```elixir
defmodule DSPEx.Predict.PerformanceOptimizer do
  def predict_batch(predictor, inputs) do
    with {:ok, validated_inputs} <- validate_input_batch(predictor, inputs),
         {:ok, llm_responses} <- call_llm_batch(predictor, validated_inputs),
         {:ok, validated_outputs} <- validate_output_batch(predictor, llm_responses) do
      
      results = Enum.zip(validated_inputs, validated_outputs)
      {:ok, results}
    end
  end
  
  defp validate_input_batch(predictor, inputs) do
    config = DSPEx.Config.ElixactConfig.dspy_signature_config(predictor.signature.provider)
    Elixact.EnhancedValidator.validate_many(predictor.signature.input_schema, inputs, config: config)
  end
end
```

## Testing

```elixir
defmodule DSPEx.Predict.ChainOfThoughtTest do
  use ExUnit.Case
  
  test "validates input and generates reasoning chain" do
    predictor = DSPEx.Predict.ChainOfThought.new(TestSignature, reasoning_steps: 2)
    
    input = %{question: "What is 2+2?", context: "Basic arithmetic"}
    
    {:ok, result} = DSPEx.Predict.ChainOfThought.predict(predictor, input)
    
    assert result.answer != nil
    assert is_list(result.reasoning_chain)
    assert length(result.reasoning_chain) == 2
  end
end
```

This predict module integration provides robust, validated AI prediction capabilities with intelligent error recovery and performance optimization. 