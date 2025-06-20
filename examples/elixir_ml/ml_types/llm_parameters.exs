#!/usr/bin/env elixir

# Example: LLM Parameter Validation
#
# This example demonstrates:
# - ML-specific type validation
# - Provider-specific optimizations
# - Advanced constraint handling
# - Real-world LLM parameter scenarios
#
# Usage: elixir examples/elixir_ml/ml_types/llm_parameters.exs

# This example should be run from the ds_ex project root:
# cd /path/to/ds_ex && elixir examples/elixir_ml/ml_types/llm_parameters.exs

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

defmodule LLMParametersExample do
  @moduledoc """
  Comprehensive example of LLM parameter validation using ElixirML.

  This example demonstrates:
  - Provider-specific LLM parameter schemas
  - Advanced ML type constraints
  - Cost estimation and optimization
  - Real-world API parameter validation
  """

  def run do
    IO.puts("\n🧠 ElixirML LLM Parameters Example")
    IO.puts("==================================")

    # Step 1: OpenAI parameter validation
    openai_example()

    # Step 2: Anthropic parameter validation
    anthropic_example()

    # Step 3: Multi-provider validation
    multi_provider_example()

    # Step 4: Advanced ML constraints
    advanced_constraints_example()

    # Step 5: Cost optimization
    cost_optimization_example()

    IO.puts("\n✅ LLM parameter examples completed!")
  end

  defp openai_example do
    IO.puts("\n🤖 Step 1: OpenAI Parameter Validation")
    IO.puts("--------------------------------------")

    # OpenAI GPT-4 parameter schema
    openai_schema = ElixirML.Runtime.create_schema([
      {:model, :string, [choices: ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo", "gpt-3.5-turbo-16k"]]},
      {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
      {:max_tokens, :integer, [gteq: 1, lteq: 4096]},
      {:top_p, :float, [gteq: 0.0, lteq: 1.0]},
      {:frequency_penalty, :float, [gteq: -2.0, lteq: 2.0]},
      {:presence_penalty, :float, [gteq: -2.0, lteq: 2.0]},
      {:stream, :boolean, []},
      {:n, :integer, [gteq: 1, lteq: 10]},
      {:stop, :string, [optional: true]}
    ], [provider: :openai])

    IO.puts("Created OpenAI parameter schema")

    # Valid OpenAI configurations
    openai_configs = [
      %{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000,
        top_p: 0.9,
        frequency_penalty: 0.0,
        presence_penalty: 0.0,
        stream: false,
        n: 1
      },
      %{
        model: "gpt-3.5-turbo",
        temperature: 1.2,
        max_tokens: 2048,
        top_p: 0.95,
        frequency_penalty: 0.5,
        presence_penalty: -0.5,
        stream: true,
        n: 3,
        stop: "\n"
      }
    ]

    Enum.with_index(openai_configs, 1) |> Enum.each(fn {config, index} ->
      case ElixirML.Runtime.validate(openai_schema, config) do
        {:ok, validated} ->
          IO.puts("✅ OpenAI Config #{index} validated successfully")
          IO.puts("   Model: #{validated.model}, Temp: #{validated.temperature}")

        {:error, errors} ->
          IO.puts("❌ OpenAI Config #{index} validation failed:")
          IO.inspect(errors)
      end
    end)

    # Export OpenAI-optimized JSON schema
    json_schema = ElixirML.Runtime.to_json_schema(openai_schema, [provider: :openai])
    IO.puts("\n📄 OpenAI JSON Schema structure:")
    IO.puts("   Fields: #{length(Map.keys(json_schema["properties"]))}")
    IO.puts("   Required: #{inspect(json_schema["required"])}")
    IO.puts("   OpenAI optimized: #{json_schema["x-openai-optimized"]}")
  end

  defp anthropic_example do
    IO.puts("\n🏛️  Step 2: Anthropic Parameter Validation")
    IO.puts("-----------------------------------------")

    # Anthropic Claude parameter schema
    anthropic_schema = ElixirML.Runtime.create_schema([
      {:model, :string, [choices: ["claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307"]]},
      {:max_tokens, :integer, [gteq: 1, lteq: 100_000]},
      {:temperature, :float, [gteq: 0.0, lteq: 1.0]},
      {:top_p, :float, [gteq: 0.0, lteq: 1.0]},
      {:top_k, :integer, [gteq: 1, lteq: 200]},
      {:stream, :boolean, []}
    ], [provider: :anthropic])

    IO.puts("Created Anthropic parameter schema")

    # Valid Anthropic configuration
    anthropic_config = %{
      model: "claude-3-opus-20240229",
      max_tokens: 4000,
      temperature: 0.3,
      top_p: 0.9,
      top_k: 50,
      stream: false
    }

    case ElixirML.Runtime.validate(anthropic_schema, anthropic_config) do
      {:ok, validated} ->
        IO.puts("✅ Anthropic configuration validated:")
        IO.puts("   Model: #{validated.model}")
        IO.puts("   Max tokens: #{validated.max_tokens}")
        IO.puts("   Temperature: #{validated.temperature}")

      {:error, errors} ->
        IO.puts("❌ Anthropic validation failed:")
        IO.inspect(errors)
    end

    # Test invalid Anthropic config (temperature too high)
    invalid_config = Map.put(anthropic_config, :temperature, 1.5)

    case ElixirML.Runtime.validate(anthropic_schema, invalid_config) do
      {:ok, _} ->
        IO.puts("⚠️  Expected validation error for high temperature")

      {:error, error} ->
        IO.puts("✅ Caught expected error for temperature > 1.0:")
        IO.puts("   #{format_error(error)}")
    end
  end

  defp multi_provider_example do
    IO.puts("\n🔄 Step 3: Multi-Provider Validation")
    IO.puts("------------------------------------")

    # Universal LLM parameter schema
    universal_schema = ElixirML.Runtime.create_schema([
      {:provider, :string, [choices: ["openai", "anthropic", "groq"]]},
      {:model, :string, [min_length: 1]},
      {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
      {:max_tokens, :integer, [gteq: 1, lteq: 100_000]},
      {:stream, :boolean, []}
    ])

    IO.puts("Created universal multi-provider schema")

    # Test configurations for different providers
    provider_configs = [
      %{provider: "openai", model: "gpt-4", temperature: 0.7, max_tokens: 1000, stream: false},
      %{provider: "anthropic", model: "claude-3-opus", temperature: 0.3, max_tokens: 4000, stream: true},
      %{provider: "groq", model: "mixtral-8x7b", temperature: 1.0, max_tokens: 2048, stream: false}
    ]

    Enum.each(provider_configs, fn config ->
      case ElixirML.Runtime.validate(universal_schema, config) do
        {:ok, validated} ->
          IO.puts("✅ #{String.upcase(validated.provider)} config validated:")
          IO.puts("   #{validated.model} (temp: #{validated.temperature})")

        {:error, errors} ->
          IO.puts("❌ #{config.provider} validation failed:")
          IO.inspect(errors)
      end
    end)
  end

  defp advanced_constraints_example do
    IO.puts("\n🔬 Step 4: Advanced ML Constraints")
    IO.puts("----------------------------------")

    # Advanced ML parameter schema with complex constraints
    advanced_schema = ElixirML.Runtime.create_schema([
      # Core parameters
      {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
      {:top_p, :float, [gteq: 0.0, lteq: 1.0]},
      {:max_tokens, :integer, [gteq: 1, lteq: 8192]},

      # Quality metrics
      {:confidence_threshold, :float, [gteq: 0.0, lteq: 1.0]},
      {:quality_score_min, :float, [gteq: 0.0, lteq: 10.0]},

      # Performance constraints
      {:max_latency_ms, :integer, [gteq: 100, lteq: 30_000]},
      {:max_cost_per_token, :float, [gteq: 0.000001, lteq: 0.01]},

      # Optimization flags
      {:optimize_for, :string, [choices: ["speed", "quality", "cost"]]},
      {:enable_caching, :boolean, []}
    ])

    IO.puts("Created advanced ML constraints schema")

    # Test advanced configuration
    advanced_config = %{
      temperature: 0.7,
      top_p: 0.9,
      max_tokens: 2000,
      confidence_threshold: 0.8,
      quality_score_min: 7.0,
      max_latency_ms: 5000,
      max_cost_per_token: 0.002,
      optimize_for: "quality",
      enable_caching: true
    }

    case ElixirML.Runtime.validate(advanced_schema, advanced_config) do
      {:ok, validated} ->
        IO.puts("✅ Advanced configuration validated:")
        IO.puts("   Optimization: #{validated.optimize_for}")
        IO.puts("   Quality threshold: #{validated.quality_score_min}/10")
        IO.puts("   Max latency: #{validated.max_latency_ms}ms")

      {:error, errors} ->
        IO.puts("❌ Advanced validation failed:")
        IO.inspect(errors)
    end

    # Test constraint violations
    constraint_violations = [
      {Map.put(advanced_config, :confidence_threshold, 1.5), "confidence > 1.0"},
      {Map.put(advanced_config, :max_cost_per_token, 0.1), "cost too high"},
      {Map.put(advanced_config, :optimize_for, "invalid"), "invalid optimization target"}
    ]

    Enum.each(constraint_violations, fn {config, description} ->
      case ElixirML.Runtime.validate(advanced_schema, config) do
        {:ok, _} ->
          IO.puts("⚠️  Expected error for: #{description}")

        {:error, error} ->
          IO.puts("✅ Caught constraint violation (#{description}):")
          IO.puts("   #{format_error(error)}")
      end
    end)
  end

  defp cost_optimization_example do
    IO.puts("\n💰 Step 5: Cost Optimization")
    IO.puts("----------------------------")

    # Cost-aware LLM parameter schema
    cost_schema = ElixirML.Runtime.create_schema([
      {:model, :string, choices: ["gpt-4", "gpt-3.5-turbo", "claude-3-opus", "claude-3-sonnet"]},
      {:max_tokens, :integer, gteq: 1, lteq: 8192},
      {:temperature, :float, gteq: 0.0, lteq: 2.0},
      {:budget_limit_usd, :float, gteq: 0.01, lteq: 100.0},
      {:cost_per_1k_tokens, :float, gteq: 0.0001, lteq: 0.1}
    ])

    IO.puts("Created cost-aware parameter schema")

    # Model pricing (approximate)
    model_costs = %{
      "gpt-4" => 0.03,
      "gpt-3.5-turbo" => 0.002,
      "claude-3-opus" => 0.015,
      "claude-3-sonnet" => 0.003
    }

    # Test different cost scenarios
    cost_scenarios = [
      %{
        model: "gpt-3.5-turbo",
        max_tokens: 1000,
        temperature: 0.7,
        budget_limit_usd: 5.0,
        cost_per_1k_tokens: model_costs["gpt-3.5-turbo"]
      },
      %{
        model: "gpt-4",
        max_tokens: 2000,
        temperature: 0.5,
        budget_limit_usd: 10.0,
        cost_per_1k_tokens: model_costs["gpt-4"]
      },
      %{
        model: "claude-3-opus",
        max_tokens: 4000,
        temperature: 0.3,
        budget_limit_usd: 20.0,
        cost_per_1k_tokens: model_costs["claude-3-opus"]
      }
    ]

    Enum.with_index(cost_scenarios, 1) |> Enum.each(fn {scenario, index} ->
      case ElixirML.Runtime.validate(cost_schema, scenario) do
        {:ok, validated} ->
          estimated_cost = calculate_estimated_cost(validated)
          within_budget = estimated_cost <= validated.budget_limit_usd

          IO.puts("✅ Cost Scenario #{index} (#{validated.model}):")
          IO.puts("   Max tokens: #{validated.max_tokens}")
          IO.puts("   Estimated cost: $#{Float.round(estimated_cost, 4)}")
          IO.puts("   Budget limit: $#{validated.budget_limit_usd}")
          IO.puts("   Within budget: #{if within_budget, do: "✅", else: "❌"}")

        {:error, errors} ->
          IO.puts("❌ Cost Scenario #{index} validation failed:")
          IO.inspect(errors)
      end
    end)

    # Cost optimization recommendations
    IO.puts("\n💡 Cost Optimization Tips:")
    IO.puts("   1. Use gpt-3.5-turbo for simple tasks (10-15x cheaper than GPT-4)")
    IO.puts("   2. Set appropriate max_tokens to avoid unnecessary costs")
    IO.puts("   3. Use temperature < 0.7 for more deterministic (efficient) outputs")
    IO.puts("   4. Consider Claude-3-Sonnet as a middle-ground option")
  end

  defp calculate_estimated_cost(config) do
    # Simple cost estimation: (tokens / 1000) * cost_per_1k_tokens
    (config.max_tokens / 1000.0) * config.cost_per_1k_tokens
  end

  defp format_error(error) do
    case error do
      %ElixirML.Schema.ValidationError{} = err ->
        "#{err.field}: #{err.message}"

      errors when is_list(errors) ->
        errors
        |> Enum.map(&format_error/1)
        |> Enum.join(", ")

      other ->
        inspect(other)
    end
  end
end

# Run the example
LLMParametersExample.run()
