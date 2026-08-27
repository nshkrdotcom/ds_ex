defmodule DSPEx.Program do
  @moduledoc """
  Minimal behavior definition and helpers for DSPEx programs.
  """

  @type t :: struct()
  @type program :: struct()
  @type inputs :: map()
  @type outputs :: map()
  @type options :: keyword()

  @callback forward(program(), inputs()) :: {:ok, outputs()} | {:error, term()}
  @callback forward(program(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}

  @optional_callbacks forward: 3

  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour DSPEx.Program

      @impl DSPEx.Program
      def forward(_program, _inputs, _opts \\ []) do
        {:error, {:not_implemented, "#{__MODULE__} must implement forward/2 or forward/3"}}
      end

      defoverridable forward: 3
    end
  end

  @spec forward(program(), inputs()) :: {:ok, outputs()} | {:error, term()}
  def forward(program, inputs), do: forward(program, inputs, [])

  @spec forward(program(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}
  def forward(program, inputs, opts) when is_map(inputs) do
    do_forward(program, inputs, opts)
  end

  def forward(_, _inputs, _opts), do: {:error, {:invalid_inputs, "inputs must be a map"}}

  defp do_forward(program, inputs, opts) when is_struct(program) do
    cond do
      function_exported?(program.__struct__, :forward, 3) ->
        program.__struct__.forward(program, inputs, opts)

      function_exported?(program.__struct__, :forward, 2) ->
        program.__struct__.forward(program, inputs)

      true ->
        {:error, :forward_not_implemented}
    end
  rescue
    error -> {:error, {:program_error, error}}
  end

  @spec program_name(program() | any()) :: atom()
  def program_name(program) when is_struct(program) do
    program.__struct__
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  rescue
    _ -> :unknown
  end

  def program_name(_), do: :unknown

  @spec implements_program?(module()) :: boolean()
  def implements_program?(module) when is_atom(module) do
    behaviours = module.module_info(:attributes) |> Keyword.get(:behaviour, [])
    __MODULE__ in behaviours
  rescue
    _ -> false
  end

  def implements_program?(_), do: false

  @spec new(module(), map()) :: {:ok, program()} | {:error, term()}
  def new(module, fields) when is_atom(module) and is_map(fields) do
    if implements_program?(module) do
      {:ok, struct(module, fields)}
    else
      {:error, {:invalid_program_module, module}}
    end
  rescue
    error -> {:error, {:struct_creation_failed, error}}
  end

  def new(_, _), do: {:error, :invalid_arguments}

  @spec program_type(t()) :: :predict | :optimized | :custom
  def program_type(program) when is_struct(program) do
    case program.__struct__ |> Module.split() |> List.last() do
      "Predict" -> :predict
      "OptimizedProgram" -> :optimized
      _ -> :custom
    end
  rescue
    _ -> :custom
  end

  def program_type(_), do: :custom

  @doc """
  Placeholder to indicate schema validation is not enabled by default.
  """
  @spec schema_validation_enabled?(t()) :: boolean()
  def schema_validation_enabled?(_), do: false

  @doc """
  No-op helper to keep existing builder code paths working.
  """
  @spec enable_schema_validation(t()) :: t()
  def enable_schema_validation(program), do: program
end
