defmodule DSPEx.OptimizedProgram do
  @moduledoc """
  Wrapper for programs that have been optimized with demonstrations.

  This module provides a container for programs that don't natively support
  demonstration storage, allowing any program to be enhanced with few-shot
  learning capabilities through teleprompter optimization.
  """

  use DSPEx.Program

  defstruct [:program, :demos, :metadata]

  @type t :: %__MODULE__{
          program: struct(),
          demos: [DSPEx.Example.t()],
          metadata: map()
        }

  @doc """
  Create a new optimized program wrapper.

  ## Parameters

  - `program`: The original program to wrap
  - `demos`: List of demonstration examples
  - `metadata`: Optional metadata about the optimization (default: empty map)
  """
  @spec new(struct(), [DSPEx.Example.t()], map()) :: t()
  def new(program, demos, metadata \\ %{}) do
    # Handle nil metadata gracefully
    safe_metadata = metadata || %{}

    %__MODULE__{
      program: program,
      demos: demos,
      metadata:
        Map.merge(
          %{
            optimized_at: DateTime.utc_now(),
            demo_count: length(demos)
          },
          safe_metadata
        )
    }
  end

  @impl DSPEx.Program
  def forward(%__MODULE__{program: program, demos: demos}, inputs, opts) do
    # If the wrapped program supports demos, pass them through
    case program do
      %{demos: _} ->
        # Program has native demo support, update it
        enhanced_program = %{program | demos: demos}
        DSPEx.Program.forward(enhanced_program, inputs, opts)

      _ ->
        # Program doesn't have native demo support, pass demos in options
        DSPEx.Program.forward(program, inputs, Keyword.put(opts, :demos, demos))
    end
  end

  @doc """
  Get the demonstration examples from the optimized program.
  """
  @spec get_demos(t()) :: [DSPEx.Example.t()]
  def get_demos(%__MODULE__{demos: demos}), do: demos

  @doc """
  Get the original program from the optimized wrapper.
  """
  @spec get_program(t()) :: struct()
  def get_program(%__MODULE__{program: program}), do: program

  @doc """
  Get optimization metadata.
  """
  @spec get_metadata(t()) :: map()
  def get_metadata(%__MODULE__{metadata: metadata}), do: metadata

  @doc """
  Add additional demonstrations to the optimized program.
  """
  @spec add_demos(t(), [DSPEx.Example.t()]) :: t()
  def add_demos(%__MODULE__{demos: existing_demos} = optimized, new_demos) do
    %{
      optimized
      | demos: existing_demos ++ new_demos,
        metadata:
          Map.put(optimized.metadata, :demo_count, length(existing_demos) + length(new_demos))
    }
  end

  @doc """
  Replace demonstrations in the optimized program.
  """
  @spec replace_demos(t(), [DSPEx.Example.t()]) :: t()
  def replace_demos(%__MODULE__{} = optimized, new_demos) do
    %{
      optimized
      | demos: new_demos,
        metadata: Map.put(optimized.metadata, :demo_count, length(new_demos))
    }
  end

  @doc """
  Update the wrapped program while preserving demos and metadata.
  """
  @spec update_program(t(), struct()) :: t()
  def update_program(%__MODULE__{} = optimized, new_program) do
    %{optimized | program: new_program}
  end

  @doc """
  Check if a program natively supports demonstrations.

  Returns true if the program struct has a `demos` field, false otherwise.
  """
  @spec supports_native_demos?(struct()) :: boolean()
  def supports_native_demos?(program) when is_struct(program) do
    Map.has_key?(program, :demos)
  end

  def supports_native_demos?(_), do: false
end
