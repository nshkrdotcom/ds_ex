# dspex/teleprompter/simba/trajectory.ex
defmodule DSPEx.Teleprompter.SIMBA.Trajectory do
  @moduledoc """
  Represents a single execution trajectory through a program.

  A trajectory captures the complete execution context including inputs,
  outputs, performance score, and execution metadata.
  """

  @enforce_keys [:program, :example, :inputs, :outputs, :score]
  defstruct [
    :program,        # The program that was executed
    :example,        # The example that was processed
    :inputs,         # Input values
    :outputs,        # Output values
    :score,          # Performance score from metric function
    :duration,       # Execution time in native units
    :model_config,   # Model configuration used
    :success,        # Whether execution succeeded
    :error,          # Error details if execution failed
    :metadata        # Additional metadata
  ]

  @type t :: %__MODULE__{
          program: struct(),
          example: DSPEx.Example.t(),
          inputs: map(),
          outputs: map(),
          score: float(),
          duration: integer() | nil,
          model_config: map() | nil,
          success: boolean() | nil,
          error: term() | nil,
          metadata: map() | nil
        }

  @doc """
  Create a new trajectory.
  """
  @spec new(struct(), DSPEx.Example.t(), map(), map(), float(), keyword()) :: t()
  def new(program, example, inputs, outputs, score, opts \\ []) do
    %__MODULE__{
      program: program,
      example: example,
      inputs: inputs,
      outputs: outputs,
      score: score,
      duration: Keyword.get(opts, :duration),
      model_config: Keyword.get(opts, :model_config),
      success: Keyword.get(opts, :success, true),
      error: Keyword.get(opts, :error),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Check if trajectory represents a successful execution.
  """
  @spec successful?(t()) :: boolean()
  def successful?(%__MODULE__{success: success, score: score}) do
    success != false and score > 0.0
  end

  @doc """
  Get quality score for the trajectory.
  """
  @spec quality_score(t()) :: float()
  def quality_score(%__MODULE__{score: score}), do: score

  @doc """
  Create a demonstration example from a successful trajectory.
  """
  @spec to_demo(t()) :: {:ok, DSPEx.Example.t()} | {:error, term()}
  def to_demo(%__MODULE__{inputs: inputs, outputs: outputs, success: true}) do
    combined_data = Map.merge(inputs, outputs)
    input_keys = Map.keys(inputs)

    demo = DSPEx.Example.new(combined_data, input_keys)
    {:ok, demo}
  end

  def to_demo(%__MODULE__{success: false}) do
    {:error, :trajectory_failed}
  end

  def to_demo(%__MODULE__{score: score}) when score <= 0.0 do
    {:error, :low_quality_score}
  end
end
