#!/usr/bin/env elixir

# Example: Performance Benchmarking
#
# This example demonstrates:
# - Validation performance benchmarking
# - Memory usage analysis
# - Schema complexity profiling
# - Performance optimization strategies
#
# Usage: elixir examples/elixir_ml/performance/benchmarking.exs

# This example should be run from the ds_ex project root:
# cd /path/to/ds_ex && elixir examples/elixir_ml/performance/benchmarking.exs

# Add the lib directory to the code path
Code.prepend_path("lib")

# Load the necessary modules in dependency order
Code.require_file("lib/elixir_ml/schema/validation_error.ex")
Code.require_file("lib/elixir_ml/schema/types.ex")
Code.require_file("lib/elixir_ml/schema/definition.ex")
Code.require_file("lib/elixir_ml/schema/behaviour.ex")
Code.require_file("lib/elixir_ml/schema/dsl.ex")
Code.require_file("lib/elixir_ml/schema/compiler.ex")
Code.require_file("lib/elixir_ml/schema/runtime.ex")
Code.require_file("lib/elixir_ml/schema.ex")
Code.require_file("lib/elixir_ml/variable.ex")
Code.require_file("lib/elixir_ml/variable/space.ex")
Code.require_file("lib/elixir_ml/variable/ml_types.ex")
Code.require_file("lib/elixir_ml/runtime.ex")
Code.require_file("lib/elixir_ml/performance.ex")

defmodule PerformanceBenchmarkingExample do
  @moduledoc """
  Comprehensive performance benchmarking example for ElixirML.

  This example demonstrates:
  - Validation speed benchmarking across different schema types
  - Memory usage analysis and optimization
  - Schema complexity impact on performance
  - Real-world performance scenarios
  """

  def run do
    IO.puts("\n⚡ ElixirML Performance Benchmarking")
    IO.puts("===================================")

    # Step 1: Basic validation benchmarking
    basic_benchmarking()

    # Step 2: ML-specific type benchmarking
    ml_type_benchmarking()

    # Step 3: Memory usage analysis
    memory_analysis()

    # Step 4: Schema complexity profiling
    complexity_profiling()

    # Step 5: Variable space performance
    variable_space_performance()

    # Step 6: Optimization recommendations
    optimization_recommendations()

    IO.puts("\n✅ Performance benchmarking completed!")
  end

  defp basic_benchmarking do
    IO.puts("\n📊 Step 1: Basic Validation Benchmarking")
    IO.puts("----------------------------------------")

    # Create schemas of different complexities
    schemas = %{
      simple: ElixirML.Runtime.create_schema([
        {:name, :string, [min_length: 1]},
        {:age, :integer, [gteq: 0, lteq: 150]}
      ]),

      moderate: ElixirML.Runtime.create_schema([
        {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
        {:max_tokens, :integer, [gteq: 1, lteq: 4096]},
        {:top_p, :float, [gteq: 0.0, lteq: 1.0]},
        {:model, :string, [choices: ["gpt-4", "gpt-3.5-turbo"]]},
        {:stream, :boolean, []}
      ]),

      complex: ElixirML.Runtime.create_schema([
        {:model_config, :string, [choices: Enum.map(1..20, &"model_#{&1}")]},
        {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
        {:max_tokens, :integer, [gteq: 1, lteq: 100_000]},
        {:top_p, :float, [gteq: 0.0, lteq: 1.0]},
        {:frequency_penalty, :float, [gteq: -2.0, lteq: 2.0]},
        {:presence_penalty, :float, [gteq: -2.0, lteq: 2.0]},
        {:confidence_threshold, :float, [gteq: 0.0, lteq: 1.0]},
        {:quality_score, :float, [gteq: 0.0, lteq: 10.0]},
        {:cost_limit, :float, [gteq: 0.01, lteq: 100.0]},
        {:enable_caching, :boolean, []},
        {:retry_count, :integer, [gteq: 0, lteq: 10]},
        {:timeout_ms, :integer, [gteq: 1000, lteq: 60_000]}
      ])
    }

    # Generate test datasets
    datasets = %{
      simple: generate_simple_data(1000),
      moderate: generate_moderate_data(1000),
      complex: generate_complex_data(1000)
    }

    # Benchmark each schema type
    Enum.each([:simple, :moderate, :complex], fn schema_type ->
      schema = schemas[schema_type]
      dataset = datasets[schema_type]

      IO.puts("\n🔍 Benchmarking #{schema_type} schema:")

      # Benchmark with ElixirML.Performance
      stats = ElixirML.Performance.benchmark_validation(schema, dataset,
        iterations: 10,
        warmup: 2
      )

      IO.puts("   Validations/second: #{round_number(stats.validations_per_second)}")
      IO.puts("   Avg time per validation: #{round_number(stats.avg_time_microseconds, 2)} μs")
      IO.puts("   Total validations: #{stats.total_validations}")

      # Performance assessment
      performance_level = case stats.validations_per_second do
        n when n > 50_000 -> "🚀 Excellent"
        n when n > 20_000 -> "✅ Good"
        n when n > 5_000 -> "⚠️  Acceptable"
        _ -> "❌ Needs optimization"
      end

      IO.puts("   Performance: #{performance_level}")
    end)
  end

  defp ml_type_benchmarking do
    IO.puts("\n🧠 Step 2: ML-Specific Type Benchmarking")
    IO.puts("----------------------------------------")

    # Create ML-specific schemas
    ml_schemas = %{
      llm_params: ElixirML.Runtime.create_schema([
        {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
        {:max_tokens, :integer, [gteq: 1, lteq: 8192]},
        {:top_p, :float, [gteq: 0.0, lteq: 1.0]}
      ]),

      embeddings: ElixirML.Runtime.create_schema([
        {:embedding_vector, :float, [gteq: -1.0, lteq: 1.0]},
        {:similarity_score, :float, [gteq: 0.0, lteq: 1.0]},
        {:dimensions, :integer, [gteq: 128, lteq: 2048]}
      ]),

      performance_metrics: ElixirML.Runtime.create_schema([
        {:latency_ms, :integer, [gteq: 1, lteq: 30_000]},
        {:throughput_rps, :float, [gteq: 0.1, lteq: 10_000.0]},
        {:accuracy_score, :float, [gteq: 0.0, lteq: 1.0]},
        {:f1_score, :float, [gteq: 0.0, lteq: 1.0]},
        {:precision, :float, [gteq: 0.0, lteq: 1.0]},
        {:recall, :float, [gteq: 0.0, lteq: 1.0]}
      ])
    }

    # Generate ML-specific test data
    ml_datasets = %{
      llm_params: generate_llm_data(500),
      embeddings: generate_embedding_data(500),
      performance_metrics: generate_metrics_data(500)
    }

    # Benchmark ML schemas
    Enum.each([:llm_params, :embeddings, :performance_metrics], fn schema_type ->
      schema = ml_schemas[schema_type]
      dataset = ml_datasets[schema_type]

      IO.puts("\n🔍 ML Schema: #{schema_type}")

      stats = ElixirML.Performance.benchmark_validation(schema, dataset, iterations: 5)

      IO.puts("   Validations/second: #{round_number(stats.validations_per_second)}")
      IO.puts("   Avg time: #{round_number(stats.avg_time_microseconds, 2)} μs")
      IO.puts("   Dataset size: #{length(dataset)} records")
    end)
  end

  defp memory_analysis do
    IO.puts("\n💾 Step 3: Memory Usage Analysis")
    IO.puts("--------------------------------")

    # Create memory-intensive schema
    memory_schema = ElixirML.Runtime.create_schema([
      {:large_text, :string, [min_length: 1, max_length: 10_000]},
      {:embedding_vector, :float, [gteq: -1.0, lteq: 1.0]},
      {:metadata, :string, [min_length: 1]},
      {:scores, :float, [gteq: 0.0, lteq: 1.0]}
    ])

    # Generate memory-intensive dataset
    memory_dataset = Enum.map(1..100, fn i ->
      %{
        large_text: String.duplicate("sample text #{i} ", 100),
        embedding_vector: :rand.uniform() * 2.0 - 1.0,
        metadata: "metadata_#{i}",
        scores: :rand.uniform()
      }
    end)

    IO.puts("Generated memory-intensive dataset (100 records)")

    # Analyze memory usage
    memory_stats = ElixirML.Performance.analyze_memory_usage(memory_schema, memory_dataset)

    IO.puts("📊 Memory Analysis Results:")
    IO.puts("   Initial memory: #{format_bytes(memory_stats.initial_memory_bytes)}")
    IO.puts("   Final memory: #{format_bytes(memory_stats.final_memory_bytes)}")
    IO.puts("   Memory used: #{format_bytes(memory_stats.memory_used_bytes)}")
    IO.puts("   Memory per validation: #{format_bytes(memory_stats.memory_per_validation_bytes)}")

    # Memory efficiency assessment
    efficiency = case memory_stats.memory_per_validation_bytes do
      n when n < 1024 -> "🚀 Excellent"
      n when n < 5120 -> "✅ Good"
      n when n < 10240 -> "⚠️  Acceptable"
      _ -> "❌ High memory usage"
    end

    IO.puts("   Memory efficiency: #{efficiency}")
  end

  defp complexity_profiling do
    IO.puts("\n🔬 Step 4: Schema Complexity Profiling")
    IO.puts("-------------------------------------")

    # Create schemas with different complexity levels
    complexity_schemas = [
      {ElixirML.Runtime.create_schema([
        {:simple_field, :string, [min_length: 1]}
      ]), "minimal"},

      {ElixirML.Runtime.create_schema([
        {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
        {:max_tokens, :integer, [gteq: 1, lteq: 4096]},
        {:model, :string, [choices: ["gpt-4", "gpt-3.5-turbo"]]}
      ]), "moderate"},

      {ElixirML.Runtime.create_schema([
        {:model, :string, [choices: Enum.map(1..50, &"model_#{&1}")]},
        {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
        {:max_tokens, :integer, [gteq: 1, lteq: 100_000]},
        {:top_p, :float, [gteq: 0.0, lteq: 1.0]},
        {:frequency_penalty, :float, [gteq: -2.0, lteq: 2.0]},
        {:presence_penalty, :float, [gteq: -2.0, lteq: 2.0]},
        {:confidence_threshold, :float, [gteq: 0.0, lteq: 1.0]},
        {:quality_metrics, :float, [gteq: 0.0, lteq: 10.0]},
        {:cost_constraints, :float, [gteq: 0.01, lteq: 1000.0]},
        {:optimization_flags, :string, [choices: ["speed", "quality", "cost", "balanced"]]},
        {:retry_policy, :string, [choices: ["none", "exponential", "linear", "custom"]]},
        {:timeout_config, :integer, [gteq: 100, lteq: 300_000]},
        {:caching_strategy, :string, [choices: ["none", "memory", "disk", "distributed"]]},
        {:monitoring_level, :string, [choices: ["off", "basic", "detailed", "debug"]]},
        {:circuit_breaker, :boolean, []}
      ]), "complex"}
    ]

    Enum.each(complexity_schemas, fn {schema, complexity_level} ->
      IO.puts("\n🔍 Complexity Level: #{complexity_level}")

      profile = ElixirML.Performance.profile_schema_complexity(schema)

      IO.puts("   Field count: #{profile.field_count}")
      IO.puts("   Complexity score: #{round_number(profile.total_complexity_score, 2)}")
      IO.puts("   Avg field complexity: #{round_number(profile.average_field_complexity, 2)}")

      if length(profile.optimization_recommendations) > 0 do
        IO.puts("   Recommendations:")
        Enum.each(profile.optimization_recommendations, fn rec ->
          IO.puts("     • #{rec}")
        end)
      end
    end)
  end

  defp variable_space_performance do
    IO.puts("\n🎛️  Step 5: Variable Space Performance")
    IO.puts("------------------------------------")

    # Create variable spaces using MLTypes
    spaces = [
      {ElixirML.Variable.MLTypes.llm_optimization_space(), "LLM Optimization"},
      {ElixirML.Variable.MLTypes.teleprompter_optimization_space(), "Teleprompter"},
      {ElixirML.Variable.MLTypes.multi_objective_space(), "Multi-Objective"}
    ]

    Enum.each(spaces, fn {space, space_name} ->
      IO.puts("\n🔍 Variable Space: #{space_name}")

      # Generate sample configurations
      sample_configs = generate_space_configurations(space, 50)

      # Benchmark variable space validation
      stats = ElixirML.Performance.benchmark_variable_space_validation(
        space,
        sample_configs,
        iterations: 3
      )

      IO.puts("   Validations/second: #{round_number(stats.validations_per_second)}")
      IO.puts("   Avg time: #{round_number(stats.avg_time_microseconds, 2)} μs")
      success_rate = Map.get(stats, :success_rate, 1.0)
      IO.puts("   Success rate: #{round_number(success_rate * 100, 1)}%")

      # Analyze optimization space
      analysis = ElixirML.Performance.analyze_optimization_space(space)
      total_vars = Map.get(analysis, :total_variables, Map.get(analysis, :variable_count, 0))
      complexity_score = Map.get(analysis, :total_complexity_score, Map.get(analysis, :dimensionality_score, 0))
      search_time = Map.get(analysis, :estimated_search_time_seconds, Map.get(analysis, :estimated_search_time, 0))

      IO.puts("   Total variables: #{total_vars}")
      IO.puts("   Complexity score: #{round_number(complexity_score, 2)}")
      IO.puts("   Search time estimate: #{round_number(search_time, 2)}s")
    end)
  end

  defp optimization_recommendations do
    IO.puts("\n💡 Step 6: Performance Optimization Recommendations")
    IO.puts("--------------------------------------------------")

    # Create a complex schema for optimization analysis
    complex_schema = ElixirML.Runtime.create_schema([
      {:model, :string, [choices: Enum.map(1..100, &"model_#{&1}")]},
      {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
      {:max_tokens, :integer, [gteq: 1, lteq: 100_000]},
      {:embeddings, :float, [gteq: -1.0, lteq: 1.0]},
      {:quality_scores, :float, [gteq: 0.0, lteq: 10.0]}
    ] ++ Enum.map(1..20, fn i ->
      {:"additional_field_#{i}", :string, [min_length: 1, max_length: 100]}
    end))

    profile = ElixirML.Performance.profile_schema_complexity(complex_schema)

    IO.puts("📊 Schema Analysis:")
    IO.puts("   Total fields: #{profile.field_count}")
    IO.puts("   Complexity score: #{round_number(profile.total_complexity_score, 2)}")

    IO.puts("\n🎯 Optimization Strategies:")

    # General optimization tips
    optimization_tips = [
      "Reduce field count where possible (current: #{profile.field_count})",
      "Limit choice options (#{profile.field_count} fields with choices detected)",
      "Use simpler data types when sufficient",
      "Consider schema composition for reusability",
      "Pre-compile schemas for repeated use",
      "Use batch validation for multiple records",
      "Implement caching for repeated validations",
      "Monitor memory usage in production"
    ]

    Enum.each(optimization_tips, fn tip ->
      IO.puts("   • #{tip}")
    end)

    # Performance targets
    IO.puts("\n🎯 Performance Targets:")
    IO.puts("   • Simple schemas: >50,000 validations/second")
    IO.puts("   • Moderate schemas: >20,000 validations/second")
    IO.puts("   • Complex schemas: >5,000 validations/second")
    IO.puts("   • Memory usage: <5KB per validation")
    IO.puts("   • Schema compilation: <10ms")

    IO.puts("\n⚡ Quick Wins:")
    IO.puts("   1. Use :integer instead of :float when precision isn't needed")
    IO.puts("   2. Limit :string choices to essential options only")
    IO.puts("   3. Set reasonable min/max constraints")
    IO.puts("   4. Avoid deeply nested schemas")
    IO.puts("   5. Use ElixirML.Performance.benchmark_validation() regularly")
  end

  # Helper functions for generating test data

  defp round_number(number, precision \\ 0) when is_number(number) do
    cond do
      is_float(number) -> Float.round(number, precision)
      is_integer(number) -> number
      true -> number
    end
  end

  defp generate_simple_data(count) do
    Enum.map(1..count, fn i ->
      %{
        name: "User #{i}",
        age: :rand.uniform(100) + 10
      }
    end)
  end

  defp generate_moderate_data(count) do
    models = ["gpt-4", "gpt-3.5-turbo"]

    Enum.map(1..count, fn _ ->
      %{
        temperature: :rand.uniform() * 2.0,
        max_tokens: :rand.uniform(4096),
        top_p: :rand.uniform(),
        model: Enum.random(models),
        stream: :rand.uniform() > 0.5
      }
    end)
  end

  defp generate_complex_data(count) do
    models = Enum.map(1..20, &"model_#{&1}")

    Enum.map(1..count, fn _ ->
      %{
        model_config: Enum.random(models),
        temperature: :rand.uniform() * 2.0,
        max_tokens: :rand.uniform(100_000),
        top_p: :rand.uniform(),
        frequency_penalty: (:rand.uniform() - 0.5) * 4.0,
        presence_penalty: (:rand.uniform() - 0.5) * 4.0,
        confidence_threshold: :rand.uniform(),
        quality_score: :rand.uniform() * 10.0,
        cost_limit: :rand.uniform() * 100.0,
        enable_caching: :rand.uniform() > 0.5,
        retry_count: :rand.uniform(10),
        timeout_ms: :rand.uniform(59_000) + 1000
      }
    end)
  end

  defp generate_llm_data(count) do
    Enum.map(1..count, fn _ ->
      %{
        temperature: :rand.uniform() * 2.0,
        max_tokens: :rand.uniform(8192),
        top_p: :rand.uniform()
      }
    end)
  end

  defp generate_embedding_data(count) do
    Enum.map(1..count, fn _ ->
      %{
        embedding_vector: :rand.uniform() * 2.0 - 1.0,
        similarity_score: :rand.uniform(),
        dimensions: Enum.random([128, 256, 512, 768, 1024, 1536, 2048])
      }
    end)
  end

  defp generate_metrics_data(count) do
    Enum.map(1..count, fn _ ->
      %{
        latency_ms: :rand.uniform(29_999) + 1,
        throughput_rps: :rand.uniform() * 10_000.0,
        accuracy_score: :rand.uniform(),
        f1_score: :rand.uniform(),
        precision: :rand.uniform(),
        recall: :rand.uniform()
      }
    end)
  end

  defp generate_space_configurations(_space, count) do
    # Generate random configurations for the variable space
    # This is a simplified version - in practice, you'd use the space's
    # random configuration generation
    Enum.map(1..count, fn _ ->
      %{
        temperature: :rand.uniform() * 2.0,
        max_tokens: :rand.uniform(4096),
        quality_score: :rand.uniform() * 10.0
      }
    end)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
end

# Run the example
PerformanceBenchmarkingExample.run()
