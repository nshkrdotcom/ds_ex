defmodule LoggingConfiguration do
  @moduledoc """
  Elixact schema for DSPEx logging configuration validation.

  Validates logging settings including log levels and correlation options.
  """

  use Elixact

  schema "DSPEx logging configuration settings" do
    field :level, :string do
      description("Log level for DSPEx operations")
      example("info")
      optional()
    end

    field :correlation_enabled, :boolean do
      description("Whether request correlation is enabled")
      example(true)
      optional()
    end

    config do
      title("Logging Configuration")
      strict(false)
    end
  end
end
