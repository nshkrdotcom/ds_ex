defmodule EvaluationConfiguration do
  @moduledoc """
  Elixact schema for DSPEx evaluation configuration validation.

  Validates evaluation settings including batch sizes and parallel processing limits.
  """

  use Elixact

  schema "DSPEx evaluation configuration settings" do
    field :batch_size, :integer do
      description("Batch size for evaluation processing")
      gteq(1)
      example(10)
      optional()
    end

    field :parallel_limit, :integer do
      description("Maximum number of parallel evaluation operations")
      gteq(1)
      example(4)
      optional()
    end

    config do
      title("Evaluation Configuration")
      strict(false)
    end
  end
end
