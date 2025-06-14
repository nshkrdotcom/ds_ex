# Part I: Critical Algorithm Fixes Required

## 1. **CRITICAL: Fix Program Selection Algorithm**

### Current Broken Implementation:
```elixir
# ❌ BROKEN: Uses fixed scores instead of real performance
defp softmax_sample(program_indices, _all_programs, temperature) do
  scores = Enum.map(program_indices, fn _idx -> 0.5 end)  # FIXED SCORES!
  # This breaks the core SIMBA optimization logic
end
```

### Required Fix - Complete Implementation:
```elixir
defp softmax_sample(program_indices, program_scores, temperature) do
  if is_list(program_indices) and length(program_indices) > 0 do
    # ✅ Calculate real average scores for each program
    scores = Enum.map(program_indices, fn idx ->
      program_score_list = Map.get(program_scores, idx, [])
      if Enum.empty?(program_score_list) do
        0.0  # Default for programs with no evaluation history
      else
        Enum.sum(program_score_list) / length(program_score_list)
      end
    end)
    
    # Apply temperature scaling and softmax
    if temperature > 0 do
      exp_scores = Enum.map(scores, fn score -> :math.exp(score / temperature) end)
      sum_exp = Enum.sum(exp_scores)
      
      if sum_exp > 0 do
        probabilities = Enum.map(exp_scores, fn exp_score -> exp_score / sum_exp end)
        weighted_random_choice(probabilities)
      else
        # Fallback to uniform random if all scores are zero
        :rand.uniform(length(program_indices)) - 1
      end
    else
      # Temperature = 0: always pick best scoring program
      {_max_score, max_idx} = 
        scores 
        |> Enum.with_index() 
        |> Enum.max_by(fn {score, _} -> score end)
      max_idx
    end
  else
    0  # Default to first program if no valid indices
  end
end

defp weighted_random_choice(probabilities) do
  random_val = :rand.uniform()
  
  probabilities
  |> Enum.with_index()
  |> Enum.reduce_while(0.0, fn {prob, idx}, acc ->
    new_acc = acc + prob
    if random_val <= new_acc do
      {:halt, idx}
    else
      {:cont, new_acc}
    end
  end)
end
```
