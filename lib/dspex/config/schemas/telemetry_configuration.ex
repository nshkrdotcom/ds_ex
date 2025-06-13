defmodule TelemetryConfiguration do
  @moduledoc """
  Elixact schema for DSPEx telemetry configuration validation.

  Validates telemetry settings including enabled state, detailed logging,
  and performance tracking options.
  """

  use Elixact

  schema "DSPEx telemetry configuration settings" do
    field :enabled, :boolean do
      description("Whether telemetry collection is enabled")
      example(true)
      optional()
    end

    field :detailed_logging, :boolean do
      description("Whether detailed telemetry logging is enabled")
      example(false)
      optional()
    end

    field :performance_tracking, :boolean do
      description("Whether performance metrics are tracked")
      example(true)
      optional()
    end

    config do
      title("Telemetry Configuration")
      strict(false)
    end
  end
end
