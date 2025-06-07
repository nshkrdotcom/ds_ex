defmodule DSPEx.Signature do
  @moduledoc """
  Defines the `@behaviour` and `use` macro for creating DSPEx Signatures.

  A signature declaratively defines the inputs and outputs of a DSPEx program.
  Using this macro at compile-time generates an efficient struct and the necessary
  functions to interact with the framework.

  ## Example

      defmodule QASignature do
        @moduledoc "Answer questions with detailed reasoning"
        use DSPEx.Signature, "question -> answer"
      end

  This generates a module that implements the DSPEx.Signature behaviour and provides:
  - A struct with the specified fields
  - Functions to access input/output field lists
  - Validation functions for inputs and outputs
  - Instructions extracted from the module's @moduledoc

  ## Behaviour Callbacks

  - `instructions/0` - Returns the instruction string for this signature
  - `input_fields/0` - Returns list of input field names as atoms
  - `output_fields/0` - Returns list of output field names as atoms
  - `fields/0` - Returns all fields as a combined list
  """

  @doc "Returns the instruction string for this signature"
  @callback instructions() :: String.t()

  @doc "Returns list of input field names as atoms"
  @callback input_fields() :: list(atom())

  @doc "Returns list of output field names as atoms"
  @callback output_fields() :: list(atom())

  @doc "Returns all fields as a combined list"
  @callback fields() :: list(atom())

  defmacro __using__(signature_string) when is_binary(signature_string) do
    # Parse at compile time for efficiency
    {input_fields, output_fields} = DSPEx.Signature.Parser.parse(signature_string)
    all_fields = input_fields ++ output_fields

    quote do
      @behaviour DSPEx.Signature

      # Create struct with all fields, defaulting to nil
      defstruct unquote(all_fields |> Enum.map(&{&1, nil}))

      # Define type
      @type t :: %__MODULE__{}

      # Extract instructions from module doc at compile time
      @instructions (@moduledoc || "Given the fields #{inspect(unquote(input_fields))}, produce the fields #{inspect(unquote(output_fields))}.")

      # Store field lists as module attributes for efficiency
      @input_fields unquote(input_fields)
      @output_fields unquote(output_fields)
      @all_fields unquote(all_fields)

      # Implement behaviour callbacks
      @impl DSPEx.Signature
      def instructions(), do: @instructions

      @impl DSPEx.Signature
      def input_fields(), do: @input_fields

      @impl DSPEx.Signature
      def output_fields(), do: @output_fields

      @impl DSPEx.Signature
      def fields(), do: @all_fields

      # Convenience constructor
      def new(fields \\ %{}) when is_map(fields) do
        struct(__MODULE__, fields)
      end

      # Validation helper for inputs
      def validate_inputs(inputs) when is_map(inputs) do
        required_inputs = MapSet.new(@input_fields)
        provided_inputs = MapSet.new(Map.keys(inputs))

        missing = MapSet.difference(required_inputs, provided_inputs)
        case MapSet.size(missing) do
          0 -> :ok
          _ -> {:error, {:missing_inputs, MapSet.to_list(missing)}}
        end
      end

      # Validation helper for outputs
      def validate_outputs(outputs) when is_map(outputs) do
        required_outputs = MapSet.new(@output_fields)
        provided_outputs = MapSet.new(Map.keys(outputs))

        missing = MapSet.difference(required_outputs, provided_outputs)
        case MapSet.size(missing) do
          0 -> :ok
          _ -> {:error, {:missing_outputs, MapSet.to_list(missing)}}
        end
      end
    end
  end
end

defmodule DSPEx.Signature.Parser do
  @moduledoc false
  # This module is private and only used by the macro at compile time.

  @doc """
  Parses signature string into input and output field lists.

  Equivalent to Python's _parse_signature() function.

  ## Examples

      iex> DSPEx.Signature.Parser.parse("question -> answer")
      {[:question], [:answer]}

      iex> DSPEx.Signature.Parser.parse("question, context -> answer, confidence")
      {[:question, :context], [:answer, :confidence]}

  """
  @spec parse(String.t()) :: {list(atom()), list(atom())} | no_return()
  def parse(signature_string) when is_binary(signature_string) do
    signature_string
    |> String.trim()
    |> validate_format()
    |> split_signature()
    |> parse_fields()
    |> validate_fields()
  end

  # Validates basic format with arrow separator
  defp validate_format(str) do
    unless String.contains?(str, "->") do
      raise CompileError,
        description: "DSPEx signature must contain '->' separator. Example: 'question -> answer'",
        file: __ENV__.file,
        line: __ENV__.line
    end

    str
  end

  # Splits on arrow, handles whitespace
  defp split_signature(str) do
    case String.split(str, "->", parts: 2) do
      [inputs_str, outputs_str] -> {String.trim(inputs_str), String.trim(outputs_str)}
      _ ->
        raise CompileError,
          description: "Invalid DSPEx signature format. Must contain exactly one '->' separator.",
          file: __ENV__.file,
          line: __ENV__.line
    end
  end

  # Parses comma-separated field lists
  defp parse_fields({inputs_str, outputs_str}) do
    inputs = parse_field_list(inputs_str)
    outputs = parse_field_list(outputs_str)

    # Validate that both inputs and outputs are non-empty
    if Enum.empty?(inputs) do
      raise CompileError,
        description: "DSPEx signature must have at least one input field",
        file: __ENV__.file,
        line: __ENV__.line
    end

    if Enum.empty?(outputs) do
      raise CompileError,
        description: "DSPEx signature must have at least one output field",
        file: __ENV__.file,
        line: __ENV__.line
    end

    {inputs, outputs}
  end

  defp parse_field_list(""), do: []

  defp parse_field_list(str) do
    fields =
      str
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    # Check for empty fields before rejecting them
    if Enum.any?(fields, &(&1 == "")) do
      raise CompileError,
        description: "Empty field names are not allowed in DSPEx signatures",
        file: __ENV__.file,
        line: __ENV__.line
    end

    fields
    |> Enum.map(&validate_field_name/1)
    |> Enum.map(&String.to_atom/1)
  end

  # Validates field names are valid Elixir atoms
  defp validate_field_name(name) do
    unless Regex.match?(~r/^[a-z][a-zA-Z0-9_]*$/, name) do
      raise CompileError,
        description: "Invalid field name '#{name}'. Must be a valid Elixir atom starting with lowercase letter.",
        file: __ENV__.file,
        line: __ENV__.line
    end

    name
  end

  # Validates no duplicate fields
  defp validate_fields({inputs, outputs}) do
    all_fields = inputs ++ outputs
    unique_fields = Enum.uniq(all_fields)

    if length(all_fields) != length(unique_fields) do
      duplicates = all_fields -- unique_fields

      raise CompileError,
        description: "Duplicate fields found: #{inspect(duplicates)}",
        file: __ENV__.file,
        line: __ENV__.line
    end

    {inputs, outputs}
  end
end
