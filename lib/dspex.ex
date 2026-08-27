defmodule DSPEx do
  @moduledoc """
  Minimal entry point for the supported DSPEx stack.

  The functions here wire together signatures, adapters, clients, and
  teleprompters used in the vertical slice (Predict, Retrieval/RAG,
  BootstrapFewShot, GEPA). Builder helpers remain for compatibility but
  advanced variable-system features are intentionally out of scope.
  """

  alias DSPEx.{Program, Builder}
  # ElixirML integration handled dynamically to avoid circular dependencies

  @doc """
  Creates an enhanced DSPEx program with ElixirML foundation integration.

  This is the primary entry point for creating programs that leverage the
  ElixirML foundation's variable system, schema validation, and process orchestration.

  ## Parameters
  - `signature` - Signature module defining program interface
  - `opts` - Optional configuration parameters

  ## Options
  - `:variables` - Map of variable overrides
  - `:schema_validation` - Enable schema validation (default: false)
  - `:client` - Client configuration
  - `:adapter` - Adapter configuration

  ## Returns
  - `{:ok, program}` - Enhanced program ready for execution
  - `{:error, reason}` - Program creation failed

  ## Examples

      program = DSPEx.program(QASignature)
      |> DSPEx.with_variables(%{temperature: 0.8})
      |> DSPEx.with_schema_validation(true)

  """
  @spec program(module(), keyword()) :: {:ok, Builder.t()} | {:error, term()}
  def program(signature_module, opts \\ []) do
    Builder.new(signature_module, opts)
  end

  @doc """
  Adds variables to a program builder for automatic optimization.

  Variables specified here are preserved on the builder for experimental
  optimizers. The minimal teleprompters in this slice do not automatically
  tune them.

  ## Parameters
  - `builder` - Program builder from DSPEx.program/2
  - `variables` - Map of variable names to values

  ## Returns
  - Updated program builder with variables configured

  ## Examples

      program = DSPEx.program(QASignature)
      |> DSPEx.with_variables(%{
        provider: :openai,
        temperature: 0.7,
        max_tokens: 150
      })

  """
  @spec with_variables(Builder.t(), map()) :: Builder.t()
  def with_variables(%Builder{} = builder, variables) when is_map(variables) do
    Builder.with_variables(builder, variables)
  end

  @doc """
  Enables or disables schema validation for the program.

  When enabled, all inputs and outputs are validated using the ElixirML
  Schema Engine with ML-specific type checking.

  ## Parameters
  - `builder` - Program builder from DSPEx.program/2
  - `enabled` - Boolean to enable/disable validation

  ## Returns
  - Updated program builder with schema validation configured

  ## Examples

      program = DSPEx.program(QASignature)
      |> DSPEx.with_schema_validation(true)

  """
  @spec with_schema_validation(Builder.t(), boolean()) :: Builder.t()
  def with_schema_validation(%Builder{} = builder, enabled) when is_boolean(enabled) do
    Builder.with_schema_validation(builder, enabled)
  end

  @doc """
  Executes a program with the given inputs using the Process Orchestrator.

  This function leverages the ElixirML Process Orchestrator for execution,
  providing fault tolerance, telemetry, and performance optimization.

  ## Parameters
  - `program` - Program or builder to execute
  - `inputs` - Map of input values
  - `opts` - Execution options

  ## Options
  - `:validate_inputs` - Validate inputs before execution (default: true)
  - `:validate_outputs` - Validate outputs after execution (default: true)
  - `:timeout` - Execution timeout in milliseconds

  ## Returns
  - `{:ok, outputs}` - Execution successful with validated outputs
  - `{:error, reason}` - Execution failed

  ## Examples

      {:ok, result} = DSPEx.forward(program, %{
        question: "What is machine learning?",
        context: embedding_vector
      })

  """
  @spec forward(Builder.t() | struct(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def forward(program_or_builder, inputs, opts \\ [])

  def forward(%Builder{} = builder, inputs, opts) do
    case Builder.build(builder) do
      {:ok, program} -> forward(program, inputs, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  def forward(program, inputs, opts) when is_struct(program) do
    validate_inputs = Keyword.get(opts, :validate_inputs, true)
    validate_outputs = Keyword.get(opts, :validate_outputs, true)

    with {:ok, validated_inputs} <- maybe_validate_inputs(program, inputs, validate_inputs),
         {:ok, outputs} <- Program.forward(program, validated_inputs, opts),
         {:ok, validated_outputs} <- maybe_validate_outputs(program, outputs, validate_outputs) do
      {:ok, validated_outputs}
    end
  end

  @doc """
  Run a teleprompter (BootstrapFewShot or GEPA) against a program.

  Requires a teacher program and a metric function; by default it uses
  `DSPEx.Teleprompter.BootstrapFewShot`.
  """
  @spec optimize(Builder.t() | struct(), [DSPEx.Example.t()], keyword()) ::
          {:ok, struct()} | {:error, term()}
  def optimize(program_or_builder, training_data, opts \\ []) do
    teleprompter = Keyword.get(opts, :teleprompter, DSPEx.Teleprompter.BootstrapFewShot)
    teacher = Keyword.get(opts, :teacher)
    metric_fn = Keyword.get(opts, :metric)

    with {:ok, program} <- ensure_program(program_or_builder),
         {:ok, teacher} <- ensure_teacher(teacher),
         {:ok, metric_fn} <- ensure_metric(metric_fn),
         :ok <- DSPEx.Teleprompter.validate_student(program),
         :ok <- DSPEx.Teleprompter.validate_teacher(teacher),
         :ok <- DSPEx.Teleprompter.validate_trainset(training_data),
         true <- DSPEx.Teleprompter.implements_behavior?(teleprompter) || {:error, :invalid_teleprompter} do
      teleprompter.compile(program, teacher, training_data, metric_fn, Keyword.drop(opts, [:teleprompter, :teacher, :metric]))
    end
  end

  @doc """
  Returns a greeting atom for basic library verification.

  This function is primarily used for testing the library installation
  and basic functionality.

  ## Returns

  The atom `:world`

  ## Examples

      iex> DSPEx.hello()
      :world

  """
  @spec hello() :: :world
  def hello do
    :world
  end

  # Private helper functions

  @spec ensure_program(Builder.t() | struct()) :: {:ok, struct()} | {:error, term()}
  defp ensure_program(%Builder{} = builder) do
    Builder.build(builder)
  end

  defp ensure_program(program) when is_struct(program) do
    {:ok, program}
  end

  defp ensure_teacher(nil), do: {:error, :teacher_required}
  defp ensure_teacher(%_{} = teacher), do: {:ok, teacher}
  defp ensure_teacher(_), do: {:error, :invalid_teacher}

  defp ensure_metric(nil), do: {:error, :metric_required}

  defp ensure_metric(metric_fn) when is_function(metric_fn, 2) do
    {:ok, metric_fn}
  end

  defp ensure_metric(_), do: {:error, :invalid_metric}

  @spec maybe_validate_inputs(struct(), map(), boolean()) :: {:ok, map()} | {:error, term()}
  defp maybe_validate_inputs(program, inputs, true) do
    if DSPEx.Program.schema_validation_enabled?(program) do
      program.signature.validate_inputs_with_schema(inputs)
    else
      program.signature.validate_inputs(inputs)
      {:ok, inputs}
    end
  end

  defp maybe_validate_inputs(_program, inputs, false) do
    {:ok, inputs}
  end

  @spec maybe_validate_outputs(struct(), map(), boolean()) :: {:ok, map()} | {:error, term()}
  defp maybe_validate_outputs(program, outputs, true) do
    if DSPEx.Program.schema_validation_enabled?(program) do
      program.signature.validate_outputs_with_schema(outputs)
    else
      program.signature.validate_outputs(outputs)
      {:ok, outputs}
    end
  end

  defp maybe_validate_outputs(_program, outputs, false) do
    {:ok, outputs}
  end
end
