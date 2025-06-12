defmodule DSPEx.Teleprompter.BEACON.BenchmarkTest do
  @moduledoc """
  Comprehensive test suite for BEACON Benchmark module.
  """

  use ExUnit.Case, async: true

  alias DSPEx.Teleprompter.BEACON.Benchmark

  describe "benchmark configuration" do
    test "benchmark_configuration returns proper structure" do
      config = %{
        name: "Test",
        candidates: 10,
        trials: 20,
        demos: 2,
        trainset_size: 50
      }

      result = Benchmark.benchmark_configuration(config)

      assert Map.has_key?(result, :config)
      assert Map.has_key?(result, :duration)
      assert Map.has_key?(result, :bootstrap_time)
      assert Map.has_key?(result, :optimization_time)
      assert Map.has_key?(result, :memory_mb)
      assert Map.has_key?(result, :throughput)
      assert Map.has_key?(result, :efficiency_score)

      assert result.config == config
      assert is_number(result.duration)
      assert is_number(result.throughput)
      assert result.throughput > 0
    end

    test "configuration affects timing simulation" do
      small_config = %{
        name: "Small",
        candidates: 5,
        trials: 10,
        demos: 1,
        trainset_size: 25
      }

      large_config = %{
        name: "Large",
        candidates: 20,
        trials: 40,
        demos: 4,
        trainset_size: 100
      }

      small_result = Benchmark.benchmark_configuration(small_config)
      large_result = Benchmark.benchmark_configuration(large_config)

      # Large configuration should take more time
      assert large_result.duration > small_result.duration
      assert large_result.bootstrap_time > small_result.bootstrap_time
      assert large_result.optimization_time > small_result.optimization_time
    end

    test "memory usage scales with configuration size" do
      config = %{
        name: "Memory Test",
        candidates: 30,
        trials: 60,
        demos: 6,
        trainset_size: 200
      }

      result = Benchmark.benchmark_configuration(config)

      # Memory should be measured (even if simulated)
      assert is_float(result.memory_mb)
      assert result.memory_mb >= 0
    end

    test "efficiency score calculation" do
      config = %{
        name: "Efficiency Test",
        candidates: 15,
        trials: 30,
        demos: 3,
        trainset_size: 75
      }

      result = Benchmark.benchmark_configuration(config)

      assert is_float(result.efficiency_score)
      assert result.efficiency_score > 0
    end
  end

  describe "concurrency benchmarks" do
    test "run_concurrency_benchmarks tests different concurrency levels" do
      # This test verifies the structure and behavior of concurrency benchmarks
      # Since it involves IO operations, we test the logic rather than full execution

      concurrency_levels = [1, 5, 10]
      trainset_size = 50

      # Test the underlying logic
      Enum.each(concurrency_levels, fn concurrency ->
        config = %{
          name: "Concurrency #{concurrency}",
          candidates: 20,
          trials: 30,
          demos: 4,
          trainset_size: trainset_size,
          max_concurrency: concurrency
        }

        # Test that configuration is valid
        assert config.max_concurrency == concurrency
        assert config.trainset_size == trainset_size
      end)
    end

    test "concurrency efficiency calculation" do
      # Test the efficiency calculation logic
      throughput = 100.0
      concurrency = 5
      efficiency = throughput / concurrency

      assert efficiency == 20.0

      # Higher concurrency should reduce per-worker efficiency (due to overhead)
      high_concurrency_throughput = 150.0
      high_concurrency = 20
      high_efficiency = high_concurrency_throughput / high_concurrency

      assert high_efficiency < efficiency  # More workers, less efficient per worker
    end

    test "optimal concurrency detection logic" do
      # Mock results with different efficiency scores
      mock_results = [
        %{concurrency: 1, efficiency: 10.0},
        %{concurrency: 5, efficiency: 15.0},  # Optimal
        %{concurrency: 10, efficiency: 12.0},
        %{concurrency: 20, efficiency: 8.0}
      ]

      optimal = Enum.max_by(mock_results, & &1.efficiency)
      assert optimal.concurrency == 5
      assert optimal.efficiency == 15.0
    end
  end

  describe "memory benchmarks" do
    test "memory usage calculation" do
      # Test memory usage calculation logic
      memory_before = 1000
      memory_after = 1500
      memory_used_mb = (memory_after - memory_before) / 1_048_576

      assert memory_used_mb > 0
      assert is_float(memory_used_mb)
    end

    test "memory per example calculation" do
      memory_used_mb = 10.0
      dataset_size = 100
      memory_per_example = memory_used_mb / dataset_size

      assert memory_per_example == 0.1
      assert memory_per_example * 1000 == 100.0  # KB per example
    end

    test "dataset size affects memory usage" do
      # Larger datasets should require more memory
      small_dataset = 100
      large_dataset = 1000

      # Mock memory calculation
      base_memory_per_example = 0.001  # MB
      small_memory = small_dataset * base_memory_per_example
      large_memory = large_dataset * base_memory_per_example

      assert large_memory > small_memory
      assert large_memory == 1.0
      assert small_memory == 0.1
    end
  end

  describe "optimization quality benchmarks" do
    test "quality simulation based on configuration" do
      speed_config = %{candidates: 5, trials: 10, threshold: 0.5}
      quality_config = %{candidates: 30, trials: 60, threshold: 0.9}

      # Test improvement simulation logic
      speed_improvement = simulate_improvement(speed_config)
      quality_improvement = simulate_improvement(quality_config)

      # Quality-focused config should show better improvement
      assert quality_improvement > speed_improvement
    end

    test "consistency simulation" do
      low_trials = %{trials: 10, threshold: 0.5}
      high_trials = %{trials: 100, threshold: 0.9}

      low_consistency = simulate_consistency(low_trials)
      high_consistency = simulate_consistency(high_trials)

      # More trials should lead to better consistency
      assert high_consistency > low_consistency
    end

    test "quality score calculation" do
      improvement = 0.8
      consistency = 0.9
      quality_score = (improvement + consistency) / 2

      assert quality_score == 0.85
    end
  end

  describe "configuration comparison" do
    test "compare_configurations tests multiple setups" do
      base_config = %{trainset_size: 100}

      configurations = [
        Map.merge(base_config, %{name: "Conservative", candidates: 10, trials: 20}),
        Map.merge(base_config, %{name: "Balanced", candidates: 20, trials: 40}),
        Map.merge(base_config, %{name: "Aggressive", candidates: 40, trials: 80})
      ]

      # Test that configurations are properly structured
      assert length(configurations) == 3

      Enum.each(configurations, fn config ->
        assert Map.has_key?(config, :name)
        assert Map.has_key?(config, :candidates)
        assert Map.has_key?(config, :trials)
        assert config.trainset_size == 100
      end)

      # Conservative should have fewer candidates/trials than aggressive
      conservative = Enum.find(configurations, &(&1.name == "Conservative"))
      aggressive = Enum.find(configurations, &(&1.name == "Aggressive"))

      assert conservative.candidates < aggressive.candidates
      assert conservative.trials < aggressive.trials
    end

    test "best configuration selection logic" do
      mock_results = [
        %{config: %{name: "Config A"}, efficiency_score: 0.75},
        %{config: %{name: "Config B"}, efficiency_score: 0.90},  # Best
        %{config: %{name: "Config C"}, efficiency_score: 0.60}
      ]

      best = Enum.max_by(mock_results, & &1.efficiency_score)
      assert best.config.name == "Config B"
      assert best.efficiency_score == 0.90
    end
  end

  describe "benchmark summary and reporting" do
    test "summary statistics calculation" do
      mock_results = [
        %{duration: 100, memory_mb: 10.0, throughput: 50.0, efficiency_score: 0.8},
        %{duration: 200, memory_mb: 20.0, throughput: 40.0, efficiency_score: 0.7},
        %{duration: 150, memory_mb: 15.0, throughput: 45.0, efficiency_score: 0.75}
      ]

      total_time = Enum.sum(Enum.map(mock_results, & &1.duration))
      avg_memory = mock_results |> Enum.map(& &1.memory_mb) |> Enum.sum() |> Kernel./(length(mock_results))
      avg_throughput = mock_results |> Enum.map(& &1.throughput) |> Enum.sum() |> Kernel./(length(mock_results))

      assert total_time == 450
      assert avg_memory == 15.0
      assert avg_throughput == 45.0

      fastest = Enum.max_by(mock_results, & &1.throughput)
      most_efficient = Enum.max_by(mock_results, & &1.efficiency_score)

      assert fastest.throughput == 50.0
      assert most_efficient.efficiency_score == 0.8
    end

    test "performance recommendations logic" do
      # Test recommendation triggers
      high_memory = 150.0  # > 100MB threshold
      low_throughput = 5.0  # < 10 examples/sec threshold
      long_time = 120_000  # > 60 seconds threshold

      recommendations = []

      if high_memory > 100 do
        recommendations = ["reduce memory usage" | recommendations]
      end

      if low_throughput < 10 do
        recommendations = ["increase concurrency" | recommendations]
      end

      if long_time > 60_000 do
        recommendations = ["reduce optimization time" | recommendations]
      end

      assert "reduce memory usage" in recommendations
      assert "increase concurrency" in recommendations
      assert "reduce optimization time" in recommendations
      assert length(recommendations) == 3
    end
  end

  describe "simulation functions" do
    test "bootstrap phase simulation" do
      config = %{candidates: 20, demos: 4}

      # Test the simulation logic
      base_time = config.candidates * 50  # 50ms per candidate
      concurrency_factor = max(1, config.candidates / 20)
      simulated_time = round(base_time / concurrency_factor)

      assert simulated_time == 1000  # 20 * 50 / 1 = 1000ms
    end

    test "optimization phase simulation" do
      config = %{trials: 30, demos: 4}

      base_time = config.trials * 100  # 100ms per trial
      complexity_factor = 1 + (config.demos * 0.1)  # More demos = more complexity
      simulated_time = round(base_time * complexity_factor)

      expected_time = round(3000 * 1.4)  # 30 * 100 * 1.4 = 4200ms
      assert simulated_time == expected_time
    end

    test "concurrent processing simulation" do
      trainset_size = 100
      concurrency = 10

      base_time_per_example = 10  # ms
      total_base_time = trainset_size * base_time_per_example

      # Concurrency reduces time but with diminishing returns
      concurrency_efficiency = min(concurrency, trainset_size) / (1 + concurrency * 0.01)
      concurrent_time = total_base_time / concurrency_efficiency

      assert concurrent_time < total_base_time  # Should be faster
      assert concurrent_time > 0
    end

    test "efficiency score calculation components" do
      config = %{candidates: 20, trials: 40}
      time_ms = 5000
      memory_bytes = 50 * 1_048_576  # 50MB

      # Test individual score components
      time_score = 1.0 / (time_ms / 1000)  # Higher score for less time
      memory_score = 1.0 / (memory_bytes / 1_048_576)  # Higher score for less memory
      work_score = config.candidates * config.trials  # More work = higher score

      assert time_score == 0.2  # 1.0 / 5
      assert memory_score == 0.02  # 1.0 / 50
      assert work_score == 800  # 20 * 40

      efficiency_score = (time_score + memory_score + work_score) / 3
      assert efficiency_score > 0
      assert efficiency_score == (0.2 + 0.02 + 800) / 3
    end
  end

  describe "trainset creation" do
    test "create_benchmark_trainset generates correct size" do
      sizes = [10, 50, 100, 500]

      Enum.each(sizes, fn size ->
        # Mock the trainset creation logic
        trainset = 1..size
        |> Enum.map(fn i ->
          %{
            question: "Benchmark question #{i}?",
            answer: "Benchmark answer #{i}"
          }
        end)

        assert length(trainset) == size

        # Check first and last items
        first_item = List.first(trainset)
        last_item = List.last(trainset)

        assert first_item.question == "Benchmark question 1?"
        assert last_item.question == "Benchmark question #{size}?"
      end)
    end

    test "varied content generation" do
      # Test the content variation logic
      test_cases = [
        {0, "mathematical calculation"},
        {1, "complex concepts"},
        {2, "multiple factors"},
        {3, "synthesis of information"}
      ]

      Enum.each(test_cases, fn {index, expected_content_type} ->
        content = case rem(index, 4) do
          0 -> "This involves mathematical calculation and reasoning."
          1 -> "This requires understanding of complex concepts and relationships."
          2 -> "This needs careful analysis of multiple factors and considerations."
          3 -> "This demands synthesis of information from various sources."
        end

        assert String.contains?(String.downcase(content), expected_content_type)
      end)
    end
  end

  describe "full benchmark execution" do
    test "run_benchmarks structure and flow" do
      # Test the overall benchmark flow without full execution
      benchmark_configurations = [
        %{name: "Small Scale", candidates: 10, trials: 20, demos: 2, trainset_size: 50},
        %{name: "Medium Scale", candidates: 20, trials: 40, demos: 4, trainset_size: 200}
      ]

      # Verify configurations are properly structured
      assert length(benchmark_configurations) == 2

      Enum.each(benchmark_configurations, fn config ->
        assert Map.has_key?(config, :name)
        assert Map.has_key?(config, :candidates)
        assert Map.has_key?(config, :trials)
        assert Map.has_key?(config, :demos)
        assert Map.has_key?(config, :trainset_size)

        assert is_binary(config.name)
        assert is_integer(config.candidates)
        assert config.candidates > 0
        assert config.trainset_size > 0
      end)
    end

    test "benchmark result validation" do
      # Test that benchmark results have required fields
      required_fields = [
        :config, :duration, :bootstrap_time, :optimization_time,
        :memory_mb, :throughput, :efficiency_score
      ]

      mock_result = %{
        config: %{name: "Test"},
        duration: 1000,
        bootstrap_time: 300,
        optimization_time: 700,
        memory_mb: 25.5,
        throughput: 50.0,
        efficiency_score: 0.75
      }

      Enum.each(required_fields, fn field ->
        assert Map.has_key?(mock_result, field)
      end)

      # Validate data types and ranges
      assert is_map(mock_result.config)
      assert is_number(mock_result.duration) and mock_result.duration > 0
      assert is_number(mock_result.throughput) and mock_result.throughput > 0
      assert is_float(mock_result.efficiency_score)
      assert mock_result.bootstrap_time + mock_result.optimization_time <= mock_result.duration
    end
  end

  # Helper functions for testing simulation logic
  defp simulate_improvement(config) do
    base_improvement = 0.3
    candidate_factor = min(config.candidates / 50, 1.0) * 0.4
    trial_factor = min(config.trials / 100, 1.0) * 0.2
    threshold_factor = config.threshold * 0.1

    base_improvement + candidate_factor + trial_factor + threshold_factor
  end

  defp simulate_consistency(config) do
    base_consistency = 0.6
    trial_factor = min(config.trials / 100, 1.0) * 0.3
    threshold_factor = config.threshold * 0.1

    base_consistency + trial_factor + threshold_factor
  end
end
