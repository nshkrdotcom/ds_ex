defmodule ProviderConfiguration do
  @moduledoc """
  Elixact schema for DSPEx provider configuration validation.

  Validates provider-specific settings including API keys, URLs, models, timeouts,
  rate limits, and circuit breaker configurations.
  """

  use Elixact

  schema "DSPEx provider configuration settings" do
    field :api_key, :string do
      description("API key as string or {:system, env_var} tuple")
      example("sk-abc123")
      optional()
    end

    field :base_url, :string do
      description("Base URL for the provider API")
      example("https://api.example.com")
      optional()
    end

    field :default_model, :string do
      description("Default model to use for requests")
      example("gpt-4")
      optional()
    end

    field :timeout, :integer do
      description("Request timeout in milliseconds")
      gteq(1)
      example(30000)
      optional()
    end

    config do
      title("Provider Configuration")
      strict(false)
    end
  end
end
