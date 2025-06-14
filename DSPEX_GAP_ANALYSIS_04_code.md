## 4. **NEW: Fixed Trajectory Sampling**

### Current Over-Complex Implementation Needs Simplification:
```elixir
defp sample_trajectories_fixed(batch, top_program_indices, all_programs, program_scores, models, metric_fn, config, correlation_id) do
  emit_telemetry([:dspex, :teleprompter, :simba, :trajectory, :start], 
    %{trajectory_count: length(batch) * length(models)}, 
    %{correlation_id: correlation_id})
  
  # Create execution pairs: for each example, for each model config, pick a program
  exec_pairs = for {example, example_idx} <- Enum.with_index(batch),
                   {model_config, model_idx} <- Enum.with_index(models) do
    # ✅ FIXED: Use proper program selection with real scores
    chosen_prog_idx = softmax_sample(top_program_indices, program_scores, config.temperature_for_sampling)
    candidate_program = Enum.at(all_programs, chosen_prog_idx)
    
    exec_id = example_idx * length(models) + model_idx
    {candidate_program, model_config, example, exec_id}
  end
  
  # Execute all trajectory pairs in parallel
  trajectories = exec_pairs
    |> Task.async_stream(
      fn {program, model_config, example, exec_id} ->
        execute_with_trajectory_fixed(program, example, model_config, metric_fn, exec_id)
      end,
      max_concurrency: config.num_threads || 20,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(fn {:ok, trajectory} -> trajectory end)
    |> Enum.to_list()
  
  emit_telemetry([:dspex, :teleprompter, :simba, :trajectory, :sampled], 
    %{trajectory_count: length(trajectories)}, 
    %{correlation_id: correlation_id})
  
  trajectories
end

defp execute_with_trajectory_fixed(program, example, model_config, metric_fn, exec_id) do
  start_time = System.monotonic_time()
  inputs = Example.inputs(example)
  
  # Convert model config to execution options
  execution_opts = [
    temperature: Map.get(model_config, :temperature, 0.7),
    timeout: 30_000
  ]
  
  case Program.forward(program, inputs, execution_opts) do
    {:ok, outputs} ->
      score = try do
        metric_fn.(example, outputs)
      rescue
        _ -> 0.0
      catch
        _ -> 0.0
      end
      
      %Trajectory{
        program: program,
        example: example,
        inputs: inputs,
        outputs: outputs,
        score: score,
        duration: System.monotonic_time() - start_time,
        model_config: model_config,
        success: true,
        metadata: %{exec_id: exec_id, program_type: Program.program_type(program)}
      }
      
    {:error, reason} ->
      %Trajectory{
        program: program,
        example: example,
        inputs: inputs,
        outputs: %{},
        score: 0.0,
        duration: System.monotonic_time() - start_time,
        model_config: model_config,
        success: false,
        error: reason,
        metadata: %{exec_id: exec_id, program_type: Program.program_type(program)}
      }
  end
rescue
  error ->
    %Trajectory{
      program: program,
      example: example,
      inputs: Example.inputs(example),
      outputs: %{},
      score: 0.0,
      duration: 0,
      model_config: model_config,
      success: false,
      error: error,
      metadata: %{exec_id: exec_id, error_type: :execution_exception}
    }
end
```

## 5. **NEW: Fixed Strategy Application**

```elixir
defp apply_strategies_fixed(buckets, programs, program_scores, config, next_program_idx, predictor2name, name2predictor, correlation_id) do
  # Filter buckets with improvement potential
  viable_buckets = Enum.filter(buckets, fn bucket ->
    bucket.metadata[:max_to_min_gap] > 0.01 and bucket.metadata[:max_score] > 0.1
  end)
  
  # Sort and take top buckets for strategy application
  top_buckets = viable_buckets
    |> Enum.sort_by(fn bucket ->
      {-bucket.metadata[:max_to_min_gap], -bucket.metadata[:max_score]}
    end)
    |> Enum.take(config.num_candidates)
  
  emit_telemetry([:dspex, :teleprompter, :simba, :strategy, :start], 
    %{viable_buckets: length(viable_buckets), selected_buckets: length(top_buckets)}, 
    %{correlation_id: correlation_id})
  
  # Apply strategies to each viable bucket
  {candidates, updated_idx} = Enum.reduce(top_buckets, {[], next_program_idx}, 
    fn bucket, {acc_candidates, current_idx} ->
      # ✅ FIXED: Select source program using real scores and softmax
      program_indices = 0..(length(programs) - 1) |> Enum.to_list()
      source_program_idx = softmax_sample(program_indices, program_scores, config.temperature_for_candidates)
      source_program = Enum.at(programs, source_program_idx)
      
      # Apply the first applicable strategy
      case apply_first_applicable_strategy(bucket, source_program, config.strategies, 
                                         predictor2name, name2predictor, config) do
        {:ok, new_program} ->
          {[new_program | acc_candidates], current_idx + 1}
        {:skip, _reason} ->
          {acc_candidates, current_idx}
      end
    end
  )
  
  emit_telemetry([:dspex, :teleprompter, :simba, :strategy, :applied], 
    %{candidates_created: length(candidates)}, 
    %{correlation_id: correlation_id})
  
  {Enum.reverse(candidates), updated_idx}
end
```

## 6. **NEW: Enhanced Program Pool Updates**

```elixir
defp update_program_pool_fixed(programs, program_scores, new_candidates, candidate_scores, next_idx) do
  # Add new candidates to program list
  updated_programs = programs ++ new_candidates
  
  # Update scores with new candidate results
  updated_scores = Enum.reduce(candidate_scores, program_scores, 
    fn {candidate_idx, score}, acc ->
      program_idx = length(programs) + candidate_idx
      Map.update(acc, program_idx, [score], &[score | &1])
    end
  )
  
  # Prune program pool if it gets too large (keep top performers + baseline)
  if length(updated_programs) > 50 do  # Configurable threshold
    prune_program_pool(updated_programs, updated_scores, 30)  # Keep top 30
  else
    {updated_programs, updated_scores}
  end
end

defp prune_program_pool(programs, program_scores, keep_count) do
  # Calculate average scores for all programs
  program_performance = programs
    |> Enum.with_index()
    |> Enum.map(fn {program, idx} ->
      avg_score = calculate_average_score(program_scores, idx)
      {program, idx, avg_score}
    end)
    |> Enum.sort_by(fn {_program, _idx, score} -> -score end)
  
  # Always keep baseline (index 0) and top performers
  baseline_entry = Enum.find(program_performance, fn {_program, idx, _score} -> idx == 0 end)
  top_performers = program_performance 
    |> Enum.reject(fn {_program, idx, _score} -> idx == 0 end)
    |> Enum.take(keep_count - 1)
  
  kept_entries = [baseline_entry | top_performers] |> Enum.reject(&is_nil/1)
  
  # Rebuild programs and scores with new indices
  new_programs = Enum.map(kept_entries, fn {program, _old_idx, _score} -> program end)
  new_scores = kept_entries
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{_program, old_idx, _score}, new_idx}, acc ->
      old_scores = Map.get(program_scores, old_idx, [])
      Map.put(acc, new_idx, old_scores)
    end)
  
  {new_programs, new_scores}
end

defp update_winning_programs(current_winning, new_candidates, candidate_scores, all_programs, program_scores) do
  # Find best candidate from this iteration
  best_candidate = case candidate_scores do
    [] -> nil
    scores ->
      {best_idx, best_score} = Enum.max_by(scores, fn {_idx, score} -> score end)
      if best_score > 0.5 do  # Configurable threshold
        Enum.at(new_candidates, best_idx)
      else
        nil
      end
  end
  
  # Add to winning programs if it's a good candidate
  case best_candidate do
    nil -> current_winning
    candidate -> 
      # Limit winning programs list size
      updated_list = [candidate | current_winning]
      if length(updated_list) > 20 do  # Configurable
        Enum.take(updated_list, 20)
      else
        updated_list
      end
  end
end
```

---

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
