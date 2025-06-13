defmodule PredictionConfiguration do
  @moduledoc """
  Elixact schema for DSPEx prediction configuration validation.

  Validates prediction-level settings including providers, temperature,
  max tokens, and caching options.
  """

  use Elixact

  schema "DSPEx prediction configuration settings" do
    field :default_provider, :string do
      description("Default provider for predictions")
      example("gemini")
      optional()
    end

    field :default_temperature, :float do
      description("Default temperature for predictions")
      gteq(0.0)
      lteq(2.0)
      example(0.7)
      optional()
    end

    field :default_max_tokens, :integer do
      description("Default maximum tokens for responses")
      gteq(1)
      example(1000)
      optional()
    end

    field :cache_enabled, :boolean do
      description("Whether response caching is enabled")
      example(true)
      optional()
    end

    field :cache_ttl, :integer do
      description("Cache time-to-live in seconds")
      gteq(1)
      example(3600)
      optional()
    end

    config do
      title("Prediction Configuration")
      strict(false)
    end
  end
end
