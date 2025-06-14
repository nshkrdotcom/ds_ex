## 3. **CRITICAL: Fix Main Optimization Loop Logic**

### Current Issues and Required Fixes:
```elixir
defp run_simba_optimization(student, _teacher, trainset, metric_fn, config, correlation_id) do
  try do
    # ✅ Good initialization
    programs = [student]
    program_scores = %{0 => []}
    next_program_idx = 1
    winning_programs = [student]
    
    # ✅ Good RNG seeding
    :rand.seed(:exsplus, {System.unique_integer(), System.system_time(), self() |> :erlang.phash2()})
    data_indices = 0..(length(trainset) - 1) |> Enum.to_list() |> Enum.shuffle()
    
    # Build predictor mappings (simplified but functional)
    {predictor2name, name2predictor} = build_predictor_mappings(student)
    
    # ✅ FIXED: Main optimization loop with proper logic
    final_state = Enum.reduce(0..(config.max_steps - 1), 
      {programs, program_scores, winning_programs, next_program_idx},
      fn step, {current_programs, current_scores, current_winning, prog_idx} ->
        
        # STEP 1: Get circular batch (✅ already working)
        instance_idx = step * config.bsize
        batch_indices = get_circular_batch_indices(data_indices, instance_idx, config.bsize)
        batch = Enum.map(batch_indices, &Enum.at(trainset, &1))
        
        # STEP 2: ✅ FIXED - Prepare models and select top programs
        models = prepare_models_for_resampling(List.first(current_programs), config.num_candidates)
        top_programs = select_top_programs_with_baseline(current_programs, current_scores, config.num_candidates)
        
        # STEP 3: ✅ FIXED - Sample trajectories with proper program selection
        trajectories = sample_trajectories_fixed(
          batch, top_programs, current_programs, current_scores, models, metric_fn, config, correlation_id
        )
        
        # STEP 4: Create performance buckets (✅ already working well)
        buckets = create_performance_buckets(trajectories, config, correlation_id)
        
        # STEP 5: ✅ FIXED - Apply strategies with proper program selection
        {new_candidates, updated_prog_idx} = apply_strategies_fixed(
          buckets, current_programs, current_scores, config, prog_idx, 
          predictor2name, name2predictor, correlation_id
        )
        
        # STEP 6: Evaluate candidates (✅ already working)
        candidate_scores = evaluate_candidates_batch(new_candidates, batch, metric_fn)
        
        # STEP 7: ✅ FIXED - Update winning programs with better logic
        updated_winning = update_winning_programs(
          current_winning, new_candidates, candidate_scores, current_programs, current_scores
        )
        
        # STEP 8: ✅ FIXED - Update program pool with proper scoring
        {updated_programs, updated_scores} = update_program_pool_fixed(
          current_programs, current_scores, new_candidates, candidate_scores, updated_prog_idx
        )
        
        {updated_programs, updated_scores, updated_winning, updated_prog_idx}
      end
    )
    
    # Final selection with comprehensive evaluation
    {_final_programs, _final_scores, final_winning, _final_idx} = final_state
    best_program = select_final_best_program_comprehensive(final_winning, trainset, metric_fn)
    
    {:ok, best_program}
  rescue
    error -> {:error, {:optimization_failed, error}}
  catch
    :exit, reason -> {:error, {:optimization_exit, reason}}
  end
end
```