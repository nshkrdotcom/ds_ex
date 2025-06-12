# dspex/teleprompter/simba/strategy.ex
defmodule DSPEx.Teleprompter.SIMBA.Strategy do
  @moduledoc """
  Behavior for SIMBA optimization strategies.

  Strategies are simple rules that create new program variants from
  successful execution trajectories.
  """

  alias DSPEx.Teleprompter.SIMBA.{Bucket, Trajectory}

  @doc """
  Apply the strategy to a bucket to create a new program variant.

  ## Parameters
  - `bucket` - Bucket containing trajectories to analyze
  - `source_program` - Base program to modify
  - `opts` - Strategy-specific options

  ## Returns
  - `{:ok, new_program}` - Successfully created new program variant
  - `{:skip, reason}` - Strategy not applicable or failed
  """
  @callback apply(Bucket.t(), struct(), map()) ::
    {:ok, struct()} | {:skip, String.t()}

  @doc """
  Check if strategy is applicable to the given bucket.
  """
  @callback applicable?(Bucket.t(), map()) :: boolean()

  @optional_callbacks [applicable?: 2]
end
