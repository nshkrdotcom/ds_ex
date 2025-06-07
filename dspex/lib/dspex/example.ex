defmodule DSPEx.Example do
  @moduledoc """
  Represents an example data structure for DSPEx programs.

  An Example holds input/output data and provides methods for manipulation,
  conversion, and validation. This is equivalent to Python DSPy's Example class
  but designed for Elixir's functional paradigm.

  ## Example

      # Create example with data
      example = DSPEx.Example.new(%{question: "What is 2+2?", answer: "4"})

      # Access data
      DSPEx.Example.get(example, :question)  # "What is 2+2?"

      # Update data
      updated = DSPEx.Example.put(example, :confidence, 0.95)

      # Convert to different formats
      DSPEx.Example.to_dict(example)  # %{question: "What is 2+2?", answer: "4"}

  ## Data Structure

  The Example struct contains:
  - `data`: Map containing the actual key-value pairs
  - `input_keys`: MapSet of keys that are considered inputs (for validation)
  """

  defstruct data: %{}, input_keys: MapSet.new()

  @type t :: %__MODULE__{
          data: map(),
          input_keys: MapSet.t(atom())
        }

  @doc """
  Creates a new Example from data.

  ## Examples

      iex> DSPEx.Example.new()
      %DSPEx.Example{data: %{}, input_keys: #MapSet<[]>}

      iex> DSPEx.Example.new(%{question: "What is 2+2?"})
      %DSPEx.Example{data: %{question: "What is 2+2?"}, input_keys: #MapSet<[]>}

  """
  @spec new(map() | keyword()) :: t()
  def new(data \\ %{})

  def new(data) when is_map(data) do
    %__MODULE__{
      data: data,
      input_keys: MapSet.new()
    }
  end

  def new(data) when is_list(data) do
    new(Enum.into(data, %{}))
  end

  @doc """
  Creates a new Example with specified input keys.

  Input keys are used for validation and separation of concerns.

  ## Examples

      iex> DSPEx.Example.new(%{question: "Hi", answer: "Hello"}, [:question])
      %DSPEx.Example{
        data: %{question: "Hi", answer: "Hello"},
        input_keys: #MapSet<[:question]>
      }

  """
  @spec new(map() | keyword(), list(atom())) :: t()
  def new(data, input_keys) when is_list(input_keys) do
    data
    |> new()
    |> Map.put(:input_keys, MapSet.new(input_keys))
  end

  @doc """
  Gets a value from the example data.

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "What is 2+2?"})
      iex> DSPEx.Example.get(example, :question)
      "What is 2+2?"

      iex> DSPEx.Example.get(example, :missing)
      nil

      iex> DSPEx.Example.get(example, :missing, "default")
      "default"

  """
  @spec get(t(), atom(), any()) :: any()
  def get(%__MODULE__{data: data}, key, default \\ nil) do
    Map.get(data, key, default)
  end

  @doc """
  Puts a value into the example data, returning a new example.

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "What is 2+2?"})
      iex> updated = DSPEx.Example.put(example, :answer, "4")
      iex> updated.data
      %{question: "What is 2+2?", answer: "4"}

  """
  @spec put(t(), atom(), any()) :: t()
  def put(%__MODULE__{} = example, key, value) do
    %{example | data: Map.put(example.data, key, value)}
  end

  @doc """
  Updates multiple values in the example data.

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "What is 2+2?"})
      iex> updated = DSPEx.Example.merge(example, %{answer: "4", confidence: 0.9})
      iex> updated.data
      %{question: "What is 2+2?", answer: "4", confidence: 0.9}

  """
  @spec merge(t(), map()) :: t()
  def merge(%__MODULE__{} = example, new_data) when is_map(new_data) do
    %{example | data: Map.merge(example.data, new_data)}
  end

  @doc """
  Deletes a key from the example data.

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello", temp: "remove"})
      iex> cleaned = DSPEx.Example.delete(example, :temp)
      iex> cleaned.data
      %{question: "Hi", answer: "Hello"}

  """
  @spec delete(t(), atom()) :: t()
  def delete(%__MODULE__{} = example, key) do
    %{example | data: Map.delete(example.data, key)}
  end

  @doc """
  Designates which keys are considered inputs (does not filter data).

  ## Examples

      iex> example = DSPEx.Example.new(%{q: "Hi", a: "Hello", extra: "data"})
      iex> with_inputs = DSPEx.Example.with_inputs(example, [:q])
      iex> with_inputs.data
      %{q: "Hi", a: "Hello", extra: "data"}
      iex> MapSet.to_list(with_inputs.input_keys)
      [:q]

  """
  @spec with_inputs(t(), list(atom())) :: t()
  def with_inputs(%__MODULE__{} = example, keys) when is_list(keys) do
    %{example | input_keys: MapSet.new(keys)}
  end

  @doc """
  Filters example data to only include outputs (non-input keys).

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"}, [:question])
      iex> outputs = DSPEx.Example.with_outputs(example)
      iex> outputs.data
      %{answer: "Hello"}

  """
  @spec with_outputs(t()) :: t()
  def with_outputs(%__MODULE__{data: data, input_keys: input_keys} = example) do
    output_keys =
      data
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.difference(input_keys)
      |> MapSet.to_list()

    filtered_data = Map.take(data, output_keys)
    %{example | data: filtered_data, input_keys: MapSet.new()}
  end

  @doc """
  Returns the input data only.

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"}, [:question])
      iex> DSPEx.Example.inputs(example)
      %{question: "Hi"}

  """
  @spec inputs(t()) :: map()
  def inputs(%__MODULE__{data: data, input_keys: input_keys}) do
    input_keys
    |> MapSet.to_list()
    |> case do
      [] -> %{}
      keys -> Map.take(data, keys)
    end
  end

    @doc """
  Returns the output data only.

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"}, [:question])
      iex> DSPEx.Example.outputs(example)
      %{answer: "Hello"}

  """
  @spec outputs(t()) :: map()
  def outputs(%__MODULE__{data: data, input_keys: input_keys}) do
    output_keys =
      data
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.difference(input_keys)
      |> MapSet.to_list()

    Map.take(data, output_keys)
  end

  @doc """
  Returns the output data only (alias for outputs/1 for DSPy compatibility).

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"}, [:question])
      iex> DSPEx.Example.labels(example)
      %{answer: "Hello"}

  """
  @spec labels(t()) :: map()
  def labels(%__MODULE__{} = example), do: outputs(example)

  @doc """
  Converts example to a plain map (equivalent to Python's toDict()).

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"})
      iex> DSPEx.Example.to_dict(example)
      %{question: "Hi", answer: "Hello"}

  """
  @spec to_dict(t()) :: map()
  def to_dict(%__MODULE__{data: data}), do: data

  @doc """
  Converts example to a keyword list.

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"})
      iex> DSPEx.Example.to_list(example) |> Enum.sort()
      [answer: "Hello", question: "Hi"]

  """
  @spec to_list(t()) :: keyword()
  def to_list(%__MODULE__{data: data}), do: Map.to_list(data)

  @doc """
  Returns all keys in the example.

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"})
      iex> DSPEx.Example.keys(example) |> Enum.sort()
      [:answer, :question]

  """
  @spec keys(t()) :: list(atom())
  def keys(%__MODULE__{data: data}), do: Map.keys(data)

  @doc """
  Returns all values in the example.

  ## Examples

      iex> example = DSPEx.Example.new(%{a: 1, b: 2})
      iex> DSPEx.Example.values(example) |> Enum.sort()
      [1, 2]

  """
  @spec values(t()) :: list(any())
  def values(%__MODULE__{data: data}), do: Map.values(data)

  @doc """
  Checks if the example is empty.

  ## Examples

      iex> DSPEx.Example.empty?(%DSPEx.Example{})
      true

      iex> DSPEx.Example.empty?(DSPEx.Example.new(%{a: 1}))
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{data: data}), do: map_size(data) == 0

  @doc """
  Returns the size (number of key-value pairs) of the example.

  ## Examples

      iex> example = DSPEx.Example.new(%{a: 1, b: 2, c: 3})
      iex> DSPEx.Example.size(example)
      3

  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{data: data}), do: map_size(data)

  @doc """
  Checks if a key exists in the example.

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi"})
      iex> DSPEx.Example.has_key?(example, :question)
      true

      iex> DSPEx.Example.has_key?(example, :answer)
      false

  """
  @spec has_key?(t(), atom()) :: boolean()
  def has_key?(%__MODULE__{data: data}, key), do: Map.has_key?(data, key)

  # Protocol implementations for better integration

  defimpl Enumerable do
    def count(%DSPEx.Example{data: data}), do: {:ok, map_size(data)}

    def member?(%DSPEx.Example{data: data}, {key, value}) do
      {:ok, Map.get(data, key) == value}
    end

    def member?(%DSPEx.Example{}, _), do: {:ok, false}

    def slice(%DSPEx.Example{}), do: {:error, __MODULE__}

    def reduce(%DSPEx.Example{data: data}, acc, fun) do
      Enumerable.reduce(data, acc, fun)
    end
  end

  defimpl Collectable do
    def into(%DSPEx.Example{} = original) do
      collector_fun = fn
        example_acc, {:cont, {key, value}} ->
          DSPEx.Example.put(example_acc, key, value)
        example_acc, :done ->
          example_acc
        _example_acc, :halt ->
          :ok
      end

      {original, collector_fun}
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%DSPEx.Example{data: data, input_keys: input_keys}, opts) do
      input_keys_list = MapSet.to_list(input_keys)

      concat([
        "#DSPEx.Example<",
        to_doc(data, opts),
        if input_keys_list != [] do
          concat([", inputs: ", to_doc(input_keys_list, opts)])
        else
          empty()
        end,
        ">"
      ])
    end
  end
end
