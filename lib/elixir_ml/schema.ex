defmodule ElixirML.Schema do
  @moduledoc """
  Enhanced schema system for ElixirML/DSPEx with ML-specific types,
  compile-time optimization, and comprehensive validation.

  Built on Sinter for advanced schema capabilities with native support
  for ML-specific types like embeddings, probabilities, and confidence scores.
  """

  alias ElixirML.Schema.Runtime

  defmacro __using__(_opts) do
    quote do
      import ElixirML.Schema, only: [defschema: 2]
    end
  end

  defmacro defschema(name, do: block) do
    quote do
      defmodule unquote(name) do
        use ElixirML.Schema.Definition
        import ElixirML.Schema.DSL

        unquote(block)

        @before_compile ElixirML.Schema.Compiler
      end
    end
  end

  @doc """
  Create a runtime schema for dynamic validation.

  ## Examples

      iex> schema = ElixirML.Schema.create([
      ...>   {:embedding, :embedding, required: true},
      ...>   {:confidence, :probability, default: 0.5}
      ...> ])
      iex> ElixirML.Schema.validate(schema, %{embedding: [1.0, 2.0, 3.0], confidence: 0.8})
      {:ok, %{embedding: [1.0, 2.0, 3.0], confidence: 0.8}}
  """
  @spec create(list(), keyword()) :: Runtime.t()
  def create(fields, opts \\ []) do
    %Runtime{
      fields: fields,
      validations: Keyword.get(opts, :validations, []),
      transforms: Keyword.get(opts, :transforms, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Validate data against a schema.

  ## Examples

      iex> ElixirML.Schema.validate(MySchema, %{field: "value"})
      {:ok, %{field: "value"}}

      iex> ElixirML.Schema.validate(MySchema, %{invalid: "data"})
      {:error, %ElixirML.Schema.ValidationError{}}
  """
  @spec validate(module() | Runtime.t(), map()) ::
          {:ok, map()} | {:error, ElixirML.Schema.ValidationError.t()}
  def validate(schema_module, data) when is_atom(schema_module) do
    schema_module.validate(data)
  end

  def validate(%Runtime{} = schema, data) do
    Runtime.validate(schema, data)
  end

  @doc """
  Extract variables from a schema for optimization.
  """
  @spec extract_variables(module()) :: list()
  def extract_variables(schema_module) when is_atom(schema_module) do
    schema_module.__variables__()
  end

  @doc """
  Generate JSON schema representation.
  """
  @spec to_json_schema(module()) :: map()
  def to_json_schema(schema_module) when is_atom(schema_module) do
    schema_module.to_json_schema()
  end
end
