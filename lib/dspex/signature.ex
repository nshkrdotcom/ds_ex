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

  ## Generated Functions

  When using this module, the following functions are automatically generated:
  - `new/1` - Creates a new struct instance
  - `validate_inputs/1` - Validates input field completeness
  - `validate_outputs/1` - Validates output field completeness

  See the type specification `t()` for the generated struct type.
  """

  @typedoc "Validation result for input/output field checking"
  @type validation_result :: :ok | {:error, {:missing_inputs | :missing_outputs, [atom()]}}

  @doc "Returns the instruction string for this signature"
  @callback instructions() :: String.t()

  @doc "Returns list of input field names as atoms"
  @callback input_fields() :: [atom()]

  @doc "Returns list of output field names as atoms"
  @callback output_fields() :: [atom()]

  @doc "Returns all fields as a combined list"
  @callback fields() :: [atom()]

  @doc """
  Defines a DSPEx signature with the given signature string.

  The signature string follows the format: "input1, input2 -> output1, output2"

  ## Parameters
  - `signature_string` - A binary string defining the input/output signature

  ## Generated Module Features
  - Implements the DSPEx.Signature behaviour
  - Creates a struct with all specified fields
  - Generates validation and accessor functions
  - Extracts documentation from the module's @moduledoc

  ## Examples

      defmodule MySignature do
        use DSPEx.Signature, "question, context -> answer, confidence"
      end

      %MySignature{question: "test", context: "info", answer: "result", confidence: 0.9}
  """
  @spec __using__(binary()) :: Macro.t()
  defmacro __using__(signature_string) when is_binary(signature_string) do
    # Parse at compile time for efficiency
    {input_fields, output_fields} = DSPEx.Signature.Parser.parse(signature_string)
    all_fields = input_fields ++ output_fields

    quote do
      @behaviour DSPEx.Signature

      # Create struct with all fields, defaulting to nil
      defstruct unquote(all_fields |> Enum.map(&{&1, nil}))

      # Define comprehensive type specification
      @type t :: %__MODULE__{
              unquote_splicing(
                all_fields
                |> Enum.map(fn field ->
                  {field, quote(do: any())}
                end)
              )
            }

      # Extract instructions from module doc at compile time
      @instructions @moduledoc ||
                      "Given the fields #{inspect(unquote(input_fields))}, produce the fields #{inspect(unquote(output_fields))}."

      # Store field lists as module attributes for efficiency
      @input_fields unquote(input_fields)
      @output_fields unquote(output_fields)
      @all_fields unquote(all_fields)

      # Implement behaviour callbacks with proper specs
      @doc "Returns the instruction string extracted from @moduledoc or auto-generated"
      @spec instructions() :: String.t()
      @impl DSPEx.Signature
      def instructions(), do: @instructions

      @doc "Returns the list of input field names as atoms"
      @spec input_fields() :: [atom()]
      @impl DSPEx.Signature
      def input_fields(), do: @input_fields

      @doc "Returns the list of output field names as atoms"
      @spec output_fields() :: [atom()]
      @impl DSPEx.Signature
      def output_fields(), do: @output_fields

      @doc "Returns all fields (inputs + outputs) as a combined list"
      @spec fields() :: [atom()]
      @impl DSPEx.Signature
      def fields(), do: @all_fields

      @doc """
      Creates a new signature struct instance.

      ## Parameters
      - `fields` - A map of field names to values (optional, defaults to empty map)

      ## Returns
      - A new struct instance with the given field values

      ## Examples

          iex> MySignature.new(%{question: "test"})
          %MySignature{question: "test", answer: nil, ...}
      """
      @spec new(map()) :: t()
      def new(fields \\ %{}) when is_map(fields) do
        struct(__MODULE__, fields)
      end

      @doc """
      Validates that all required input fields are present and non-nil.

      ## Parameters
      - `inputs` - A map containing input field values

      ## Returns
      - `:ok` if all required input fields are present
      - `{:error, {:missing_inputs, [atom()]}}` if any required fields are missing

      ## Examples

          iex> MySignature.validate_inputs(%{question: "test", context: "info"})
          :ok

          iex> MySignature.validate_inputs(%{question: "test"})
          {:error, {:missing_inputs, [:context]}}
      """
      @spec validate_inputs(map()) :: DSPEx.Signature.validation_result()
      def validate_inputs(inputs) when is_map(inputs) do
        required_inputs = MapSet.new(@input_fields)
        provided_inputs = MapSet.new(Map.keys(inputs))

        missing = MapSet.difference(required_inputs, provided_inputs)

        case MapSet.size(missing) do
          0 -> :ok
          _ -> {:error, {:missing_inputs, MapSet.to_list(missing)}}
        end
      end

      @doc """
      Validates that all required output fields are present and non-nil.

      ## Parameters
      - `outputs` - A map containing output field values

      ## Returns
      - `:ok` if all required output fields are present
      - `{:error, {:missing_outputs, [atom()]}}` if any required fields are missing

      ## Examples

          iex> MySignature.validate_outputs(%{answer: "result", confidence: 0.9})
          :ok

          iex> MySignature.validate_outputs(%{answer: "result"})
          {:error, {:missing_outputs, [:confidence]}}
      """
      @spec validate_outputs(map()) :: DSPEx.Signature.validation_result()
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

  @typedoc "Parsed signature result as input and output field lists"
  @type parsed_signature :: {[atom()], [atom()]}

  @doc """
  Parses signature string into input and output field lists.

  Equivalent to Python's _parse_signature() function.

  ## Parameters
  - `signature_string` - The signature string to parse

  ## Returns
  - A tuple `{input_fields, output_fields}` where both are lists of atoms

  ## Raises
  - `CompileError` for invalid signature formats

  ## Examples

      iex> DSPEx.Signature.Parser.parse("question -> answer")
      {[:question], [:answer]}

      iex> DSPEx.Signature.Parser.parse("question, context -> answer, confidence")
      {[:question, :context], [:answer, :confidence]}

  """
  @spec parse(String.t()) :: parsed_signature() | no_return()
  def parse(signature_string) when is_binary(signature_string) do
    signature_string
    |> String.trim()
    |> validate_format()
    |> split_signature()
    |> parse_fields()
    |> validate_fields()
  end

  # Validates basic format with arrow separator
  @spec validate_format(String.t()) :: String.t() | no_return()
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
  @spec split_signature(String.t()) :: {String.t(), String.t()} | no_return()
  defp split_signature(str) do
    case String.split(str, "->", parts: 2) do
      [inputs_str, outputs_str] ->
        {String.trim(inputs_str), String.trim(outputs_str)}

      _ ->
        raise CompileError,
          description: "Invalid DSPEx signature format. Must contain exactly one '->' separator.",
          file: __ENV__.file,
          line: __ENV__.line
    end
  end

  # Parses comma-separated field lists
  @spec parse_fields({String.t(), String.t()}) :: parsed_signature() | no_return()
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

  @spec parse_field_list(String.t()) :: [atom()]
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
  @spec validate_field_name(String.t()) :: String.t() | no_return()
  defp validate_field_name(name) do
    unless Regex.match?(~r/^[a-z][a-zA-Z0-9_]*$/, name) do
      raise CompileError,
        description:
          "Invalid field name '#{name}'. Must be a valid Elixir atom starting with lowercase letter.",
        file: __ENV__.file,
        line: __ENV__.line
    end

    name
  end

  # Validates no duplicate fields
  @spec validate_fields(parsed_signature()) :: parsed_signature() | no_return()
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
