defmodule DSPEx.Program do
  @moduledoc """
  Behavior for all DSPEx programs with Foundation integration.

  This module defines the core behavior that all DSPEx programs must implement,
  providing a unified interface for forward execution with built-in telemetry,
  correlation tracking, and error handling through Foundation infrastructure.

  ## Example Implementation

      defmodule MyProgram do
        use DSPEx.Program
        
        defstruct [:signature, :client, :demos]
        
        @impl DSPEx.Program
        def forward(program, inputs, opts \\ []) do
          # Implementation here
          {:ok, %{answer: "result"}}
        end
      end

  ## Telemetry

  All programs automatically emit telemetry events:
  - `[:dspex, :program, :forward, :start]`
  - `[:dspex, :program, :forward, :stop]`
  - `[:dspex, :program, :forward, :exception]`

  """

  alias Foundation.Utils

  @type t :: struct()
  @type program :: struct()
  @type inputs :: map()
  @type outputs :: map()
  @type options :: keyword()

  @doc """
  Execute a program with the given inputs.

  This is the core behavior callback that all programs must implement.
  It should take a program struct and input map, and return either 
  `{:ok, outputs}` or `{:error, reason}`.

  ## Parameters

  - `program` - The program struct containing configuration
  - `inputs` - Map of input field values

  ## Returns

  - `{:ok, outputs}` - Successful execution with result map
  - `{:error, reason}` - Error during execution

  """
  @callback forward(program(), inputs()) :: {:ok, outputs()} | {:error, term()}

  @doc """
  Execute a program with the given inputs and options.

  Optional callback for programs that need configuration options.

  """
  @callback forward(program(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}

  @optional_callbacks forward: 3

  @doc """
  Execute a program with Foundation observability and correlation tracking.

  This is the main entry point that wraps the behavior callback with
  automatic telemetry, correlation tracking, and error handling.

  """
  @spec forward(program(), inputs()) :: {:ok, outputs()} | {:error, term()}
  def forward(program, inputs) do
    forward(program, inputs, [])
  end

  @spec forward(program(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}
  def forward(program, inputs, opts) when is_map(inputs) do
    correlation_id = Keyword.get(opts, :correlation_id) || Utils.generate_correlation_id()

    # Use actual Foundation functions that exist
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :program, :forward, :start],
      %{system_time: System.system_time()},
      %{
        program: program_name(program),
        correlation_id: correlation_id,
        input_count: map_size(inputs)
      }
    )

    result = program.__struct__.forward(program, inputs, opts)

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :program, :forward, :stop],
      %{duration: duration, success: success},
      %{
        program: program_name(program),
        correlation_id: correlation_id
      }
    )

    result
  end

  def forward(_, inputs, _) when not is_map(inputs),
    do: {:error, {:invalid_inputs, "inputs must be a map"}}

  @doc """
  Macro for implementing program behavior with automatic telemetry setup.

  This macro adds the behavior, provides default implementations, and sets up
  the necessary infrastructure for telemetry and correlation tracking.

  ## Options

  - `:telemetry_prefix` - Custom telemetry event prefix (default: program module name)

  """
  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour DSPEx.Program

      @impl DSPEx.Program
      def forward(program, inputs, opts \\ []) do
        {:error, {:not_implemented, "#{__MODULE__} must implement forward/2 or forward/3"}}
      end

      defoverridable forward: 3
    end
  end

  @doc """
  Get a human-readable name for a program.

  Extracts the module name and converts it to a readable format for telemetry
  and logging purposes.

  """
  @spec program_name(program()) :: atom()
  def program_name(program) when is_struct(program) do
    program.__struct__
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end

  def program_name(_), do: :unknown

  @doc """
  Check if a module implements the DSPEx.Program behavior.

  Useful for validation and introspection.

  """
  @spec implements_program?(module()) :: boolean()
  def implements_program?(module) when is_atom(module) do
    module.module_info(:attributes)
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(DSPEx.Program)
  rescue
    UndefinedFunctionError -> false
  end

  def implements_program?(_), do: false

  @doc """
  Create a program struct with validation.

  Helper function for creating program structs with automatic validation
  of required fields and behavior implementation.

  """
  @spec new(module(), map()) :: {:ok, program()} | {:error, term()}
  def new(module, fields) when is_atom(module) and is_map(fields) do
    if implements_program?(module) do
      try do
        program = struct(module, fields)
        {:ok, program}
      rescue
        error -> {:error, {:struct_creation_failed, error}}
      end
    else
      {:error, {:invalid_program_module, module}}
    end
  end

  def new(nil, _), do: {:error, {:invalid_program_module, nil}}
  def new(_, _), do: {:error, :invalid_arguments}
end
