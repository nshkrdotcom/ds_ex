## 2. **CRITICAL: Implement Program Pool Management**

### Missing Component - Top-K Selection with Baseline:
```elixir
defp select_top_programs_with_baseline(programs, program_scores, num_candidates) do
  # Calculate average scores for all programs
  program_avg_scores = 
    programs
    |> Enum.with_index()
    |> Enum.map(fn {_program, idx} ->
      scores = Map.get(program_scores, idx, [])
      avg_score = if Enum.empty?(scores) do
        if idx == 0, do: 0.1, else: 0.0  # Give baseline slight preference
      else
        Enum.sum(scores) / length(scores)
      end
      {idx, avg_score}
    end)
    |> Enum.sort_by(fn {_idx, score} -> -score end)  # Sort by descending score
  
  # Take top K programs
  top_k_indices = 
    program_avg_scores
    |> Enum.take(num_candidates)
    |> Enum.map(fn {idx, _score} -> idx end)
  
  # Ensure baseline program (index 0) is always included
  if 0 in top_k_indices do
    top_k_indices
  else
    # Replace worst performer with baseline
    [0 | Enum.take(top_k_indices, num_candidates - 1)]
  end
end

defp calculate_average_score(program_scores, program_idx) do
  scores = Map.get(program_scores, program_idx, [])
  if Enum.empty?(scores) do
    if program_idx == 0, do: 0.1, else: 0.0
  else
    Enum.sum(scores) / length(scores)
  end
end
```