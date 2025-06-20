defmodule ElixirML.Variable.MLTypes do
  @moduledoc """
  ML-specific variable types with built-in compatibility and optimization logic.

  These are pre-built variable definitions for common ML optimization scenarios
  like provider selection, model configuration, and reasoning strategies.
  """

  alias ElixirML.Variable

  @doc """
  Create a provider variable with model compatibility and cost/performance weights.

  ## Examples

      iex> provider_var = ElixirML.Variable.MLTypes.provider(:llm_provider)
      iex> provider_var.type
      :choice
      iex> :openai in provider_var.constraints.choices
      true
  """
  def provider(name, opts \\ []) do
    providers = Keyword.get(opts, :providers, [:openai, :anthropic, :groq, :google])

    Variable.choice(name, providers,
      description: "LLM Provider selection",
      hints: [
        optimization_priority: :cost_performance,
        compatibility_aware: true
      ],
      metadata: %{
        cost_weights: %{
          openai: 1.0,
          anthropic: 1.2,
          groq: 0.3,
          google: 0.8
        },
        performance_weights: %{
          openai: 0.9,
          anthropic: 0.95,
          groq: 0.7,
          google: 0.85
        },
        latency_weights: %{
          openai: 0.8,
          anthropic: 0.7,
          groq: 0.95,
          google: 0.8
        }
      }
    )
  end

  @doc """
  Create a model variable with provider-specific model options.

  ## Examples

      iex> model_var = ElixirML.Variable.MLTypes.model(:model, provider: :openai)
      iex> "gpt-4" in model_var.constraints.choices
      true
  """
  def model(name, opts \\ []) do
    provider = Keyword.get(opts, :provider)

    models =
      case provider do
        :openai -> ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"]
        :anthropic -> ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"]
        :groq -> ["llama-3-70b", "mixtral-8x7b", "gemma-7b"]
        :google -> ["gemini-pro", "gemini-pro-vision"]
        _ -> Keyword.get(opts, :models, ["gpt-4"])
      end

    Variable.choice(name, models,
      description: "Model selection for #{provider || "provider"}",
      dependencies: if(provider, do: [], else: [:provider]),
      hints: [
        performance_impact: :high,
        cost_impact: :high
      ],
      metadata: %{
        capabilities: model_capabilities(models),
        context_windows: model_context_windows(models)
      }
    )
  end

  @doc """
  Create an adapter variable with capability awareness.

  ## Examples

      iex> adapter_var = ElixirML.Variable.MLTypes.adapter(:response_adapter)
      iex> adapter_var.type
      :module
  """
  def adapter(name, opts \\ []) do
    adapters =
      Keyword.get(opts, :adapters, [
        ElixirML.Adapter.JSON,
        ElixirML.Adapter.Markdown,
        ElixirML.Adapter.Chat,
        ElixirML.Adapter.Structured
      ])

    Variable.module(name,
      modules: adapters,
      behavior: ElixirML.Adapter,
      description: "Response format adapter",
      hints: [
        performance_impact: :medium,
        model_compatibility: true
      ],
      metadata: %{
        output_formats: %{
          ElixirML.Adapter.JSON => :json,
          ElixirML.Adapter.Markdown => :markdown,
          ElixirML.Adapter.Chat => :text,
          ElixirML.Adapter.Structured => :structured
        }
      }
    )
  end

  @doc """
  Create a reasoning strategy variable for automatic strategy selection.

  ## Examples

      iex> reasoning_var = ElixirML.Variable.MLTypes.reasoning_strategy(:reasoning)
      iex> reasoning_var.type
      :module
  """
  def reasoning_strategy(name, opts \\ []) do
    strategies =
      Keyword.get(opts, :strategies, [
        ElixirML.Reasoning.Predict,
        ElixirML.Reasoning.ChainOfThought,
        ElixirML.Reasoning.ProgramOfThought,
        ElixirML.Reasoning.ReAct,
        ElixirML.Reasoning.SelfConsistency
      ])

    Variable.module(name,
      modules: strategies,
      behavior: ElixirML.Reasoning.Strategy,
      description: "Reasoning strategy selection",
      hints: [
        performance_impact: :high,
        accuracy_impact: :high,
        cost_impact: :high
      ],
      metadata: %{
        complexity_levels: %{
          ElixirML.Reasoning.Predict => 1,
          ElixirML.Reasoning.ChainOfThought => 3,
          ElixirML.Reasoning.ProgramOfThought => 4,
          ElixirML.Reasoning.ReAct => 5,
          ElixirML.Reasoning.SelfConsistency => 6
        },
        token_multipliers: %{
          ElixirML.Reasoning.Predict => 1.0,
          ElixirML.Reasoning.ChainOfThought => 2.5,
          ElixirML.Reasoning.ProgramOfThought => 3.0,
          ElixirML.Reasoning.ReAct => 4.0,
          ElixirML.Reasoning.SelfConsistency => 8.0
        }
      }
    )
  end

  @doc """
  Create a temperature variable with model-specific ranges.

  ## Examples

      iex> temp_var = ElixirML.Variable.MLTypes.temperature(:temperature)
      iex> temp_var.constraints.range
      {0.0, 2.0}
  """
  def temperature(name, opts \\ []) do
    range = Keyword.get(opts, :range, {0.0, 2.0})
    default = Keyword.get(opts, :default, 0.7)

    Variable.float(name,
      range: range,
      default: default,
      description: "Sampling temperature for randomness control",
      hints: [
        continuous: true,
        smooth_optimization: true,
        local_search_friendly: true
      ],
      metadata: %{
        effect: "Higher values increase randomness and creativity",
        sweet_spot: {0.3, 1.0},
        extreme_values: %{
          deterministic: 0.0,
          very_creative: 1.5,
          chaotic: 2.0
        }
      }
    )
  end

  @doc """
  Create a max_tokens variable with dynamic ranges based on model.

  ## Examples

      iex> tokens_var = ElixirML.Variable.MLTypes.max_tokens(:max_tokens)
      iex> tokens_var.type
      :integer
  """
  def max_tokens(name, opts \\ []) do
    range = Keyword.get(opts, :range, {1, 4096})
    default = Keyword.get(opts, :default, 1000)

    Variable.integer(name,
      range: range,
      default: default,
      description: "Maximum tokens to generate",
      dependencies: Keyword.get(opts, :dependencies, [:model]),
      hints: [
        cost_impact: :high,
        performance_impact: :medium
      ],
      metadata: %{
        cost_scaling: :linear,
        typical_ranges: %{
          short_response: {50, 200},
          medium_response: {200, 1000},
          long_response: {1000, 4000}
        }
      }
    )
  end

  @doc """
  Create a top_p variable for nucleus sampling.

  ## Examples

      iex> top_p_var = ElixirML.Variable.MLTypes.top_p(:top_p)
      iex> top_p_var.constraints.range
      {0.0, 1.0}
  """
  def top_p(name, opts \\ []) do
    Variable.float(name,
      range: {0.0, 1.0},
      default: Keyword.get(opts, :default, 0.9),
      description: "Nucleus sampling probability threshold",
      hints: [
        continuous: true,
        complementary_to: :temperature
      ],
      metadata: %{
        effect: "Controls diversity by focusing on cumulative probability mass",
        interaction_with_temperature: "Use lower values with higher temperature"
      }
    )
  end

  @doc """
  Create a frequency_penalty variable.
  """
  def frequency_penalty(name, opts \\ []) do
    Variable.float(name,
      range: {-2.0, 2.0},
      default: Keyword.get(opts, :default, 0.0),
      description: "Penalty for token frequency",
      hints: [
        continuous: true,
        fine_tuning_parameter: true
      ]
    )
  end

  @doc """
  Create a presence_penalty variable.
  """
  def presence_penalty(name, opts \\ []) do
    Variable.float(name,
      range: {-2.0, 2.0},
      default: Keyword.get(opts, :default, 0.0),
      description: "Penalty for token presence",
      hints: [
        continuous: true,
        fine_tuning_parameter: true
      ]
    )
  end

  @doc """
  Create a comprehensive ML model configuration variable space.

  This creates a complete variable space with all common ML parameters
  and their interdependencies properly configured.

  ## Examples

      iex> space = ElixirML.Variable.MLTypes.standard_ml_config()
      iex> map_size(space.variables) > 5
      true
  """
  def standard_ml_config(opts \\ []) do
    alias ElixirML.Variable.Space

    space =
      Space.new(
        name: Keyword.get(opts, :name, "Standard ML Configuration"),
        metadata: %{
          version: "1.0",
          description: "Standard ML model configuration with common parameters"
        }
      )

    # Core variables
    variables = [
      provider(:provider),
      model(:model, dependencies: [:provider]),
      temperature(:temperature),
      max_tokens(:max_tokens, dependencies: [:model]),
      top_p(:top_p),
      reasoning_strategy(:reasoning_strategy),
      adapter(:adapter)
    ]

    # Add optional variables based on options
    variables =
      if Keyword.get(opts, :include_penalties, false) do
        variables ++
          [
            frequency_penalty(:frequency_penalty),
            presence_penalty(:presence_penalty)
          ]
      else
        variables
      end

    space = Space.add_variables(space, variables)

    # Add cross-variable constraints
    space
    |> Space.add_constraint(&validate_provider_model_compatibility/1)
    |> Space.add_constraint(&validate_token_limits/1)
    |> Space.add_constraint(&validate_temperature_top_p_interaction/1)
  end

  @doc """
  Extract variables from a signature module with ML-specific enhancements.
  """
  def extract_from_signature(signature_module) do
    base_space = ElixirML.Variable.Space.from_signature(signature_module)

    # Enhance with ML-specific variables
    enhanced_variables = [
      provider(:provider),
      adapter(:adapter),
      reasoning_strategy(:reasoning_strategy),
      temperature(:temperature, range: {0.0, 2.0}, default: 0.7)
    ]

    ElixirML.Variable.Space.add_variables(base_space, enhanced_variables)
  end

  # Private helper functions

  defp model_capabilities(models) do
    Enum.reduce(models, %{}, fn model, acc ->
      capabilities =
        case model do
          "gpt-4" -> [:text, :reasoning, :code, :math]
          "gpt-4-turbo" -> [:text, :reasoning, :code, :math, :vision]
          "claude-3-opus" -> [:text, :reasoning, :code, :analysis]
          "llama-3-70b" -> [:text, :reasoning, :code]
          "gemini-pro" -> [:text, :reasoning, :code, :multimodal]
          _ -> [:text]
        end

      Map.put(acc, model, capabilities)
    end)
  end

  defp model_context_windows(models) do
    Enum.reduce(models, %{}, fn model, acc ->
      context_window =
        case model do
          "gpt-4" -> 8192
          "gpt-4-turbo" -> 128_000
          "claude-3-opus" -> 200_000
          "llama-3-70b" -> 8192
          "gemini-pro" -> 32_768
          _ -> 4096
        end

      Map.put(acc, model, context_window)
    end)
  end

  # Cross-variable constraint validators

  defp validate_provider_model_compatibility(config) do
    case {config[:provider], config[:model]} do
      {:openai, model} when model in ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"] ->
        {:ok, config}

      {:anthropic, model} when model in ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"] ->
        {:ok, config}

      {:groq, model} when model in ["llama-3-70b", "mixtral-8x7b", "gemma-7b"] ->
        {:ok, config}

      {:google, model} when model in ["gemini-pro", "gemini-pro-vision"] ->
        {:ok, config}

      # No provider specified
      {nil, _} ->
        {:ok, config}

      # No model specified
      {_, nil} ->
        {:ok, config}

      {provider, model} ->
        {:error, "Model #{model} not compatible with provider #{provider}"}
    end
  end

  defp validate_token_limits(config) do
    max_tokens = config[:max_tokens]
    model = config[:model]

    if max_tokens && model do
      context_window =
        case model do
          "gpt-4" -> 8192
          "gpt-4-turbo" -> 128_000
          "claude-3-opus" -> 200_000
          _ -> 4096
        end

      if max_tokens > context_window do
        {:error,
         "max_tokens #{max_tokens} exceeds context window #{context_window} for model #{model}"}
      else
        {:ok, config}
      end
    else
      {:ok, config}
    end
  end

  defp validate_temperature_top_p_interaction(config) do
    temp = config[:temperature]
    top_p = config[:top_p]

    if temp && top_p && temp > 1.5 && top_p < 0.3 do
      {:error, "High temperature (#{temp}) with low top_p (#{top_p}) may produce poor results"}
    else
      {:ok, config}
    end
  end
end
