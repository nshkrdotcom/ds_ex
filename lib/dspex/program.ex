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
    # PERFORMANCE INSTRUMENTATION - Start
    total_start = System.monotonic_time()

    # Step 1: Correlation ID generation (optimized for performance)
    correlation_start = System.monotonic_time()

    correlation_id =
      case Keyword.get(opts, :correlation_id) do
        nil ->
          # Use fast UUID generation to avoid crypto cold start
          # Format: test-{node}-{timestamp}-{random}
          node_hash = :erlang.phash2(node(), 65536)
          timestamp = System.unique_integer([:positive])
          random = :erlang.unique_integer([:positive])
          "test-#{node_hash}-#{timestamp}-#{random}"

        existing_id ->
          existing_id
      end

    _correlation_duration =
      System.convert_time_unit(System.monotonic_time() - correlation_start, :native, :microsecond)

    # Step 2: Program name resolution
    program_name_start = System.monotonic_time()
    program_name = program_name(program)

    _program_name_duration =
      System.convert_time_unit(
        System.monotonic_time() - program_name_start,
        :native,
        :microsecond
      )

    # Step 3: Start telemetry
    telemetry_start_time = System.monotonic_time()
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :program, :forward, :start],
      %{system_time: System.system_time()},
      %{
        program: program_name,
        correlation_id: correlation_id,
        input_count: map_size(inputs)
      }
    )

    _telemetry_start_duration =
      System.convert_time_unit(
        System.monotonic_time() - telemetry_start_time,
        :native,
        :microsecond
      )

    # Step 4: Actual program execution
    execution_start = System.monotonic_time()
    result = program.__struct__.forward(program, inputs, opts)

    _execution_duration =
      System.convert_time_unit(System.monotonic_time() - execution_start, :native, :microsecond)

    # Step 5: Stop telemetry
    telemetry_stop_start = System.monotonic_time()
    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :program, :forward, :stop],
      %{duration: duration, success: success},
      %{
        program: program_name,
        correlation_id: correlation_id
      }
    )

    _telemetry_stop_duration =
      System.convert_time_unit(
        System.monotonic_time() - telemetry_stop_start,
        :native,
        :microsecond
      )

    # PERFORMANCE INSTRUMENTATION - Report
    _total_duration =
      System.convert_time_unit(System.monotonic_time() - total_start, :native, :microsecond)

    # Performance instrumentation (disabled for production)
    # IO.puts("🔍 DSPEx.Program.forward [#{_total_duration}µs]: ID=#{_correlation_duration}µs, Name=#{_program_name_duration}µs, StartTel=#{_telemetry_start_duration}µs, Exec=#{_execution_duration}µs, StopTel=#{_telemetry_stop_duration}µs")

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

  @doc """
  Determine the type of a program.

  Returns the general category of the program based on its struct type.
  Useful for optimization and introspection workflows.

  ## Returns

  - `:predict` - For DSPEx.Predict programs
  - `:optimized` - For DSPEx.OptimizedProgram programs
  - `:custom` - For other program types

  ## Examples

      iex> predict = %DSPEx.Predict{signature: MySignature, client: :openai}
      iex> DSPEx.Program.program_type(predict)
      :predict

      iex> optimized = %DSPEx.OptimizedProgram{program: predict, demos: []}
      iex> DSPEx.Program.program_type(optimized)
      :optimized

  """
  @spec program_type(t()) :: :predict | :optimized | :custom
  def program_type(program) when is_struct(program) do
    case program.__struct__ |> Module.split() |> List.last() do
      "Predict" -> :predict
      "OptimizedProgram" -> :optimized
      _ -> :custom
    end
  end

  def program_type(_), do: :custom

  @doc """
  Get sanitized information about a program.

  Returns a map with safe information about the program that doesn't
  expose sensitive data like API keys or internal prompts.

  ## Parameters

  - `program` - The program struct to introspect

  ## Returns

  Map with keys:
  - `:type` - Program type (see `program_type/1`)
  - `:has_demos` - Whether the program has demonstration examples
  - `:name` - Human-readable program name
  - `:signature` - Signature module name (if available)
  - `:demo_count` - Number of demonstrations (if applicable)

  """
  @spec safe_program_info(t()) :: %{
          type: atom(),
          has_demos: boolean(),
          name: String.t(),
          signature: atom() | nil,
          demo_count: integer()
        }
  def safe_program_info(program) do
    type = program_type(program)
    demo_count = demo_count(program)

    %{
      type: type,
      has_demos: has_demos?(program),
      name: program_name(program) |> Atom.to_string(),
      signature: get_signature_module(program),
      demo_count: demo_count
    }
  end

  @doc """
  Check if a program has demonstration examples.

  Returns true if the program contains demonstration examples that can
  be used for few-shot learning or optimization.

  ## Examples

      iex> predict = %DSPEx.Predict{signature: MySignature, client: :openai, demos: []}
      iex> DSPEx.Program.has_demos?(predict)
      false

      iex> predict_with_demos = %DSPEx.Predict{signature: MySignature, client: :openai, demos: [%{}]}
      iex> DSPEx.Program.has_demos?(predict_with_demos)
      true

  """
  @spec has_demos?(t()) :: boolean()
  def has_demos?(program) do
    demo_count(program) > 0
  end

  # Private helper functions

  defp demo_count(program) do
    cond do
      is_struct(program) and Map.has_key?(program, :demos) and is_list(program.demos) ->
        length(program.demos)

      true ->
        0
    end
  end

  defp get_signature_module(program) when is_struct(program) do
    cond do
      # For Predict programs
      Map.has_key?(program, :signature) and is_atom(program.signature) ->
        program.signature

      # For OptimizedProgram wrapping Predict
      Map.has_key?(program, :program) and is_struct(program.program) and
          Map.has_key?(program.program, :signature) ->
        program.program.signature

      true ->
        nil
    end
  end

  defp get_signature_module(_), do: nil
end
