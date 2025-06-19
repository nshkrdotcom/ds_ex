# Part II: Additional Strategy Implementations

## 7. **NEW: Rule-Based Strategy Implementation**

```elixir
defmodule DSPEx.Teleprompter.SIMBA.Strategy.AppendRule do
  @moduledoc """
  Strategy that generates instruction improvements based on trajectory analysis.
  
  This strategy analyzes successful vs. unsuccessful trajectories and generates
  new instruction text to improve program performance.
  """
  
  @behaviour DSPEx.Teleprompter.SIMBA.Strategy
  
  alias DSPEx.{Program, Client}
  alias DSPEx.Teleprompter.SIMBA.{Bucket, Trajectory}
  
  @impl DSPEx.Teleprompter.SIMBA.Strategy
  def apply(bucket, source_program, opts \\ %{}) do
    case analyze_bucket_for_rules(bucket, opts) do
      {:ok, instruction_improvement} ->
        apply_instruction_to_program(source_program, instruction_improvement, opts)
      {:skip, reason} ->
        {:skip, reason}
    end
  end
  
  @impl DSPEx.Teleprompter.SIMBA.Strategy
  def applicable?(bucket, opts \\ %{}) do
    quality_threshold = Map.get(opts, :quality_threshold, 0.7)
    
    case {Bucket.best_trajectory(bucket), Bucket.statistics(bucket)} do
      {%Trajectory{score: best_score}, %{trajectory_count: count}} 
      when best_score >= quality_threshold and count >= 3 ->
        true
      _ ->
        false
    end
  end
  
  defp analyze_bucket_for_rules(bucket, opts) do
    trajectories = bucket.trajectories
    
    # Separate successful and unsuccessful trajectories
    {successful, unsuccessful} = Enum.split_with(trajectories, fn trajectory ->
      trajectory.score >= Map.get(opts, :quality_threshold, 0.7)
    end)
    
    if length(successful) > 0 and length(unsuccessful) > 0 do
      generate_instruction_improvement(successful, unsuccessful, opts)
    else
      {:skip, "Not enough trajectory variance for rule generation"}
    end
  end
  
  defp generate_instruction_improvement(successful_trajectories, unsuccessful_trajectories, opts) do
    # Analyze patterns in successful vs unsuccessful trajectories
    success_patterns = analyze_trajectory_patterns(successful_trajectories)
    failure_patterns = analyze_trajectory_patterns(unsuccessful_trajectories)
    
    # Generate instruction improvement using LLM
    prompt = build_rule_generation_prompt(success_patterns, failure_patterns, opts)
    
    case request_instruction_improvement(prompt, opts) do
      {:ok, instruction} ->
        {:ok, String.trim(instruction)}
      {:error, reason} ->
        {:skip, "Failed to generate instruction: #{inspect(reason)}"}
    end
  end
  
  defp analyze_trajectory_patterns(trajectories) do
    %{
      common_inputs: extract_common_input_patterns(trajectories),
      common_outputs: extract_common_output_patterns(trajectories),
      average_score: calculate_average_score(trajectories),
      execution_times: Enum.map(trajectories, & &1.duration),
      error_types: extract_error_types(trajectories)
    }
  end
  
  defp extract_common_input_patterns(trajectories) do
    # Find common input field patterns
    all_inputs = Enum.map(trajectories, & &1.inputs)
    
    # Extract field types and common values
    input_fields = case List.first(all_inputs) do
      nil -> []
      first_input -> Map.keys(first_input)
    end
    
    Enum.reduce(input_fields, %{}, fn field, acc ->
      values = Enum.map(all_inputs, &Map.get(&1, field))
      Map.put(acc, field, analyze_field_values(values))
    end)
  end
  
  defp extract_common_output_patterns(trajectories) do
    # Similar to input patterns but for outputs
    all_outputs = Enum.map(trajectories, & &1.outputs)
    
    output_fields = case List.first(all_outputs) do
      nil -> []
      first_output -> Map.keys(first_output)
    end
    
    Enum.reduce(output_fields, %{}, fn field, acc ->
      values = Enum.map(all_outputs, &Map.get(&1, field))
      Map.put(acc, field, analyze_field_values(values))
    end)
  end
  
  defp analyze_field_values(values) do
    non_nil_values = Enum.reject(values, &is_nil/1)
    
    %{
      count: length(non_nil_values),
      types: non_nil_values |> Enum.map(&get_value_type/1) |> Enum.uniq(),
      sample_values: Enum.take(non_nil_values, 3),
      avg_length: calculate_avg_string_length(non_nil_values)
    }
  end
  
  defp get_value_type(value) when is_binary(value), do: :string
  defp get_value_type(value) when is_number(value), do: :number
  defp get_value_type(value) when is_list(value), do: :list
  defp get_value_type(value) when is_map(value), do: :map
  defp get_value_type(_), do: :other
  
  defp calculate_avg_string_length(values) do
    string_values = Enum.filter(values, &is_binary/1)
    if Enum.empty?(string_values) do
      0
    else
      total_length = Enum.reduce(string_values, 0, fn str, acc -> acc + String.length(str) end)
      total_length / length(string_values)
    end
  end
  
  defp extract_error_types(trajectories) do
    trajectories
    |> Enum.filter(fn t -> not t.success end)
    |> Enum.map(fn t -> t.error end)
    |> Enum.group_by(& &1)
    |> Enum.map(fn {error_type, occurrences} -> {error_type, length(occurrences)} end)
  end
  
  defp calculate_average_score(trajectories) do
    if Enum.empty?(trajectories) do
      0.0
    else
      total_score = Enum.reduce(trajectories, 0.0, fn t, acc -> acc + t.score end)
      total_score / length(trajectories)
    end
  end
  
  defp build_rule_generation_prompt(success_patterns, failure_patterns, _opts) do
    """
    You are an AI instruction optimizer. Analyze the following execution patterns and generate an improved instruction.
    
    SUCCESSFUL EXECUTION PATTERNS:
    - Average Score: #{success_patterns.average_score}
    - Input Patterns: #{inspect(success_patterns.common_inputs, limit: :infinity)}
    - Output Patterns: #{inspect(success_patterns.common_outputs, limit: :infinity)}
    
    UNSUCCESSFUL EXECUTION PATTERNS:
    - Average Score: #{failure_patterns.average_score}
    - Input Patterns: #{inspect(failure_patterns.common_inputs, limit: :infinity)}
    - Output Patterns: #{inspect(failure_patterns.common_outputs, limit: :infinity)}
    - Common Errors: #{inspect(failure_patterns.error_types)}
    
    Based on this analysis, generate a concise instruction improvement that addresses the failure patterns while reinforcing the success patterns. Focus on:
    1. Specific guidance that differentiates successful from unsuccessful approaches
    2. Clear direction on handling the types of inputs shown
    3. Expected output format and quality standards
    
    Instruction improvement:
    """
  end
  
  defp request_instruction_improvement(prompt, opts) do
    model = Map.get(opts, :instruction_model, :gemini)
    correlation_id = Map.get(opts, :correlation_id, "rule-gen")
    
    messages = [%{role: "user", content: prompt}]
    
    case Client.request(messages, %{provider: model, correlation_id: correlation_id, temperature: 0.7}) do
      {:ok, response} ->
        instruction = response.choices
          |> List.first()
          |> get_in([Access.key(:message), Access.key(:content)])
          |> String.trim()
        
        {:ok, instruction}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp apply_instruction_to_program(program, instruction_improvement, _opts) do
    case program do
      # Program with signature - enhance instruction
      %{signature: signature} when not is_nil(signature) ->
        enhanced_program = enhance_program_instruction(program, signature, instruction_improvement)
        {:ok, enhanced_program}
      
      # OptimizedProgram wrapper
      %DSPEx.OptimizedProgram{program: inner_program} ->
        case apply_instruction_to_program(inner_program, instruction_improvement, _opts) do
          {:ok, enhanced_inner} ->
            enhanced_wrapper = %{program | program: enhanced_inner}
            {:ok, enhanced_wrapper}
          error ->
            error
        end
      
      # No signature available - wrap with OptimizedProgram
      _ ->
        optimized = DSPEx.OptimizedProgram.new(program, [], %{
          instruction: instruction_improvement,
          strategy: :append_rule,
          generated_at: DateTime.utc_now()
        })
        {:ok, optimized}
    end
  end
  
  defp enhance_program_instruction(program, signature, instruction_improvement) do
    if function_exported?(signature, :instructions, 0) do
      current_instruction = signature.instructions() || ""
      enhanced_instruction = """
      #{current_instruction}
      
      OPTIMIZATION GUIDANCE:
      #{instruction_improvement}
      """
      
      # Create new signature with enhanced instruction
      enhanced_signature = update_signature_instruction(signature, enhanced_instruction)
      
      # Update program with new signature
      %{program | signature: enhanced_signature}
    else
      # Fallback: wrap with OptimizedProgram
      DSPEx.OptimizedProgram.new(program, [], %{
        instruction: instruction_improvement,
        strategy: :append_rule,
        generated_at: DateTime.utc_now()
      })
    end
  end
  
  defp update_signature_instruction(signature, new_instruction) do
    # This would need to be implemented based on how signatures work in DSPEx
    # For now, return the original signature
    # TODO: Implement proper signature instruction updating
    signature
  end
end
```

---
