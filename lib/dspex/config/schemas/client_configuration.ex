defmodule ClientConfiguration do
  @moduledoc """
  Elixact schema for DSPEx client configuration validation.

  Validates client-level settings including timeouts, retries, and backoff factors.
  """

  use Elixact

  schema "DSPEx client configuration settings" do
    field :timeout, :integer do
      description("Request timeout in milliseconds")
      gteq(1)
      example(30_000)
      optional()
    end

    field :retry_attempts, :integer do
      description("Number of retry attempts for failed requests")
      gteq(0)
      example(3)
      optional()
    end

    field :backoff_factor, :float do
      description("Exponential backoff factor for retries")
      gt(0.0)
      example(2.0)
      optional()
    end

    config do
      title("Client Configuration")
      strict(false)
    end
  end
end
