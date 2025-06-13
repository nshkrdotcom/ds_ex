defmodule BEACONConfiguration do
  @moduledoc """
  Elixact schema for DSPEx BEACON teleprompter configuration validation.

  Validates BEACON-specific settings including models, optimization parameters,
  and Bayesian optimization configurations.
  """

  use Elixact

  schema "DSPEx BEACON teleprompter configuration settings" do
    field :default_instruction_model, :string do
      description("Default model for instruction generation")
      example("gemini")
      optional()
    end

    field :default_evaluation_model, :string do
      description("Default model for evaluation")
      example("gemini")
      optional()
    end

    field :max_concurrent_operations, :integer do
      description("Maximum concurrent optimization operations")
      gteq(1)
      example(5)
      optional()
    end

    field :default_timeout, :integer do
      description("Default timeout for operations in milliseconds")
      gteq(1)
      example(30000)
      optional()
    end

    config do
      title("BEACON Configuration")
      strict(false)
    end
  end
end
