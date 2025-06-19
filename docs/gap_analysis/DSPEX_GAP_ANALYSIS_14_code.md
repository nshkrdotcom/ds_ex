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
