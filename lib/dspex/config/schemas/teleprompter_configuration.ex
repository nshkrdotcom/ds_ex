defmodule TeleprompterConfiguration do
  @moduledoc """
  Elixact schema for DSPEx teleprompter configuration validation.

  Validates teleprompter settings including bootstrap examples and validation thresholds.
  """

  use Elixact

  schema "DSPEx teleprompter configuration settings" do
    field :bootstrap_examples, :integer do
      description("Number of bootstrap examples to use")
      gteq(1)
      example(5)
      optional()
    end

    field :validation_threshold, :float do
      description("Validation threshold for teleprompter optimization")
      gteq(0.0)
      lteq(1.0)
      example(0.8)
      optional()
    end

    config do
      title("Teleprompter Configuration")
      strict(false)
    end
  end
end
