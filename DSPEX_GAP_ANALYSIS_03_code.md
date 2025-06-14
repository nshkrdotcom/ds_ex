```elixir
  def get_preset(:balanced) do
    @default_config
  end
  
  def get_preset(:thorough) do
    Map.merge(@default_config, %{
      max_steps: 50,
      bsize: 2,
      num_candidates: 16,
      num_threads: 30,
      early_stopping_patience: 10,
      min_improvement_threshold: 0.005,
      trajectory_retention: 2000,
      adaptive_batch_size: true,
      dynamic_candidate_count: true
    })
  end
  
  def get_preset(:memory_efficient) do
    Map.merge(@default_config, %{
      max_steps: 15,
      bsize: 2,
      num_candidates: 4,
      num_threads: 8,
      memory_limit_mb: 128,
      trajectory_retention: 100,
      evaluation_batch_size: 5
    })
  end
  
  defp validate_config(config) do
    with :ok <- validate_positive_integers(config),
         :ok <- validate_temperature_ranges(config),
         :ok <- validate_strategies(config),
         :ok <- validate_memory_settings(config) do
      :ok
    end
  end
  
  defp validate_positive_integers(config) do
    required_positive = [:max_steps, :bsize, :num_candidates, :num_threads, 
                         :early_stopping_patience, :memory_limit_mb, 
                         :trajectory_retention, :evaluation_batch_size]
    
    invalid_fields = Enum.filter(required_positive, fn field ->
      value = Map.get(config, field)
      not is_integer(value) or value <= 0
    end)
    
    if Enum.empty?(invalid_fields) do
      :ok
    else
      {:error, {:invalid_positive_integers, invalid_fields}}
    end
  end
  
  defp validate_temperature_ranges(config) do
    temp_fields = [:temperature_for_sampling, :temperature_for_candidates, :min_improvement_threshold]
    
    invalid_temps = Enum.filter(temp_fields, fn field ->
      value = Map.get(config, field)
      not is_number(value) or value < 0 or value > 10
    end)
    
    if Enum.empty?(invalid_temps) do
      :ok
    else
      {:error, {:invalid_temperature_ranges, invalid_temps}}
    end
  end
  
  defp validate_strategies(config) do
    strategies = Map.get(config, :strategies, [])
    
    cond do
      not is_list(strategies) ->
        {:error, :strategies_must_be_list}
      
      Enum.empty?(strategies) ->
        {:error, :strategies_cannot_be_empty}
      
      not all_valid_strategies?(strategies) ->
        {:error, :invalid_strategy_format}
      
      true ->
        :ok
    end
  end
  
  defp all_valid_strategies?(strategies) do
    Enum.all?(strategies, fn strategy ->
      is_map(strategy) and
      Map.has_key?(strategy, :name) and
      Map.has_key?(strategy, :weight) and
      Map.has_key?(strategy, :params) and
      is_atom(strategy.name) and
      is_number(strategy.weight) and
      strategy.weight >= 0 and
      strategy.weight <= 1 and
      is_map(strategy.params)
    end)
  end
  
  defp validate_memory_settings(config) do
    memory_limit = Map.get(config, :memory_limit_mb)
    trajectory_retention = Map.get(config, :trajectory_retention)
    
    # Rough estimate: each trajectory ~1KB, so warn if retention might exceed memory limit
    estimated_trajectory_memory = trajectory_retention * 1024 / (1024 * 1024)  # Convert to MB
    
    if estimated_trajectory_memory > memory_limit * 0.8 do
      {:error, {:memory_settings_incompatible, 
        "Trajectory retention (#{trajectory_retention}) may exceed memory limit (#{memory_limit}MB)"}}
    else
      :ok
    end
  end
  
  defp normalize_config(config) do
    config
    |> ensure_correlation_id()
    |> normalize_strategy_weights()
    |> validate_temperature_schedule()
  end
  
  defp ensure_correlation_id(config) do
    if is_nil(config.correlation_id) do
      correlation_id = "simba_" <> Base.encode16(:crypto.strong_rand_bytes(8))
      Map.put(config, :correlation_id, correlation_id)
    else
      config
    end
  end
  
  defp normalize_strategy_weights(config) do
    strategies = config.strategies
    total_weight = Enum.reduce(strategies, 0.0, fn strategy, acc -> 
      acc + strategy.weight 
    end)
    
    if total_weight > 0 do
      normalized_strategies = Enum.map(strategies, fn strategy ->
        %{strategy | weight: strategy.weight / total_weight}
      end)
      
      Map.put(config, :strategies, normalized_strategies)
    else
      # If all weights are 0, distribute equally
      equal_weight = 1.0 / length(strategies)
      normalized_strategies = Enum.map(strategies, fn strategy ->
        %{strategy | weight: equal_weight}
      end)
      
      Map.put(config, :strategies, normalized_strategies)
    end
  end
  
  defp validate_temperature_schedule(config) do
    valid_schedules = [:linear, :exponential, :cosine, :adaptive]
    
    if config.temperature_schedule in valid_schedules do
      config
    else
      Map.put(config, :temperature_schedule, :cosine)  # Default fallback
    end
  end
  
  @spec merge_with_overrides(config(), map()) :: config()
  def merge_with_overrides(base_config, overrides) do
    Map.merge(base_config, overrides)
  end
  
  @spec to_summary(config()) :: map()
  def to_summary(config) do
    %{
      algorithm: %{
        max_steps: config.max_steps,
        batch_size: config.bsize,
        num_candidates: config.num_candidates,
        temperature_schedule: config.temperature_schedule
      },
      strategies: Enum.map(config.strategies, fn s -> 
        "#{s.name}(#{Float.round(s.weight, 2)})" 
      end),
      performance: %{
        num_threads: config.num_threads,
        memory_limit_mb: config.memory_limit_mb,
        trajectory_retention: config.trajectory_retention
      },
      features: %{
        convergence_detection: config.convergence_detection,
        adaptive_batch_size: config.adaptive_batch_size,
        dynamic_candidate_count: config.dynamic_candidate_count,
        predictor_analysis: config.predictor_analysis
      }
    }
  end
end
```

## 14. **NEW: Complete Integration Test Suite**

```elixir
defmodule DSPEx.Teleprompter.SIMBA.IntegrationTest do
  @moduledoc """
  Comprehensive integration test suite to validate SIMBA implementation completeness.
  """
  
  use ExUnit.Case, async: true
  
  alias DSPEx.Teleprompter.SIMBA
  alias DSPEx.{Program, Example}
  
  describe "SIMBA Algorithm Completeness" do
    test "full optimization loop with real data" do
      # Setup
      {student_program, trainset, metric_fn} = setup_test_scenario()
      config = SIMBA.Config.get_preset(:fast)
      
      # Execute SIMBA optimization
      result = SIMBA.optimize(student_program, trainset, metric_fn, config)
      
      # Verify results
      assert {:ok, optimized_program} = result
      assert not is_nil(optimized_program)
      
      # Verify the optimized program performs better than baseline
      baseline_score = evaluate_program(student_program, trainset, metric_fn)
      optimized_score = evaluate_program(optimized_program, trainset, metric_fn)
      
      assert optimized_score >= baseline_score
    end
    
    test "program selection algorithm uses real scores" do
      config = SIMBA.Config.new!(%{num_candidates: 3})
      
      # Create programs with known performance differences
      {programs, program_scores} = setup_programs_with_scores()
      
      # Test multiple selections to verify score-based sampling
      selections = for _ <- 1..100 do
        SIMBA.softmax_sample([0, 1, 2], program_scores, 1.0)
      end
      
      # Higher-scoring programs should be selected more frequently
      selection_counts = Enum.frequencies(selections)
      
      # Program 2 (score 0.9) should be selected most
      # Program 1 (score 0.5) should be selected moderately  
      # Program 0 (score 0.1) should be selected least
      assert selection_counts[2] > selection_counts[1]
      assert selection_counts[1] > selection_counts[0]
    end
    
    test "strategy application creates valid program variants" do
      {source_program, bucket} = setup_strategy_test()
      config = SIMBA.Config.new!()
      
      # Test AppendDemo strategy
      result = SIMBA.Strategy.AppendDemo.apply(bucket, source_program)
      
      assert {:ok, enhanced_program} = result
      assert enhanced_program != source_program
      
      # Enhanced program should have additional demonstrations
      source_demos = extract_demonstrations(source_program)
      enhanced_demos = extract_demonstrations(enhanced_program)
      assert length(enhanced_demos) > length(source_demos)
    end
    
    test "bucket analysis provides meaningful insights" do
      trajectories = generate_test_trajectories()
      config = SIMBA.Config.new!()
      
      buckets = SIMBA.create_performance_buckets(trajectories, config, "test")
      
      assert length(buckets) > 0
      
      # Verify bucket statistics are calculated correctly
      for bucket <- buckets do
        assert is_number(bucket.max_score)
        assert is_number(bucket.min_score)
        assert is_number(bucket.avg_score)
        assert bucket.max_score >= bucket.avg_score
        assert bucket.avg_score >= bucket.min_score
        
        # Verify metadata calculations
        assert bucket.metadata[:max_to_min_gap] == bucket.max_score - bucket.min_score
        assert bucket.metadata[:max_to_avg_gap] == bucket.max_score - bucket.avg_score
      end
    end
    
    test "convergence detection works correctly" do
      convergence_state = SIMBA.Convergence.new()
      
      # Simulate improving performance
      improving_scores = [0.1, 0.3, 0.5, 0.7, 0.85, 0.9, 0.91, 0.91, 0.91]
      
      final_state = improving_scores
        |> Enum.with_index()
        |> Enum.reduce(convergence_state, fn {score, step}, state ->
          SIMBA.Convergence.update(state, score, step)
        end)
      
      assert final_state.converged?
      assert final_state.convergence_reason in [:score_plateau, :minimal_improvement]
    end
    
    test "memory management prevents excessive memory usage" do
      # Start trajectory manager with low limits
      {:ok, _pid} = SIMBA.TrajectoryManager.start_link(
        max_trajectories: 10,
        compression_threshold: 5
      )
      
      # Store many trajectories
      trajectories = generate_test_trajectories(count: 20)
      
      Enum.each(trajectories, fn trajectory ->
        SIMBA.TrajectoryManager.store_trajectory(trajectory)
      end)
      
      # Verify memory management kicked in
      stats = SIMBA.TrajectoryManager.get_trajectory_statistics()
      assert stats.total_trajectories <= 10
      assert stats.total_summaries > 0  # Some should be compressed
    end
    
    test "temperature scheduling affects exploration properly" do
      scheduler = SIMBA.TemperatureScheduler.new(:cosine, 2.0, 10)
      
      # Simulate optimization steps
      temperatures = for step <- 0..9 do
        updated_scheduler = SIMBA.TemperatureScheduler.update(scheduler, 0.5)
        updated_scheduler.current_temp
      end
      
      # Temperature should generally decrease over time
      assert List.first(temperatures) > List.last(temperatures)
      assert Enum.all?(temperatures, &(&1 >= 0))
    end
  end
  
  describe "Error Handling and Edge Cases" do
    test "handles empty training set gracefully" do
      student_program = create_simple_program()
      empty_trainset = []
      metric_fn = &simple_metric/2
      config = SIMBA.Config.new!()
      
      result = SIMBA.optimize(student_program, empty_trainset, metric_fn, config)
      
      assert {:error, reason} = result
      assert reason =~ "empty"
    end
    
    test "handles metric function errors gracefully" do
      {student_program, trainset, _} = setup_test_scenario()
      
      # Metric function that always throws errors
      error_metric = fn _, _ -> raise "Metric error" end
      
      config = SIMBA.Config.new!(%{max_steps: 2})
      
      result = SIMBA.optimize(student_program, trainset, error_metric, config)
      
      # Should complete despite metric errors (with 0 scores)
      assert {:ok, _optimized_program} = result
    end
    
    test "handles program execution failures gracefully" do
      # Program that always fails
      failing_program = create_failing_program()
      trainset = generate_simple_trainset()
      metric_fn = &simple_metric/2
      
      config = SIMBA.Config.new!(%{max_steps: 2})
      
      result = SIMBA.optimize(failing_program, trainset, metric_fn, config)
      
      # Should complete and return a program (possibly the original)
      assert {:ok, _result_program} = result
    end
  end
  
  describe "Performance Benchmarks" do
    test "optimization completes within reasonable time" do
      {student_program, trainset, metric_fn} = setup_test_scenario()
      config = SIMBA.Config.get_preset(:fast)
      
      {time_microseconds, result} = :timer.tc(fn ->
        SIMBA.optimize(student_program, trainset, metric_fn, config)
      end)
      
      assert {:ok, _optimized_program} = result
      
      # Should complete within 30 seconds for fast preset
      time_seconds = time_microseconds / 1_000_000
      assert time_seconds < 30
    end
    
    test "memory usage stays within bounds" do
      initial_memory = :erlang.memory(:total)
      
      {student_program, trainset, metric_fn} = setup_test_scenario()
      config = SIMBA.Config.new!(%{memory_limit_mb: 100})
      
      result = SIMBA.optimize(student_program, trainset, metric_fn, config)
      assert {:ok, _optimized_program} = result
      
      final_memory = :erlang.memory(:total)
      memory_increase_mb = (final_memory - initial_memory) / (1024 * 1024)
      
      # Memory increase should be reasonable (allowing some overhead)
      assert memory_increase_mb < 150
    end
  end
  
  # Test Helpers
  
  defp setup_test_scenario() do
    student_program = create_simple_program()
    trainset = generate_simple_trainset()
    metric_fn = &simple_metric/2
    
    {student_program, trainset, metric_fn}
  end
  
  defp setup_programs_with_scores() do
    programs = [
      create_simple_program(),
      create_simple_program(),
      create_simple_program()
    ]
    
    program_scores = %{
      0 => [0.1, 0.1, 0.1],  # Consistently poor
      1 => [0.4, 0.5, 0.6],  # Moderate performance
      2 => [0.8, 0.9, 0.9]   # High performance
    }
    
    {programs, program_scores}
  end
  
  defp setup_strategy_test() do
    source_program = create_simple_program()
    
    # Create a bucket with clear performance gaps
    high_score_trajectory = create_test_trajectory(0.9)
    low_score_trajectory = create_test_trajectory(0.2)
    
    bucket = %SIMBA.Bucket{
      trajectories: [high_score_trajectory, low_score_trajectory],
      max_score: 0.9,
      min_score: 0.2,
      avg_score: 0.55,
      max_to_min_gap: 0.7,
      max_to_avg_gap: 0.35,
      metadata: %{
        max_to_min_gap: 0.7,
        max_to_avg_gap: 0.35,
        max_score: 0.9,
        avg_score: 0.55
      }
    }
    
    {source_program, bucket}
  end
  
  defp generate_test_trajectories(opts \\ []) do
    count = Keyword.get(opts, :count, 10)
    
    for i <- 1..count do
      score = :rand.uniform() * 0.8 + 0.1  # Random score between 0.1 and 0.9
      create_test_trajectory(score)
    end
  end
  
  defp create_test_trajectory(score) do
    %SIMBA.Trajectory{
      program: create_simple_program(),
      example: create_test_example(),
      inputs: %{question: "Test question #{:rand.uniform(1000)}"},
      outputs: %{answer: "Test answer"},
      score: score,
      duration: :rand.uniform(1000),
      model_config: %{temperature: 0.7},
      success: true,
      metadata: %{program_type: :test}
    }
  end
  
  defp create_test_example() do
    %Example{
      inputs: %{question: "What is 2+2?"},
      outputs: %{answer: "4"}
    }
  end
  
  defp create_simple_program() do
    # Simplified program for testing
    %{
      signature: %{instructions: "Answer the question correctly."},
      forward: fn inputs -> 
        {:ok, %{answer: "Generated answer for: #{inputs[:question]}"}}
      end
    }
  end
  
  defp create_failing_program() do
    %{
      forward: fn _inputs -> 
        {:error, "Program always fails"}
      end
    }
  end
  
  defp generate_simple_trainset() do
    [
      %Example{
        inputs: %{question: "What is 1+1?"},
        outputs: %{answer: "2"}
      },
      %Example{
        inputs: %{question: "What is 2+2?"},
        outputs: %{answer: "4"}
      },
      %Example{
        inputs: %{question: "What is 3+3?"},
        outputs: %{answer: "6"}
      }
    ]
  end
  
  defp simple_metric(example, outputs) do
    expected = example.outputs[:answer]
    actual = outputs[:answer]
    
    if expected == actual do
      1.0
    else
      0.0
    end
  end
  
  defp evaluate_program(program, trainset, metric_fn) do
    scores = Enum.map(trainset, fn example ->
      case program.forward.(example.inputs) do
        {:ok, outputs} -> metric_fn.(example, outputs)
        {:error, _} -> 0.0
      end
    end)
    
    if Enum.empty?(scores) do
      0.0
    else
      Enum.sum(scores) / length(scores)
    end
  end
  
  defp extract_demonstrations(program) do
    # Simplified demonstration extraction for testing
    case program do
      %{demos: demos} when is_list(demos) -> demos
      _ -> []
    end
  end
end
```

---

# Part VI: Final Implementation Roadmap

## 15. **Critical Implementation Priority List**

### **IMMEDIATE (Blocking Issues - Must Fix First)**

1. **Fix Broken Program Selection** ⚠️ CRITICAL
   - Replace fixed `0.5` scores with real performance calculation
   - Implement proper `calculate_average_score/2` function
   - Fix `softmax_sample/3` to use actual program scores

2. **Implement Missing `select_top_programs_with_baseline/3`** ⚠️ CRITICAL
   - Essential for program pool management
   - Ensures baseline program is always included
   - Drives optimization efficiency

3. **Fix Main Optimization Loop Logic** ⚠️ CRITICAL
   - Replace placeholder logic with real algorithm steps
   - Implement proper program updates and score tracking
   - Add convergence detection integration

### **HIGH PRIORITY (Core Algorithm Completion)**

4. **Complete Strategy System**
   - Implement `AppendRule` strategy (provided above)
   - Add strategy selection logic (random vs weighted)
   - Integrate strategy applicability checking

5. **Enhance Program Pool Management**
   - Implement program pool pruning for memory efficiency
   - Add proper program indexing and retrieval
   - Fix winning program selection logic

6. **Improve Trajectory Sampling**
   - Simplify over-complex execution pair generation
   - Fix program selection within trajectory sampling
   - Optimize parallel execution efficiency

### **MEDIUM PRIORITY (Enhanced Features)**

7. **Add Convergence Detection**
   - Integrate convergence monitoring into main loop
   - Implement early stopping based on plateau detection
   - Add performance-based convergence criteria

8. **Implement Temperature Scheduling**
   - Add adaptive temperature adjustment
   - Integrate with program selection logic
   - Support multiple scheduling strategies

9. **Enhanced Evaluation System**
   - Add comprehensive metric calculation
   - Implement statistical analysis of results
   - Support multiple evaluation modes

### **LOW PRIORITY (Advanced Features)**

10. **Memory Management**
    - Implement trajectory compression and cleanup
    - Add memory usage monitoring
    - Support large-scale optimization scenarios

11. **Advanced Configuration**
    - Complete configuration validation
    - Add preset configurations for different use cases
    - Implement dynamic parameter adjustment

12. **Performance Optimizations**
    - Optimize batch processing efficiency
    - Improve parallel execution performance
    - Add caching for expensive operations

---

## 16. **Code Completion Estimate**

### **Current Implementation Status:**
- **Infrastructure**: 95% complete ✅
- **Data Structures**: 100% complete ✅  
- **Core Algorithm**: 40% complete ⚠️
- **Strategy System**: 60% complete ⚠️
- **Evaluation**: 80% complete ✅
- **Configuration**: 70% complete ✅
- **Documentation**: 90% complete ✅

### **Estimated Development Time:**
- **Fix Critical Issues**: 2-3 days
- **Complete Core Algorithm**: 3-4 days  
- **Add Missing Strategies**: 1-2 days
- **Enhanced Features**: 2-3 days
- **Testing & Integration**: 1-2 days

**Total Estimated Time**: 9-14 days for full completion

### **Success Metrics:**
1. All integration tests pass
2. Algorithm produces better results than baseline on test data
3. Memory usage stays within configured limits
4. Optimization completes within reasonable time bounds
5. Error handling works for all edge cases

---

## 17. **Final Architecture Summary**

The DSPEx SIMBA implementation has:

### **Excellent Foundation:**
- ✅ Superior OTP/BEAM architecture with proper concurrency
- ✅ Comprehensive error handling and telemetry
- ✅ Well-designed type system and data structures
- ✅ Outstanding engineering practices and documentation

### **Critical Algorithmic Gaps:**
- ❌ Broken program selection using fixed scores instead of performance
- ❌ Missing sophisticated program pool management
- ❌ Incomplete strategy system with only partial implementations
- ❌ Oversimplified optimization logic missing key SIMBA components

### **The Path Forward:**
The implementation roadmap above provides:
1. **Specific code fixes** for all critical blocking issues
2. **Complete implementations** for missing algorithmic components  
3. **Integration guidance** for bringing all pieces together
4. **Testing framework** to validate correctness and performance
5. **Performance benchmarks** to ensure production readiness

**Bottom Line**: DSPEx has built an excellent foundation but needs the core SIMBA algorithm completed. With the detailed specifications and code provided above, the implementation can be finished to achieve full functional parity with Python DSPy's SIMBA while leveraging Elixir's superior concurrency and fault-tolerance capabilities.

The missing ~40% of algorithmic implementation represents the difference between having great infrastructure and having a working optimization algorithm. All the pieces needed to close this gap are documented in this specification.
