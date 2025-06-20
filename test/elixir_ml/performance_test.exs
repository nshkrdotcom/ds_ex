defmodule ElixirML.PerformanceTest do
  use ExUnit.Case

  alias ElixirML.{Runtime, Performance}
  alias ElixirML.Variable.MLTypes

  describe "schema validation benchmarking" do
    test "benchmark_validation/3 measures validation performance" do
      # Create a simple schema for benchmarking
      schema =
        Runtime.create_schema([
          {:temperature, :float, gteq: 0.0, lteq: 2.0},
          {:max_tokens, :integer, gteq: 1, lteq: 4096}
        ])

      dataset = [
        %{temperature: 0.7, max_tokens: 1000},
        %{temperature: 1.2, max_tokens: 2000},
        %{temperature: 0.3, max_tokens: 500}
      ]

      stats = Performance.benchmark_validation(schema, dataset, iterations: 10, warmup: 5)

      assert is_number(stats.avg_time_microseconds)
      assert is_number(stats.total_time_microseconds)
      # 10 iterations * 3 items
      assert stats.total_validations == 30
      assert stats.validations_per_second > 0
    end

    test "benchmark_validation/3 handles empty datasets" do
      schema = Runtime.create_schema([{:id, :integer, gteq: 1}])

      stats = Performance.benchmark_validation(schema, [], iterations: 5)

      assert stats.total_validations == 0
      assert stats.avg_time_microseconds == 0
      assert stats.validations_per_second == 0
    end

    test "benchmark_validation/3 with ML-specific types" do
      # Use ML-specific types for benchmarking
      schema =
        Runtime.create_schema([
          {:confidence, :float, gteq: 0.0, lteq: 1.0},
          {:token_count, :integer, gteq: 1, lteq: 8192},
          {:cost_estimate, :float, gteq: 0.0, lteq: 1000.0}
        ])

      dataset = [
        %{confidence: 0.95, token_count: 1500, cost_estimate: 0.05},
        %{confidence: 0.87, token_count: 2000, cost_estimate: 0.08}
      ]

      stats = Performance.benchmark_validation(schema, dataset, iterations: 5)

      assert stats.total_validations == 10
      assert is_number(stats.avg_time_microseconds)
    end
  end

  describe "memory usage analysis" do
    test "analyze_memory_usage/2 measures memory consumption" do
      schema =
        Runtime.create_schema([
          {:embedding, :float, gteq: -1.0, lteq: 1.0},
          {:quality_score, :float, gteq: 0.0, lteq: 10.0}
        ])

      dataset = [
        %{embedding: 0.5, quality_score: 8.5},
        %{embedding: -0.3, quality_score: 7.2}
      ]

      memory_stats = Performance.analyze_memory_usage(schema, dataset)

      assert is_number(memory_stats.initial_memory_bytes)
      assert is_number(memory_stats.final_memory_bytes)
      assert is_number(memory_stats.memory_used_bytes)
      assert memory_stats.successful_validations >= 0
      assert memory_stats.total_validations == 2
    end

    test "analyze_memory_usage/2 handles validation failures" do
      schema =
        Runtime.create_schema([
          {:probability, :float, gteq: 0.0, lteq: 1.0}
        ])

      # Mix valid and invalid data
      dataset = [
        # valid
        %{probability: 0.8},
        # invalid (> 1.0)
        %{probability: 1.5}
      ]

      memory_stats = Performance.analyze_memory_usage(schema, dataset)

      assert memory_stats.total_validations == 2
      assert memory_stats.successful_validations <= 2
      assert is_number(memory_stats.memory_per_validation_bytes)
    end
  end

  describe "schema complexity profiling" do
    test "profile_schema_complexity/1 analyzes simple schemas" do
      schema =
        Runtime.create_schema([
          {:temperature, :float, gteq: 0.0, lteq: 2.0},
          {:enabled, :integer, gteq: 0, lteq: 1}
        ])

      profile = Performance.profile_schema_complexity(schema)

      assert profile.field_count == 2
      assert is_number(profile.total_complexity_score)
      assert is_number(profile.average_field_complexity)
      assert is_map(profile.complexity_by_field)
      assert is_list(profile.optimization_recommendations)
    end

    test "profile_schema_complexity/1 identifies complex schemas" do
      # Create a complex schema with many constraints
      schema =
        Runtime.create_schema([
          {:embedding_vector, :float, gteq: -1.0, lteq: 1.0},
          {:confidence_matrix, :float, gteq: 0.0, lteq: 1.0},
          {:token_counts, :integer, gteq: 1, lteq: 100_000},
          {:quality_metrics, :float, gteq: 0.0, lteq: 10.0},
          {:cost_breakdown, :float, gteq: 0.0, lteq: 1000.0},
          {:latency_stats, :float, gteq: 0.001, lteq: 60.0}
        ])

      profile = Performance.profile_schema_complexity(schema)

      assert profile.field_count == 6
      assert profile.total_complexity_score > 0
      assert Map.has_key?(profile.complexity_by_field, :embedding_vector)
      assert is_list(profile.optimization_recommendations)
    end

    test "profile_schema_complexity/1 provides optimization recommendations" do
      schema =
        Runtime.create_schema([
          {:simple_field, :integer, gteq: 1, lteq: 10}
        ])

      profile = Performance.profile_schema_complexity(schema)

      # Simple schemas should get positive feedback
      assert Enum.any?(profile.optimization_recommendations, fn rec ->
               String.contains?(rec, "well-optimized") or String.contains?(rec, "optimized")
             end)
    end
  end

  describe "ML-specific performance patterns" do
    test "benchmarks teleprompter optimization space" do
      space = MLTypes.teleprompter_optimization_space()

      # Generate some sample configurations
      sample_configs = [
        %{temperature: 0.7, batch_size: 32, min_confidence: 0.8},
        %{temperature: 1.0, batch_size: 64, min_confidence: 0.9}
      ]

      # Benchmark variable space validation
      stats =
        Performance.benchmark_variable_space_validation(space, sample_configs, iterations: 5)

      assert is_number(stats.avg_time_microseconds)
      assert stats.total_validations == 10
    end

    test "analyzes provider-specific optimization performance" do
      openai_space = MLTypes.provider_optimized_space(:openai)
      anthropic_space = MLTypes.provider_optimized_space(:anthropic)

      sample_config = %{temperature: 0.8, output_quality: 7.5, response_time: 2.0}

      openai_stats =
        Performance.benchmark_variable_space_validation(openai_space, [sample_config],
          iterations: 3
        )

      anthropic_stats =
        Performance.benchmark_variable_space_validation(anthropic_space, [sample_config],
          iterations: 3
        )

      # Both should complete successfully
      assert openai_stats.total_validations == 3
      assert anthropic_stats.total_validations == 3

      # Performance comparison
      assert is_number(openai_stats.avg_time_microseconds)
      assert is_number(anthropic_stats.avg_time_microseconds)
    end

    test "profiles ML type complexity" do
      # Test various ML types for complexity
      embedding_var = MLTypes.embedding(:test_embedding, dimensions: 1536)
      token_var = MLTypes.token_count(:test_tokens, max: 4096)
      cost_var = MLTypes.cost_estimate(:test_cost, currency: :usd)

      embedding_complexity = Performance.calculate_variable_complexity(embedding_var)
      token_complexity = Performance.calculate_variable_complexity(token_var)
      cost_complexity = Performance.calculate_variable_complexity(cost_var)

      # Embedding should be more complex due to composite nature
      assert embedding_complexity >= token_complexity
      assert embedding_complexity >= cost_complexity

      # All should be positive numbers
      assert embedding_complexity > 0
      assert token_complexity > 0
      assert cost_complexity > 0
    end
  end

  describe "performance optimization recommendations" do
    test "recommends optimizations for high-dimensional spaces" do
      # Create a high-dimensional optimization space
      variables = [
        MLTypes.temperature(:temp1),
        MLTypes.temperature(:temp2),
        MLTypes.temperature(:temp3),
        MLTypes.probability(:prob1),
        MLTypes.probability(:prob2),
        MLTypes.token_count(:tokens1, max: 1000),
        MLTypes.token_count(:tokens2, max: 2000),
        MLTypes.cost_estimate(:cost1),
        MLTypes.cost_estimate(:cost2),
        MLTypes.quality_score(:quality1)
      ]

      space =
        ElixirML.Variable.Space.new(name: "High-Dimensional Space")
        |> ElixirML.Variable.Space.add_variables(variables)

      recommendations = Performance.analyze_optimization_space(space)

      assert is_list(recommendations.performance_tips)
      assert is_number(recommendations.dimensionality_score)
      assert is_map(recommendations.complexity_breakdown)
    end

    test "identifies bottlenecks in variable spaces" do
      space = MLTypes.multi_objective_space()

      bottlenecks = Performance.identify_performance_bottlenecks(space)

      assert is_list(bottlenecks.potential_bottlenecks)
      assert is_map(bottlenecks.performance_metrics)
      assert is_list(bottlenecks.optimization_suggestions)
    end
  end
end
