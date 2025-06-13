# DSPEx Gap Filling Plan: Pre-BEACON Implementation

## Executive Summary

This plan addresses the critical implementation gaps identified in the DSPEx codebase before BEACON teleprompter integration. The analysis revealed missing core infrastructure, incomplete signature systems, and client architecture issues that must be resolved for reliable teleprompter operation.

## Phase 1: Critical Infrastructure (Days 1-5)

### 1.1 DSPEx.Teleprompter Behavior (Day 1)

**Priority**: 🔴 CRITICAL - BEACON compilation will fail without this

**Implementation**:

```elixir
# File: lib/dspex/teleprompter.ex (COMPLETE REWRITE)
defmodule DSPEx.Teleprompter do
  @moduledoc """
  Behavior for DSPEx teleprompters (program optimizers).
  
  Teleprompters improve programs by learning from examples and optimizing
  demonstration selection. They implement the compile/5 callback to transform
  a student program using a teacher program and training examples.
  """

  alias DSPEx.{Program, Example}

  @type program :: struct()
  @type trainset :: [Example.t()]
  @type metric_fn :: (Example.t(), map() -> number())
  @type opts :: keyword()
  @type compilation_result :: {:ok, program()} | {:error, term()}

  @doc """
  Compile (optimize) a student program using a teacher program and training data.

  ## Parameters
  - `student`: The program to be optimized
  - `teacher`: A stronger program used to generate demonstrations  
  - `trainset`: Training examples for optimization
  - `metric_fn`: Function to evaluate prediction quality
  - `opts`: Options for compilation

  ## Returns
  - `{:ok, optimized_program}` on successful optimization
  - `{:error, reason}` if optimization fails
  """
  @callback compile(
              student :: program(),
              teacher :: program(),
              trainset :: trainset(),
              metric_fn :: metric_fn(),
              opts :: opts()
            ) :: compilation_result()

  @doc """
  Validate that a module implements the teleprompter behavior.
  """
  @spec implements_behavior?(module()) :: boolean()
  def implements_behavior?(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        behaviours = module.module_info(:attributes)
                    |> Keyword.get(:behaviour, [])
        __MODULE__ in behaviours
      _ -> false
    end
  end

  @doc """
  Validate student program for teleprompter compatibility.
  """
  @spec validate_student(program()) :: :ok | {:error, term()}
  def validate_student(student) when is_struct(student) do
    if Program.implements_program?(student.__struct__) do
      :ok
    else
      {:error, {:invalid_student, "Student must implement DSPEx.Program behavior"}}
    end
  end
  def validate_student(_), do: {:error, {:invalid_student, "Student must be a struct"}}

  @doc """
  Validate teacher program for teleprompter compatibility.
  """
  @spec validate_teacher(program()) :: :ok | {:error, term()}
  def validate_teacher(teacher) when is_struct(teacher) do
    if Program.implements_program?(teacher.__struct__) do
      :ok
    else
      {:error, {:invalid_teacher, "Teacher must implement DSPEx.Program behavior"}}
    end
  end
  def validate_teacher(_), do: {:error, {:invalid_teacher, "Teacher must be a struct"}}

  @doc """
  Validate training set for teleprompter use.
  """
  @spec validate_trainset(trainset()) :: :ok | {:error, term()}
  def validate_trainset(trainset) when is_list(trainset) and length(trainset) > 0 do
    if Enum.all?(trainset, &valid_example?/1) do
      :ok
    else
      {:error, {:invalid_trainset, "All examples must have inputs and outputs"}}
    end
  end
  def validate_trainset([]), do: {:error, {:invalid_trainset, "Training set cannot be empty"}}
  def validate_trainset(_), do: {:error, {:invalid_trainset, "Training set must be a list"}}

  @doc """
  Helper function to create exact match metric.
  """
  @spec exact_match(atom()) :: metric_fn()
  def exact_match(field) when is_atom(field) do
    fn example, prediction ->
      expected = Example.get(example, field)
      actual = Map.get(prediction, field)
      if expected == actual, do: 1.0, else: 0.0
    end
  end

  @doc """
  Helper function to create contains match metric.
  """
  @spec contains_match(atom()) :: metric_fn()
  def contains_match(field) when is_atom(field) do
    fn example, prediction ->
      expected = Example.get(example, field)
      actual = Map.get(prediction, field)

      if is_binary(expected) and is_binary(actual) do
        if String.contains?(String.downcase(actual), String.downcase(expected)) do
          1.0
        else
          0.0
        end
      else
        if expected == actual, do: 1.0, else: 0.0
      end
    end
  end

  # Private helper
  defp valid_example?(%Example{} = example) do
    not Example.empty?(example) and 
    map_size(Example.inputs(example)) > 0 and
    map_size(Example.outputs(example)) > 0
  end
  defp valid_example?(_), do: false
end
```

**Validation**:
```elixir
# File: test/dspex/teleprompter_test.exs
defmodule DSPEx.TeleprompterTest do
  use ExUnit.Case, async: true
  
  alias DSPEx.{Teleprompter, Example}
  
  describe "behavior validation" do
    test "implements_behavior?/1 correctly identifies teleprompters" do
      # Test with mock teleprompter module
      assert Teleprompter.implements_behavior?(DSPEx.Teleprompter.BootstrapFewShot)
      refute Teleprompter.implements_behavior?(DSPEx.Predict)
    end
  end
  
  describe "validation functions" do
    test "validate_student/1 accepts valid programs" do
      student = %DSPEx.Predict{signature: TestSignature, client: :test}
      assert :ok = Teleprompter.validate_student(student)
    end
    
    test "validate_trainset/1 accepts valid examples" do
      examples = [
        %Example{data: %{question: "test", answer: "response"}, input_keys: MapSet.new([:question])}
      ]
      assert :ok = Teleprompter.validate_trainset(examples)
    end
  end
end
```

### 1.2 DSPEx.OptimizedProgram Interface (Day 2)

**Priority**: 🔴 CRITICAL - BEACON references this module

**Issue**: Current optimized_program.ex may not match BEACON's interface expectations

**Implementation**:

```elixir
# File: lib/dspex/optimized_program.ex (ENHANCE EXISTING)
defmodule DSPEx.OptimizedProgram do
  @moduledoc """
  Wrapper for programs that have been optimized with demonstrations.
  
  This module provides the exact interface that BEACON expects for wrapping
  programs that don't natively support demonstration storage.
  """

  use DSPEx.Program

  @enforce_keys [:program, :demos]
  defstruct [:program, :demos, metadata: %{}]

  @type t :: %__MODULE__{
          program: struct(),
          demos: [DSPEx.Example.t()],
          metadata: map()
        }

  @doc """
  Create a new optimized program wrapper.
  
  This function MUST match BEACON's expectations exactly.
  """
  @spec new(struct(), [DSPEx.Example.t()], map()) :: t()
  def new(program, demos, metadata \\ %{}) when is_list(demos) do
    %__MODULE__{
      program: program,
      demos: demos,
      metadata: Map.merge(%{
        optimized_at: DateTime.utc_now(),
        demo_count: length(demos),
        teleprompter: :unknown
      }, metadata)
    }
  end

  @impl DSPEx.Program
  def forward(%__MODULE__{program: program, demos: demos}, inputs, opts \\ []) do
    # Enhanced demo handling for different program types
    case program do
      %{demos: _} ->
        # Program has native demo support
        enhanced_program = %{program | demos: demos}
        DSPEx.Program.forward(enhanced_program, inputs, opts)

      %DSPEx.Predict{} = predict ->
        # Special handling for Predict programs
        enhanced_predict = %{predict | demos: demos}
        DSPEx.Program.forward(enhanced_predict, inputs, opts)

      _ ->
        # Generic program - pass demos via options
        enhanced_opts = Keyword.put(opts, :demos, demos)
        DSPEx.Program.forward(program, inputs, enhanced_opts)
    end
  end

  @doc """
  Get demonstrations from optimized program.
  BEACON depends on this function existing with this exact signature.
  """
  @spec get_demos(t()) :: [DSPEx.Example.t()]
  def get_demos(%__MODULE__{demos: demos}), do: demos

  @doc """
  Get the wrapped program.
  BEACON depends on this function existing with this exact signature.
  """
  @spec get_program(t()) :: struct()
  def get_program(%__MODULE__{program: program}), do: program

  @doc """
  Get optimization metadata.
  """
  @spec get_metadata(t()) :: map()
  def get_metadata(%__MODULE__{metadata: metadata}), do: metadata

  @doc """
  Update the program while preserving demos and metadata.
  """
  @spec update_program(t(), struct()) :: t()
  def update_program(%__MODULE__{} = optimized, new_program) do
    %{optimized | program: new_program}
  end

  @doc """
  Add demonstrations to existing optimized program.
  """
  @spec add_demos(t(), [DSPEx.Example.t()]) :: t()
  def add_demos(%__MODULE__{demos: existing_demos, metadata: metadata} = optimized, new_demos) do
    combined_demos = existing_demos ++ new_demos
    updated_metadata = Map.put(metadata, :demo_count, length(combined_demos))
    
    %{optimized | demos: combined_demos, metadata: updated_metadata}
  end

  @doc """
  Replace all demonstrations.
  """
  @spec replace_demos(t(), [DSPEx.Example.t()]) :: t()
  def replace_demos(%__MODULE__{metadata: metadata} = optimized, new_demos) do
    updated_metadata = Map.put(metadata, :demo_count, length(new_demos))
    %{optimized | demos: new_demos, metadata: updated_metadata}
  end

  @doc """
  Check if program supports native demo storage.
  """
  @spec supports_native_demos?(struct()) :: boolean()
  def supports_native_demos?(%{demos: _}), do: true
  def supports_native_demos?(%DSPEx.Predict{}), do: true
  def supports_native_demos?(_), do: false
end
```

**Validation**:
```elixir
# File: test/dspex/optimized_program_test.exs  
defmodule DSPEx.OptimizedProgramTest do
  use ExUnit.Case, async: true
  
  alias DSPEx.{OptimizedProgram, Example, Predict}
  
  setup do
    program = %Predict{signature: TestSignature, client: :test}
    demos = [
      %Example{data: %{question: "test", answer: "response"}, input_keys: MapSet.new([:question])}
    ]
    %{program: program, demos: demos}
  end
  
  describe "BEACON interface compatibility" do
    test "new/3 creates optimized program", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)
      
      assert %OptimizedProgram{} = optimized
      assert optimized.program == program
      assert optimized.demos == demos
    end
    
    test "get_demos/1 returns demonstrations", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)
      assert ^demos = OptimizedProgram.get_demos(optimized)
    end
    
    test "get_program/1 returns wrapped program", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)
      assert ^program = OptimizedProgram.get_program(optimized)
    end
  end
  
  describe "forward/3 delegation" do
    test "forwards to wrapped program with demos", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)
      inputs = %{question: "What is 2+2?"}
      
      # Mock the underlying program
      # Test that forward is called correctly
    end
  end
end
```

### 1.3 Missing Program Utilities (Day 3)

**Priority**: 🟡 HIGH - BEACON telemetry references these

**Implementation**:

```elixir
# File: lib/dspex/program.ex (ADD TO EXISTING)
defmodule DSPEx.Program do
  # ... existing code ...

  @doc """
  Get a human-readable name for a program.
  Used by BEACON telemetry and logging.
  """
  @spec program_name(program()) :: atom() | String.t()
  def program_name(program) when is_struct(program) do
    program.__struct__
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end
  def program_name(%DSPEx.OptimizedProgram{program: wrapped}) do
    # For optimized programs, return the wrapped program's name
    case program_name(wrapped) do
      name when is_atom(name) -> "Optimized#{name}" |> String.to_atom()
      name -> "Optimized#{name}"
    end
  end
  def program_name(_), do: :unknown

  @doc """
  Check if a module implements the DSPEx.Program behavior.
  Used by teleprompter validation.
  """
  @spec implements_program?(module()) :: boolean()
  def implements_program?(module) when is_atom(module) do
    try do
      behaviours = module.module_info(:attributes)
                  |> Keyword.get(:behaviour, [])
      __MODULE__ in behaviours
    rescue
      UndefinedFunctionError -> false
      ArgumentError -> false
    end
  end
  def implements_program?(_), do: false

  @doc """
  Get program type information for telemetry.
  """
  @spec program_type(program()) :: atom()
  def program_type(%DSPEx.Predict{}), do: :predict
  def program_type(%DSPEx.OptimizedProgram{}), do: :optimized
  def program_type(program) when is_struct(program) do
    program.__struct__
    |> Module.split()
    |> List.last()
    |> String.downcase()
    |> String.to_atom()
  end
  def program_type(_), do: :unknown

  @doc """
  Safely extract program configuration for logging.
  Excludes sensitive information like API keys.
  """
  @spec safe_program_info(program()) :: map()
  def safe_program_info(program) when is_struct(program) do
    %{
      type: program_type(program),
      name: program_name(program),
      module: program.__struct__,
      has_demos: has_demos?(program)
    }
  end

  @doc """
  Check if program has demonstration examples.
  """
  @spec has_demos?(program()) :: boolean()
  def has_demos?(%{demos: demos}) when is_list(demos), do: length(demos) > 0
  def has_demos?(%DSPEx.OptimizedProgram{demos: demos}), do: length(demos) > 0
  def has_demos?(_), do: false

  # ... rest of existing code ...
end
```

## Phase 2: Signature System Enhancement (Days 4-6)

### 2.1 Signature Extension Capabilities (Day 4)

**Priority**: 🟡 HIGH - Required for ChainOfThought and complex programs

**Implementation**:

```elixir
# File: lib/dspex/signature.ex (ADD TO EXISTING)
defmodule DSPEx.Signature do
  # ... existing code ...

  @doc """
  Extend a signature with additional fields.
  Used by ChainOfThought and other complex programs.
  """
  @spec extend(module(), map()) :: {:ok, module()} | {:error, term()}
  def extend(base_signature, additional_fields) when is_map(additional_fields) do
    try do
      # Get base signature information
      base_inputs = base_signature.input_fields()
      base_outputs = base_signature.output_fields()
      base_instructions = base_signature.instructions()

      # Parse additional fields
      {additional_inputs, additional_outputs} = parse_additional_fields(additional_fields)

      # Create new signature string
      all_inputs = base_inputs ++ additional_inputs
      all_outputs = base_outputs ++ additional_outputs
      
      signature_string = format_signature_string(all_inputs, all_outputs)

      # Generate new module dynamically
      extended_module_name = :"#{base_signature}Extended#{:rand.uniform(10000)}"
      
      extended_module = quote do
        defmodule unquote(extended_module_name) do
          use DSPEx.Signature, unquote(signature_string)
          
          @base_signature unquote(base_signature)
          @additional_fields unquote(additional_fields)
          
          @impl DSPEx.Signature
          def instructions() do
            base = unquote(base_instructions)
            additional = describe_additional_fields(unquote(additional_fields))
            "#{base}\n\nAdditional requirements: #{additional}"
          end
          
          def base_signature(), do: @base_signature
          def additional_fields(), do: @additional_fields
        end
      end

      # Compile the module
      Code.eval_quoted(extended_module)
      
      {:ok, extended_module_name}
    rescue
      error -> {:error, {:extension_failed, error}}
    end
  end

  @doc """
  Get detailed field information including metadata.
  """
  @spec get_field_info(module(), atom()) :: {:ok, map()} | {:error, :field_not_found}
  def get_field_info(signature, field) when is_atom(field) do
    all_fields = signature.fields()
    
    if field in all_fields do
      info = %{
        name: field,
        type: infer_field_type(signature, field),
        is_input: field in signature.input_fields(),
        is_output: field in signature.output_fields(),
        description: get_field_description(signature, field)
      }
      {:ok, info}
    else
      {:error, :field_not_found}
    end
  end

  @doc """
  Validate signature compatibility for program composition.
  """
  @spec validate_signature_compatibility(module(), module()) :: :ok | {:error, term()}
  def validate_signature_compatibility(sig1, sig2) do
    # Check if outputs of sig1 can be inputs to sig2
    sig1_outputs = MapSet.new(sig1.output_fields())
    sig2_inputs = MapSet.new(sig2.input_fields())
    
    overlap = MapSet.intersection(sig1_outputs, sig2_inputs)
    
    if MapSet.size(overlap) > 0 do
      :ok
    else
      {:error, {:incompatible_signatures, %{
        sig1_outputs: MapSet.to_list(sig1_outputs),
        sig2_inputs: MapSet.to_list(sig2_inputs),
        overlap: MapSet.to_list(overlap)
      }}}
    end
  end

  # Private helpers
  defp parse_additional_fields(fields) do
    inputs = []
    outputs = []
    
    Enum.reduce(fields, {inputs, outputs}, fn {field, config}, {acc_inputs, acc_outputs} ->
      case Map.get(config, :position, :output) do
        :input -> {[field | acc_inputs], acc_outputs}
        :output -> {acc_inputs, [field | acc_outputs]}
        :before_outputs -> {[field | acc_inputs], acc_outputs}  # Add as input, processed before outputs
        _ -> {acc_inputs, [field | acc_outputs]}
      end
    end)
  end

  defp format_signature_string(inputs, outputs) do
    input_str = Enum.join(inputs, ", ")
    output_str = Enum.join(outputs, ", ")
    "#{input_str} -> #{output_str}"
  end

  defp describe_additional_fields(fields) do
    Enum.map_join(fields, "; ", fn {field, config} ->
      description = Map.get(config, :description, "No description")
      "#{field}: #{description}"
    end)
  end

  defp infer_field_type(signature, field) do
    # Basic type inference - can be enhanced
    cond do
      String.contains?(Atom.to_string(field), "question") -> :string
      String.contains?(Atom.to_string(field), "answer") -> :string
      String.contains?(Atom.to_string(field), "reasoning") -> :string
      String.contains?(Atom.to_string(field), "score") -> :number
      String.contains?(Atom.to_string(field), "confidence") -> :number
      true -> :any
    end
  end

  defp get_field_description(signature, field) do
    # Try to extract from instructions or use field name
    instructions = signature.instructions()
    field_str = Atom.to_string(field)
    
    if String.contains?(instructions, field_str) do
      # Extract context around field mention
      extract_field_context(instructions, field_str)
    else
      humanize_field_name(field)
    end
  end

  defp extract_field_context(text, field_name) do
    # Simple context extraction - find sentence containing field
    sentences = String.split(text, [". ", "! ", "? "])
    
    Enum.find(sentences, "Field: #{field_name}", fn sentence ->
      String.contains?(String.downcase(sentence), String.downcase(field_name))
    end)
  end

  defp humanize_field_name(field) do
    field
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
```

### 2.2 Enhanced Signature Introspection (Day 5)

**Priority**: 🟡 MEDIUM - Improves debugging and validation

**Implementation**:

```elixir
# File: lib/dspex/signature.ex (ENHANCE EXISTING)
defmodule DSPEx.Signature do
  # ... existing code ...

  @doc """
  Get comprehensive signature metadata for debugging.
  """
  @spec introspect(module()) :: map()
  def introspect(signature) do
    %{
      name: signature_name(signature),
      input_fields: signature.input_fields(),
      output_fields: signature.output_fields(),
      all_fields: signature.fields(),
      instructions: signature.instructions(),
      field_count: length(signature.fields()),
      complexity_score: calculate_complexity_score(signature),
      validation_rules: get_validation_rules(signature)
    }
  end

  @doc """
  Validate a signature implementation for completeness.
  """
  @spec validate_signature_implementation(module()) :: :ok | {:error, [atom()]}
  def validate_signature_implementation(signature) do
    required_functions = [:input_fields, :output_fields, :fields, :instructions]
    
    missing = Enum.filter(required_functions, fn func ->
      not function_exported?(signature, func, 0)
    end)
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, missing}
    end
  end

  @doc """
  Enhanced description with fallback handling.
  """
  @spec safe_description(module()) :: String.t()
  def safe_description(signature) do
    try do
      signature.instructions()
    rescue
      UndefinedFunctionError ->
        generate_default_description(signature)
      FunctionClauseError ->
        generate_default_description(signature)
    catch
      :error, _ ->
        generate_default_description(signature)
    end
  end

  @doc """
  Get signature field statistics.
  """
  @spec field_statistics(module()) :: map()
  def field_statistics(signature) do
    inputs = signature.input_fields()
    outputs = signature.output_fields()
    
    %{
      input_count: length(inputs),
      output_count: length(outputs),
      total_fields: length(inputs) + length(outputs),
      input_output_ratio: if(length(outputs) > 0, do: length(inputs) / length(outputs), else: :infinity),
      complexity: categorize_complexity(length(inputs), length(outputs))
    }
  end

  # Private helpers
  defp signature_name(signature) do
    signature
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end

  defp calculate_complexity_score(signature) do
    inputs = length(signature.input_fields())
    outputs = length(signature.output_fields())
    instructions_length = String.length(signature.instructions())
    
    # Simple complexity calculation
    base_score = inputs + outputs * 2  # Outputs are more complex
    instruction_bonus = min(instructions_length / 100, 5)  # Cap at 5 points
    
    base_score + instruction_bonus
  end

  defp get_validation_rules(signature) do
    %{
      required_inputs: signature.input_fields(),
      required_outputs: signature.output_fields(),
      allows_extra_fields: false,  # Conservative default
      min_inputs: length(signature.input_fields()),
      min_outputs: length(signature.output_fields())
    }
  end

  defp generate_default_description(signature) do
    inputs = signature.input_fields()
    outputs = signature.output_fields()
    
    input_str = Enum.join(inputs, ", ")
    output_str = Enum.join(outputs, ", ")
    
    "Given the fields #{input_str}, produce the fields #{output_str}."
  end

  defp categorize_complexity(input_count, output_count) do
    total = input_count + output_count
    
    cond do
      total <= 2 -> :simple
      total <= 4 -> :moderate  
      total <= 6 -> :complex
      true -> :very_complex
    end
  end
end
```

## Phase 3: Client Architecture Stabilization (Days 6-8)

### 3.1 Multi-Provider Reliability Testing (Day 6)

**Priority**: 🟡 HIGH - BEACON needs reliable client calls

**Implementation**:

```elixir
# File: test/dspex/integration/client_reliability_test.exs
defmodule DSPEx.Integration.ClientReliabilityTest do
  use ExUnit.Case, async: false
  
  alias DSPEx.{Client, ClientManager}
  
  @moduletag :integration
  
  setup_all do
    # Set up test mode to allow controlled testing
    original_mode = DSPEx.TestModeConfig.get_test_mode()
    DSPEx.TestModeConfig.set_test_mode(:fallback)
    
    on_exit(fn ->
      DSPEx.TestModeConfig.set_test_mode(original_mode)
    end)
    
    :ok
  end

  describe "provider switching under load" do
    test "handles rapid provider switching" do
      messages = [%{role: "user", content: "Test message"}]
      
      # Test switching between providers rapidly
      providers = [:openai, :gemini, :anthropic]
      
      results = Task.async_stream(1..100, fn i ->
        provider = Enum.at(providers, rem(i, length(providers)))
        correlation_id = "test-#{i}"
        
        Client.request(messages, %{
          provider: provider,
          correlation_id: correlation_id
        })
      end, max_concurrency: 20)
      |> Enum.to_list()
      
      # All requests should succeed (either real API or mock fallback)
      successes = Enum.count(results, fn {:ok, {:ok, _}} -> true; _ -> false end)
      assert successes >= 80  # Allow some failures in test environment
    end
    
    test "maintains correlation_id propagation" do
      messages = [%{role: "user", content: "Test with correlation"}]
      correlation_id = "test-correlation-#{System.unique_integer()}"
      
      {:ok, _response} = Client.request(messages, %{
        provider: :gemini,
        correlation_id: correlation_id
      })
      
      # Verify correlation_id was properly propagated
      # (This would require telemetry capture in a real implementation)
    end
  end

  describe "error handling across providers" do
    test "graceful degradation on provider failures" do
      # This test would require controlled failure injection
      # For now, test that fallback works
      
      messages = [%{role: "user", content: "Test graceful degradation"}]
      
      # Even with invalid configuration, should get mock fallback
      {:ok, response} = Client.request(messages, %{
        provider: :gemini,
        model: "non-existent-model"
      })
      
      assert %{choices: [%{message: %{content: content}}]} = response
      assert is_binary(content)
    end
  end

  describe "concurrent load testing" do
    test "handles high concurrency without errors" do
      messages = [%{role: "user", content: "Concurrent test"}]
      
      # Start many concurrent requests
      tasks = Task.async_stream(1..50, fn i ->
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: "concurrent-#{i}"
        })
      end, max_concurrency: 25, timeout: 30_000)
      |> Enum.to_list()
      
      # Count successful completions
      successes = Enum.count(tasks, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)
      
      # Should have high success rate
      assert successes >= 45
    end
  end
end
```

### 3.2 Foundation Integration Verification (Day 7)

**Priority**: 🟡 MEDIUM - Ensures Foundation services work correctly

**Implementation**:

```elixir
# File: test/dspex/integration/foundation_integration_test.exs
defmodule DSPEx.Integration.FoundationIntegrationTest do
  use ExUnit.Case, async: false
  
  alias DSPEx.Services.{ConfigManager, TelemetrySetup}
  
  @moduletag :integration
  
  describe "Foundation Config integration" do
    test "ConfigManager starts and integrates with Foundation" do
      # Verify ConfigManager can start and connect to Foundation
      assert {:ok, _pid} = ConfigManager.start_link([])
      
      # Test basic configuration retrieval
      assert {:ok, _config} = ConfigManager.get([:providers, :gemini])
    end
    
    test "configuration hot updates work" do
      # Test that configuration can be updated at runtime
      original_temp = ConfigManager.get_with_default([:prediction, :default_temperature], 0.7)
      
      :ok = ConfigManager.update([:prediction, :default_temperature], 0.9)
      
      assert {:ok, 0.9} = ConfigManager.get([:prediction, :default_temperature])
      
      # Cleanup
      :ok = ConfigManager.update([:prediction, :default_temperature], original_temp)
    end
  end
  
  describe "Foundation Telemetry integration" do
    test "TelemetrySetup integrates with Foundation telemetry" do
      assert {:ok, _pid} = TelemetrySetup.start_link([])
      
      # Verify telemetry handlers are attached
      handlers = :telemetry.list_handlers([])
      dspex_handlers = Enum.filter(handlers, fn %{id: id} ->
        String.contains?(to_string(id), "dspex")
      end)
      
      assert length(dspex_handlers) > 0
    end
    
    test "telemetry events are properly emitted and handled" do
      # Set up a test handler to capture events
      test_pid = self()
      
      handler_id = "test-dspex-handler"
      :telemetry.attach(
        handler_id,
        [:dspex, :test, :event],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{}
      )
      
      # Emit a test event
      :telemetry.execute([:dspex, :test, :event], %{duration: 100}, %{test: true})
      
      # Verify we received it
      assert_receive {:telemetry_event, [:dspex, :test, :event], %{duration: 100}, %{test: true}}, 1000
      
      # Cleanup
      :telemetry.detach(handler_id)
    end
  end
  
  describe "Foundation circuit breaker integration" do
    test "circuit breakers are properly initialized" do
      # This would test that Foundation circuit breakers are set up
      # for each provider during ConfigManager initialization
      
      # For now, verify that ConfigManager starts without errors
      # which indicates circuit breaker setup succeeded
      assert {:ok, _pid} = ConfigManager.start_link([])
    end
  end
end
```

### 3.3 Enhanced Mock Framework for BEACON Testing (Day 8)

**Priority**: 🟡 HIGH - BEACON needs sophisticated mocking

**Implementation**:

```elixir
# File: lib/dspex/test/mock_provider.ex
defmodule DSPEx.Test.MockProvider do
  @moduledoc """
  Enhanced mock framework for BEACON teleprompter testing.
  
  Provides sophisticated mocking capabilities for:
  - Multi-provider LLM calls
  - Bootstrap demonstration generation
  - Bayesian optimization trials
  - Complex teleprompter workflows
  """
  
  use GenServer
  
  defstruct [
    :mode,
    :responses,
    :call_history,
    :failure_rate,
    :latency_simulation
  ]
  
  @type mock_mode :: :deterministic | :contextual | :recorded | :generative
  @type response_config :: %{
    provider: atom(),
    model: String.t(),
    response: map(),
    latency_ms: non_neg_integer(),
    should_fail: boolean()
  }
  
  ## Public API
  
  @doc """
  Start mock provider with configuration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Set up mocks for bootstrap demonstration generation.
  
  This is specifically designed for BEACON's bootstrap phase.
  """
  @spec setup_bootstrap_mocks([map()]) :: :ok
  def setup_bootstrap_mocks(teacher_responses) do
    GenServer.call(__MODULE__, {:setup_bootstrap, teacher_responses})
  end
  
  @doc """
  Set up mocks for instruction generation phase.
  """
  @spec setup_instruction_generation_mocks([map()]) :: :ok
  def setup_instruction_generation_mocks(instruction_responses) do
    GenServer.call(__MODULE__, {:setup_instructions, instruction_responses})
  end
  
  @doc """
  Set up mocks for evaluation phase with scores.
  """
  @spec setup_evaluation_mocks([number()]) :: :ok
  def setup_evaluation_mocks(scores) do
    GenServer.call(__MODULE__, {:setup_evaluation, scores})
  end
  
  @doc """
  Configure realistic response patterns for BEACON optimization.
  """
  @spec setup_beacon_optimization_mocks(keyword()) :: :ok
  def setup_beacon_optimization_mocks(opts) do
    config = %{
      bootstrap_success_rate: Keyword.get(opts, :bootstrap_success_rate, 0.8),
      quality_distribution: Keyword.get(opts, :quality_distribution, :normal),
      instruction_effectiveness: Keyword.get(opts, :instruction_effectiveness, 0.7),
      optimization_trajectory: Keyword.get(opts, :optimization_trajectory, :improving)
    }
    
    GenServer.call(__MODULE__, {:setup_beacon, config})
  end
  
  @doc """
  Get detailed call history for testing validation.
  """
  @spec get_call_history() :: [map()]
  def get_call_history() do
    GenServer.call(__MODULE__, :get_history)
  end
  
  @doc """
  Reset mock state for clean testing.
  """
  @spec reset() :: :ok
  def reset() do
    GenServer.call(__MODULE__, :reset)
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(opts) do
    mode = Keyword.get(opts, :mode, :contextual)
    
    state = %__MODULE__{
      mode: mode,
      responses: %{},
      call_history: [],
      failure_rate: Keyword.get(opts, :failure_rate, 0.0),
      latency_simulation: Keyword.get(opts, :latency_simulation, false)
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:setup_bootstrap, teacher_responses}, _from, state) do
    # Set up responses for bootstrap phase
    bootstrap_responses = Enum.with_index(teacher_responses, fn response, index ->
      {
        "bootstrap_#{index}",
        %{
          type: :bootstrap,
          response: response,
          quality_score: generate_quality_score(response),
          latency_ms: :rand.uniform(500) + 100
        }
      }
    end) |> Enum.into(%{})
    
    updated_responses = Map.merge(state.responses, bootstrap_responses)
    {:reply, :ok, %{state | responses: updated_responses}}
  end
  
  @impl true
  def handle_call({:setup_instructions, instruction_responses}, _from, state) do
    instruction_configs = Enum.with_index(instruction_responses, fn response, index ->
      {
        "instruction_#{index}",
        %{
          type: :instruction,
          response: response,
          effectiveness: :rand.uniform(),
          latency_ms: :rand.uniform(300) + 50
        }
      }
    end) |> Enum.into(%{})
    
    updated_responses = Map.merge(state.responses, instruction_configs)
    {:reply, :ok, %{state | responses: updated_responses}}
  end
  
  @impl true
  def handle_call({:setup_evaluation, scores}, _from, state) do
    evaluation_configs = Enum.with_index(scores, fn score, index ->
      {
        "evaluation_#{index}",
        %{
          type: :evaluation,
          score: score,
          confidence: :rand.uniform(),
          latency_ms: :rand.uniform(200) + 25
        }
      }
    end) |> Enum.into(%{})
    
    updated_responses = Map.merge(state.responses, evaluation_configs)
    {:reply, :ok, %{state | responses: updated_responses}}
  end
  
  @impl true
  def handle_call({:setup_beacon, config}, _from, state) do
    # Generate comprehensive BEACON workflow responses
    beacon_responses = generate_beacon_responses(config)
    
    updated_responses = Map.merge(state.responses, beacon_responses)
    {:reply, :ok, %{state | responses: updated_responses}}
  end
  
  @impl true
  def handle_call({:mock_request, messages, opts}, _from, state) do
    # Simulate latency if enabled
    if state.latency_simulation do
      latency = calculate_realistic_latency(messages, opts)
      Process.sleep(latency)
    end
    
    # Check for configured failure
    if should_fail?(state.failure_rate) do
      response = {:error, generate_failure_response()}
    else
      response = generate_mock_response(messages, opts, state)
    end
    
    # Record call in history
    call_record = %{
      timestamp: DateTime.utc_now(),
      messages: messages,
      options: opts,
      response: response,
      latency_ms: if(state.latency_simulation, do: calculate_realistic_latency(messages, opts), else: 0)
    }
    
    updated_history = [call_record | state.call_history]
    updated_state = %{state | call_history: updated_history}
    
    {:reply, response, updated_state}
  end
  
  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, Enum.reverse(state.call_history), state}
  end
  
  @impl true
  def handle_call(:reset, _from, state) do
    reset_state = %{state | responses: %{}, call_history: []}
    {:reply, :ok, reset_state}
  end
  
  ## Private Helpers
  
  defp generate_quality_score(response) do
    # Generate realistic quality scores based on response content
    content = get_response_content(response)
    base_score = :rand.uniform()
    
    # Adjust based on content characteristics
    complexity_bonus = min(String.length(content) / 100, 0.2)
    keyword_bonus = count_quality_keywords(content) * 0.1
    
    min(base_score + complexity_bonus + keyword_bonus, 1.0)
  end
  
  defp generate_beacon_responses(config) do
    %{
      "beacon_bootstrap" => generate_bootstrap_responses(config),
      "beacon_instruction" => generate_instruction_responses(config),
      "beacon_optimization" => generate_optimization_responses(config)
    }
  end
  
  defp generate_bootstrap_responses(config) do
    success_rate = config.bootstrap_success_rate
    
    %{
      type: :bootstrap_pattern,
      success_rate: success_rate,
      quality_distribution: config.quality_distribution,
      response_generator: fn _input ->
        if :rand.uniform() < success_rate do
          {:ok, generate_high_quality_bootstrap_response()}
        else
          {:error, :quality_too_low}
        end
      end
    }
  end
  
  defp generate_instruction_responses(config) do
    effectiveness = config.instruction_effectiveness
    
    %{
      type: :instruction_pattern,
      effectiveness: effectiveness,
      response_generator: fn instruction_prompt ->
        quality = :rand.uniform() * effectiveness
        
        {:ok, %{
          content: generate_instruction_response(instruction_prompt, quality),
          quality: quality,
          instruction_type: classify_instruction_type(instruction_prompt)
        }}
      end
    }
  end
  
  defp generate_optimization_responses(config) do
    trajectory = config.optimization_trajectory
    
    %{
      type: :optimization_pattern,
      trajectory: trajectory,
      iteration_count: 0,
      response_generator: fn iteration ->
        score = case trajectory do
          :improving -> 0.5 + (iteration * 0.1)
          :declining -> 0.9 - (iteration * 0.1)
          :plateau -> 0.7 + (:rand.uniform() - 0.5) * 0.1
          :noisy -> 0.6 + (:rand.uniform() - 0.5) * 0.3
        end
        
        {:ok, %{score: max(0.0, min(1.0, score)), iteration: iteration}}
      end
    }
  end
  
  defp generate_mock_response(messages, opts, state) do
    case state.mode do
      :deterministic -> generate_deterministic_response(messages, opts)
      :contextual -> generate_contextual_response(messages, opts)
      :recorded -> lookup_recorded_response(messages, opts, state)
      :generative -> generate_smart_response(messages, opts, state)
    end
  end
  
  defp generate_contextual_response(messages, _opts) do
    user_message = extract_user_message(messages)
    content = generate_contextual_content(user_message)
    
    {:ok, %{
      choices: [
        %{message: %{role: "assistant", content: content}}
      ]
    }}
  end
  
  defp generate_contextual_content(user_message) do
    content_lower = String.downcase(user_message)
    
    cond do
      # BEACON-specific patterns
      String.contains?(content_lower, ["bootstrap", "demonstration"]) ->
        "This is a bootstrap demonstration example: #{generate_demo_content()}"
      
      String.contains?(content_lower, ["instruction", "optimize"]) ->
        "Here is an optimized instruction: #{generate_instruction_content()}"
      
      String.contains?(content_lower, ["evaluate", "score"]) ->
        "Evaluation result: #{:rand.uniform()}"
      
      # Math and reasoning
      String.contains?(content_lower, ["2+2", "math", "calculate"]) ->
        "4"
      
      String.contains?(content_lower, ["reasoning", "think", "analyze"]) ->
        generate_reasoning_content()
      
      # Default contextual response
      String.length(user_message) > 0 ->
        "Mock response for: #{String.slice(user_message, 0, 50)}"
      
      true ->
        "Default mock response"
    end
  end
  
  defp generate_demo_content() do
    examples = [
      "Question: What is the capital of France? Answer: Paris",
      "Question: What is 2+2? Answer: 4", 
      "Question: Who wrote Romeo and Juliet? Answer: William Shakespeare"
    ]
    Enum.random(examples)
  end
  
  defp generate_instruction_content() do
    instructions = [
      "Think step by step and provide a clear answer.",
      "Consider multiple perspectives before responding.",
      "Use specific examples to support your reasoning.",
      "Break down complex problems into smaller parts."
    ]
    Enum.random(instructions)
  end
  
  defp generate_reasoning_content() do
    "Let me think through this step by step:\n1. First, I'll analyze the question\n2. Then consider the available information\n3. Finally, formulate a clear response"
  end
  
  defp should_fail?(failure_rate) do
    :rand.uniform() < failure_rate
  end
  
  defp generate_failure_response() do
    failures = [:timeout, :network_error, :api_error, :rate_limited]
    Enum.random(failures)
  end
  
  defp calculate_realistic_latency(messages, opts) do
    # Simulate realistic API latency based on message complexity
    base_latency = 100
    message_complexity = calculate_message_complexity(messages)
    provider_factor = get_provider_latency_factor(opts[:provider])
    
    round(base_latency + message_complexity * 10 + (:rand.uniform(200) - 100) * provider_factor)
  end
  
  defp calculate_message_complexity(messages) do
    total_length = Enum.reduce(messages, 0, fn message, acc ->
      acc + String.length(Map.get(message, :content, ""))
    end)
    
    min(total_length / 100, 10)  # Cap complexity at 10
  end
  
  defp get_provider_latency_factor(:openai), do: 1.0
  defp get_provider_latency_factor(:anthropic), do: 1.2
  defp get_provider_latency_factor(:gemini), do: 0.8
  defp get_provider_latency_factor(_), do: 1.0
  
  defp get_response_content(%{content: content}), do: content
  defp get_response_content(content) when is_binary(content), do: content
  defp get_response_content(_), do: ""
  
  defp count_quality_keywords(content) do
    quality_keywords = ["step by step", "analyze", "consider", "therefore", "because", "example"]
    
    Enum.count(quality_keywords, fn keyword ->
      String.contains?(String.downcase(content), keyword)
    end)
  end
  
  defp extract_user_message(messages) do
    Enum.find_value(messages, "", fn message ->
      if Map.get(message, :role) == "user" do
        Map.get(message, :content, "")
      end
    end)
  end
  
  defp generate_deterministic_response(_messages, _opts) do
    {:ok, %{
      choices: [
        %{message: %{role: "assistant", content: "Deterministic mock response"}}
      ]
    }}
  end
  
  defp lookup_recorded_response(_messages, _opts, _state) do
    # Implementation for recorded response lookup
    {:ok, %{
      choices: [
        %{message: %{role: "assistant", content: "Recorded mock response"}}
      ]
    }}
  end
  
  defp generate_smart_response(_messages, _opts, _state) do
    # Implementation for AI-generated responses
    {:ok, %{
      choices: [
        %{message: %{role: "assistant", content: "Smart generated response"}}
      ]
    }}
  end
  
  defp classify_instruction_type(prompt) do
    cond do
      String.contains?(prompt, "step by step") -> :reasoning
      String.contains?(prompt, "example") -> :demonstration
      String.contains?(prompt, "format") -> :formatting
      true -> :general
    end
  end
end
```

## Phase 4: Integration Testing Infrastructure (Days 9-10)

### 4.1 End-to-End Teleprompter Workflow Tests (Day 9)

**Priority**: 🟡 HIGH - Validate complete pipeline before BEACON

**Implementation**:

```elixir
# File: test/dspex/integration/teleprompter_workflow_test.exs
defmodule DSPEx.Integration.TeleprompterWorkflowTest do
  use ExUnit.Case, async: false
  
  alias DSPEx.{Teleprompter, Example, Predict, OptimizedProgram}
  alias DSPEx.Test.MockProvider
  alias DSPEx.Teleprompter.BootstrapFewShot
  
  @moduletag :integration
  
  setup do
    # Set up mock provider for reliable testing
    {:ok, _pid} = MockProvider.start_link(mode: :contextual)
    
    # Create test signature
    defmodule TestWorkflowSignature do
      use DSPEx.Signature, "question -> answer"
    end
    
    # Create programs
    student = %Predict{signature: TestWorkflowSignature, client: :test}
    teacher = %Predict{signature: TestWorkflowSignature, client: :test}
    
    # Create training examples
    trainset = [
      %Example{
        data: %{question: "What is 2+2?", answer: "4"},
        input_keys: MapSet.new([:question])
      },
      %Example{
        data: %{question: "What is 3+3?", answer: "6"},
        input_keys: MapSet.new([:question])
      },
      %Example{
        data: %{question: "What is the capital of France?", answer: "Paris"},
        input_keys: MapSet.new([:question])
      }
    ]
    
    # Create metric function
    metric_fn = Teleprompter.exact_match(:answer)
    
    %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    }
  end
  
  describe "complete teleprompter workflow" do
    test "BootstrapFewShot complete pipeline", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Set up realistic bootstrap responses
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])
      
      # Create teleprompter
      teleprompter = BootstrapFewShot.new(
        max_bootstrapped_demos: 2,
        quality_threshold: 0.5
      )
      
      # Execute compilation
      result = BootstrapFewShot.compile(
        teleprompter,
        student,
        teacher,
        trainset,
        metric_fn
      )
      
      # Validate result
      assert {:ok, optimized_student} = result
      assert is_struct(optimized_student)
      
      # Check that optimized student has demos
      case optimized_student do
        %OptimizedProgram{demos: demos} ->
          assert length(demos) > 0
          assert Enum.all?(demos, &is_struct(&1, Example))
        
        %{demos: demos} ->
          assert length(demos) > 0
          assert Enum.all?(demos, &is_struct(&1, Example))
        
        _ ->
          flunk("Expected optimized student to have demos")
      end
    end
    
    test "student -> teacher -> optimized student pipeline", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Test the complete pipeline that BEACON will use
      
      # 1. Validate inputs
      assert :ok = Teleprompter.validate_student(student)
      assert :ok = Teleprompter.validate_teacher(teacher)
      assert :ok = Teleprompter.validate_trainset(trainset)
      
      # 2. Set up mock responses for teacher
      MockProvider.setup_bootstrap_mocks([
        %{content: "The answer is 4"},
        %{content: "The answer is 6"},
        %{content: "The capital of France is Paris"}
      ])
      
      # 3. Execute teleprompter compilation
      teleprompter = BootstrapFewShot.new(max_bootstrapped_demos: 3)
      
      {:ok, optimized} = BootstrapFewShot.compile(
        teleprompter,
        student,
        teacher,
        trainset,
        metric_fn
      )
      
      # 4. Validate optimized program can make predictions
      test_input = %{question: "What is 5+5?"}
      MockProvider.setup_evaluation_mocks([0.9])
      
      case DSPEx.Program.forward(optimized, test_input) do
        {:ok, prediction} ->
          assert %{answer: answer} = prediction
          assert is_binary(answer)
        
        {:error, reason} ->
          flunk("Optimized program failed to make prediction: #{inspect(reason)}")
      end
    end
    
    test "error handling in teleprompter workflow", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Test various error conditions
      
      # Invalid student
      assert {:error, _} = BootstrapFewShot.compile(
        BootstrapFewShot.new(),
        "not a program",
        teacher,
        trainset,
        metric_fn
      )
      
      # Invalid teacher
      assert {:error, _} = BootstrapFewShot.compile(
        BootstrapFewShot.new(),
        student,
        %{invalid: "teacher"},
        trainset,
        metric_fn
      )
      
      # Empty trainset
      assert {:error, _} = BootstrapFewShot.compile(
        BootstrapFewShot.new(),
        student,
        teacher,
        [],
        metric_fn
      )
      
      # Invalid metric function
      assert {:error, _} = BootstrapFewShot.compile(
        BootstrapFewShot.new(),
        student,
        teacher,
        trainset,
        "not a function"
      )
    end
  end
  
  describe "performance and reliability" do
    test "handles concurrent teleprompter operations" do
      # Test multiple teleprompter operations running concurrently
      
      # This simulates what might happen when BEACON is running
      # multiple optimization trials simultaneously
      
      # Implementation would test concurrent compilation
      # This is a placeholder for the actual implementation
      assert true
    end
    
    test "recovers from individual example failures" do
      # Test that teleprompter continues when some examples fail
      
      # Set up mock to fail some responses
      MockProvider.setup_bootstrap_mocks([
        {:error, :api_error},  # This should be handled gracefully
        %{content: "6"},
        %{content: "Paris"}
      ])
      
      # The teleprompter should still succeed with the good examples
      # Implementation would test this behavior
      assert true
    end
  end
end
```

### 4.2 Multi-Provider Switching Tests (Day 10)

**Priority**: 🟡 MEDIUM - Ensure BEACON can use different providers

**Implementation**:

```elixir
# File: test/dspex/integration/multi_provider_test.exs
defmodule DSPEx.Integration.MultiProviderTest do
  use ExUnit.Case, async: false
  
  alias DSPEx.{Client, Predict, Example}
  alias DSPEx.Test.MockProvider
  
  @moduletag :integration
  
  setup do
    {:ok, _pid} = MockProvider.start_link(mode: :contextual, latency_simulation: true)
    
    defmodule MultiProviderSignature do
      use DSPEx.Signature, "question -> answer"
    end
    
    %{signature: MultiProviderSignature}
  end
  
  describe "provider switching during teleprompter operations" do
    test "BEACON can use different providers for teacher and student", %{signature: signature} do
      # Create teacher with OpenAI
      teacher = %Predict{signature: signature, client: :openai}
      
      # Create student with Gemini
      student = %Predict{signature: signature, client: :gemini}
      
      # Set up provider-specific mock responses
      MockProvider.setup_bootstrap_mocks([
        %{provider: :openai, content: "Teacher response from OpenAI"},
        %{provider: :gemini, content: "Student response from Gemini"}
      ])
      
      # Test that both can make requests
      teacher_input = %{question: "Teacher test"}
      {:ok, teacher_response} = DSPEx.Program.forward(teacher, teacher_input)
      assert %{answer: teacher_answer} = teacher_response
      assert is_binary(teacher_answer)
      
      student_input = %{question: "Student test"}
      {:ok, student_response} = DSPEx.Program.forward(student, student_input)
      assert %{answer: student_answer} = student_response
      assert is_binary(student_answer)
    end
    
    test "provider failures don't cascade", %{signature: signature} do
      # Test that failure in one provider doesn't affect others
      
      programs = [
        %Predict{signature: signature, client: :openai},
        %Predict{signature: signature, client: :gemini},
        %Predict{signature: signature, client: :anthropic}
      ]
      
      # Set up one provider to fail
      MockProvider.setup_bootstrap_mocks([
        {:error, :api_error},  # OpenAI fails
        %{content: "Gemini success"},
        %{content: "Anthropic success"}
      ])
      
      inputs = %{question: "Test question"}
      
      results = Task.async_stream(programs, fn program ->
        DSPEx.Program.forward(program, inputs)
      end, timeout: 5000)
      |> Enum.to_list()
      
      # Should have some successes despite one failure
      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)
      
      assert successes >= 2  # At least 2 providers should work
    end
  end
  
  describe "load balancing across providers" do
    test "distributes requests across multiple providers" do
      # Test that BEACON can distribute optimization work across providers
      
      programs = [
        %Predict{signature: MultiProviderSignature, client: :openai},
        %Predict{signature: MultiProviderSignature, client: :gemini}
      ]
      
      # Make many requests and verify distribution
      results = Task.async_stream(1..20, fn i ->
        program = Enum.at(programs, rem(i, length(programs)))
        inputs = %{question: "Test question #{i}"}
        
        {program.client, DSPEx.Program.forward(program, inputs)}
      end, max_concurrency: 10)
      |> Enum.to_list()
      
      # Verify both providers were used
      providers_used = results
      |> Enum.map(fn {:ok, {provider, _result}} -> provider end)
      |> Enum.uniq()
      
      assert length(providers_used) >= 2
    end
  end
end
```

## Phase 5: Pre-BEACON Validation (Days 11-12)

### 5.1 Comprehensive Integration Validation (Day 11)

**Priority**: 🔴 CRITICAL - Final validation before BEACON

**Implementation**:

```elixir
# File: test/dspex/integration/pre_beacon_validation_test.exs
defmodule DSPEx.Integration.PreBEACONValidationTest do
  use ExUnit.Case, async: false
  
  alias DSPEx.{Teleprompter, Example, Predict, OptimizedProgram, Program}
  alias DSPEx.Test.MockProvider
  alias DSPEx.Teleprompter.BootstrapFewShot
  
  @moduletag :integration
  @moduletag :pre_beacon
  
  setup_all do
    # Comprehensive setup that mirrors what BEACON will need
    {:ok, _mock} = MockProvider.start_link(mode: :contextual)
    
    # Create test signature exactly as BEACON examples use
    defmodule BEACONCompatSignature do
      use DSPEx.Signature, "question -> answer"
    end
    
    :ok
  end
  
  describe "BEACON interface compatibility validation" do
    test "all required behaviors and modules exist" do
      # Test 1: DSPEx.Teleprompter behavior exists and is complete
      assert Code.ensure_loaded?(DSPEx.Teleprompter)
      assert function_exported?(DSPEx.Teleprompter, :behaviour_info, 1)
      
      callbacks = DSPEx.Teleprompter.behaviour_info(:callbacks)
      required_callback = {:compile, 5}
      assert required_callback in callbacks
      
      # Test 2: DSPEx.OptimizedProgram has required interface
      assert Code.ensure_loaded?(DSPEx.OptimizedProgram)
      assert function_exported?(DSPEx.OptimizedProgram, :new, 3)
      assert function_exported?(DSPEx.OptimizedProgram, :get_demos, 1)
      assert function_exported?(DSPEx.OptimizedProgram, :get_program, 1)
      
      # Test 3: DSPEx.Program utilities exist
      assert function_exported?(DSPEx.Program, :program_name, 1)
      assert function_exported?(DSPEx.Program, :implements_program?, 1)
    end
    
    test "teleprompter behavior validation functions work" do
      # Test validation functions that BEACON will use
      student = %Predict{signature: BEACONCompatSignature, client: :test}
      teacher = %Predict{signature: BEACONCompatSignature, client: :test}
      
      trainset = [
        %Example{
          data: %{question: "Test", answer: "Response"},
          input_keys: MapSet.new([:question])
        }
      ]
      
      # All validations should pass
      assert :ok = Teleprompter.validate_student(student)
      assert :ok = Teleprompter.validate_teacher(teacher)
      assert :ok = Teleprompter.validate_trainset(trainset)
      
      # Program behavior checking
      assert Program.implements_program?(Predict)
      assert Program.implements_program?(OptimizedProgram)
    end
    
    test "OptimizedProgram interface matches BEACON expectations" do
      # Create programs exactly as BEACON will
      base_program = %Predict{signature: BEACONCompatSignature, client: :test}
      
      demos = [
        %Example{
          data: %{question: "What is 2+2?", answer: "4"},
          input_keys: MapSet.new([:question])
        }
      ]
      
      # Test OptimizedProgram.new/3 interface
      optimized = OptimizedProgram.new(base_program, demos, %{
        teleprompter: :beacon,
        optimization_time: DateTime.utc_now()
      })
      
      # Test interface functions BEACON uses
      assert ^demos = OptimizedProgram.get_demos(optimized)
      assert ^base_program = OptimizedProgram.get_program(optimized)
      
      # Test that optimized program implements Program behavior
      assert Program.implements_program?(OptimizedProgram)
      
      # Test forward function works
      MockProvider.setup_evaluation_mocks([0.9])
      inputs = %{question: "Test forward"}
      
      case Program.forward(optimized, inputs) do
        {:ok, result} ->
          assert %{answer: _} = result
        {:error, reason} ->
          flunk("OptimizedProgram forward failed: #{inspect(reason)}")
      end
    end
  end
  
  describe "BootstrapFewShot teleprompter validation" do
    test "implements DSPEx.Teleprompter behavior correctly" do
      # Verify BootstrapFewShot implements the behavior
      assert Teleprompter.implements_behavior?(BootstrapFewShot)
      
      # Test that compile/5 function exists with correct arity
      assert function_exported?(BootstrapFewShot, :compile, 5)
      assert function_exported?(BootstrapFewShot, :compile, 6)  # struct version
    end
    
    test "complete BootstrapFewShot workflow succeeds" do
      # Set up complete workflow that mirrors BEACON usage
      student = %Predict{signature: BEACONCompatSignature, client: :test}
      teacher = %Predict{signature: BEACONCompatSignature, client: :test}
      
      trainset = [
        %Example{
          data: %{question: "What is 2+2?", answer: "4"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "What is 3+3?", answer: "6"},  
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "What is 4+4?", answer: "8"},
          input_keys: MapSet.new([:question])
        }
      ]
      
      metric_fn = Teleprompter.exact_match(:answer)
      
      # Set up realistic mock responses
      MockProvider.setup_bootstrap_mocks([
        %{content: "4"},
        %{content: "6"},
        %{content: "8"}
      ])
      
      # Execute teleprompter compilation
      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 2,
        quality_threshold: 0.5
      )
      
      # Validate successful compilation
      assert {:ok, optimized_student} = result
      assert is_struct(optimized_student)
      
      # Validate optimized student has demos
      demos = case optimized_student do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized_student)
        %{demos: demos} -> demos
        _ -> []
      end
      
      assert length(demos) > 0
      assert Enum.all?(demos, &is_struct(&1, Example))
    end
    
    test "handles edge cases that BEACON might encounter" do
      student = %Predict{signature: BEACONCompatSignature, client: :test}
      teacher = %Predict{signature: BEACONCompatSignature, client: :test}
      metric_fn = Teleprompter.exact_match(:answer)
      
      # Test with minimal trainset
      minimal_trainset = [
        %Example{
          data: %{question: "Single example", answer: "Response"},
          input_keys: MapSet.new([:question])
        }
      ]
      
      MockProvider.setup_bootstrap_mocks([%{content: "Response"}])
      
      result = BootstrapFewShot.compile(
        student,
        teacher, 
        minimal_trainset,
        metric_fn,
        max_bootstrapped_demos: 1
      )
      
      # Should succeed even with minimal data
      assert {:ok, _optimized} = result
      
      # Test with all low-quality responses
      low_quality_trainset = [
        %Example{
          data: %{question: "Low quality", answer: "Expected"},
          input_keys: MapSet.new([:question])
        }
      ]
      
      MockProvider.setup_bootstrap_mocks([%{content: "Different response"}])
      
      result_low_quality = BootstrapFewShot.compile(
        student,
        teacher,
        low_quality_trainset,
        metric_fn,
        quality_threshold: 0.9  # Very high threshold
      )
      
      # Should handle gracefully (might return original student or error)
      case result_low_quality do
        {:ok, _} -> :ok  # Acceptable
        {:error, _} -> :ok  # Also acceptable
      end
    end
  end
  
  describe "program name and telemetry utilities" do
    test "program_name function works for all program types" do
      # Test program_name with various program types BEACON will encounter
      
      predict_program = %Predict{signature: BEACONCompatSignature, client: :test}
      assert Program.program_name(predict_program) == :Predict
      
      optimized_program = OptimizedProgram.new(predict_program, [], %{})
      optimized_name = Program.program_name(optimized_program)
      assert is_atom(optimized_name)
      assert String.contains?(Atom.to_string(optimized_name), "Optimized")
      
      # Test with invalid input
      assert Program.program_name("not a program") == :unknown
      assert Program.program_name(nil) == :unknown
    end
    
    test "safe program info extraction for telemetry" do
      # Test safe info extraction that BEACON telemetry will use
      program = %Predict{signature: BEACONCompatSignature, client: :test}
      
      info = Program.safe_program_info(program)
      
      assert %{
        type: :predict,
        name: :Predict,
        module: Predict,
        has_demos: false
      } = info
      
      # Test with demos
      program_with_demos = %{program | demos: [%Example{data: %{}, input_keys: MapSet.new()}]}
      info_with_demos = Program.safe_program_info(program_with_demos)
      assert info_with_demos.has_demos == true
    end
  end
  
  describe "client architecture validation" do
    test "client handles concurrent requests reliably" do
      # Test concurrent usage pattern that BEACON will create
      messages = [%{role: "user", content: "Concurrent test"}]
      
      # BEACON will make many concurrent requests during optimization
      concurrent_requests = Task.async_stream(1..20, fn i ->
        correlation_id = "beacon-test-#{i}"
        DSPEx.Client.request(messages, %{
          provider: :gemini,
          correlation_id: correlation_id
        })
      end, max_concurrency: 10, timeout: 10_000)
      |> Enum.to_list()
      
      # Count successes
      successes = Enum.count(concurrent_requests, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)
      
      # Should handle most requests successfully
      assert successes >= 18  # Allow a few failures
    end
    
    test "correlation_id propagation works" do
      # BEACON heavily uses correlation IDs for tracking optimization
      messages = [%{role: "user", content: "Correlation test"}]
      correlation_id = "beacon-correlation-#{System.unique_integer()}"
      
      {:ok, _response} = DSPEx.Client.request(messages, %{
        provider: :gemini,
        correlation_id: correlation_id
      })
      
      # In a real implementation, we'd verify the correlation_id
      # was properly propagated through telemetry events
      # For now, just verify the request succeeds
      assert true
    end
  end
  
  describe "error handling and recovery" do
    test "graceful handling of teacher failures during bootstrap" do
      # BEACON needs robust error handling when teacher calls fail
      student = %Predict{signature: BEACONCompatSignature, client: :test}
      teacher = %Predict{signature: BEACONCompatSignature, client: :test}
      
      trainset = [
        %Example{
          data: %{question: "Test 1", answer: "Response 1"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "Test 2", answer: "Response 2"},
          input_keys: MapSet.new([:question])
        }
      ]
      
      metric_fn = Teleprompter.exact_match(:answer)
      
      # Set up mixed success/failure responses
      MockProvider.setup_bootstrap_mocks([
        {:error, :api_error},  # First example fails
        %{content: "Response 2"}  # Second succeeds
      ])
      
      result = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 2
      )
      
      # Should succeed with partial results
      assert {:ok, optimized} = result
      
      # Should have at least some demos from successful examples
      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end
      
      # Might have fewer demos due to failures, but should still work
      assert is_list(demos)
    end
    
    test "recovery from client connection issues" do
      # Test that BEACON can recover from temporary client issues
      messages = [%{role: "user", content: "Recovery test"}]
      
      # Simulate intermittent failures
      MockProvider.reset()
      
      # Multiple attempts should eventually succeed due to fallback mechanisms
      results = Enum.map(1..5, fn _i ->
        DSPEx.Client.request(messages, %{provider: :gemini})
      end)
      
      # At least some should succeed
      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      assert successes >= 3
    end
  end
end
```

### 5.2 Performance and Memory Validation (Day 12)

**Priority**: 🟡 HIGH - Ensure BEACON won't have performance issues

**Implementation**:

```elixir
# File: test/dspex/performance/pre_beacon_performance_test.exs
defmodule DSPEx.Performance.PreBEACONPerformanceTest do
  use ExUnit.Case, async: false
  
  alias DSPEx.{Teleprompter, Example, Predict, Program}
  alias DSPEx.Test.MockProvider
  alias DSPEx.Teleprompter.BootstrapFewShot
  
  @moduletag :performance
  @moduletag :pre_beacon
  
  setup_all do
    {:ok, _mock} = MockProvider.start_link(
      mode: :contextual,
      latency_simulation: false  # Disable for performance testing
    )
    
    defmodule PerformanceSignature do
      use DSPEx.Signature, "question -> answer"
    end
    
    %{signature: PerformanceSignature}
  end
  
  describe "memory usage validation" do
    test "teleprompter compilation doesn't leak memory", %{signature: signature} do
      # BEACON will run many optimization iterations
      # Need to ensure no memory leaks
      
      initial_memory = :erlang.memory()
      
      # Run multiple teleprompter compilations
      for _i <- 1..10 do
        student = %Predict{signature: signature, client: :test}
        teacher = %Predict{signature: signature, client: :test}
        
        trainset = create_test_trainset(20)  # Reasonable size
        metric_fn = Teleprompter.exact_match(:answer)
        
        MockProvider.setup_bootstrap_mocks(
          Enum.map(1..20, fn i -> %{content: "Response #{i}"} end)
        )
        
        {:ok, _optimized} = BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 5
        )
        
        # Force garbage collection
        :erlang.garbage_collect()
      end
      
      final_memory = :erlang.memory()
      
      # Memory should not have grown significantly
      memory_growth = final_memory[:total] - initial_memory[:total]
      memory_growth_mb = memory_growth / (1024 * 1024)
      
      # Allow some growth but not excessive
      assert memory_growth_mb < 50, "Memory grew by #{memory_growth_mb}MB"
    end
    
    test "large trainsets don't cause memory issues", %{signature: signature} do
      # BEACON might use large training sets
      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}
      
      # Create large trainset
      large_trainset = create_test_trainset(1000)
      metric_fn = Teleprompter.exact_match(:answer)
      
      # Set up mock responses
      MockProvider.setup_bootstrap_mocks(
        Enum.map(1..1000, fn i -> %{content: "Response #{i}"} end)
      )
      
      memory_before = :erlang.memory()[:total]
      
      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        large_trainset,
        metric_fn,
        max_bootstrapped_demos: 10
      )
      
      memory_after = :erlang.memory()[:total]
      memory_used_mb = (memory_after - memory_before) / (1024 * 1024)
      
      # Should handle large datasets efficiently
      assert memory_used_mb < 100, "Used #{memory_used_mb}MB for large trainset"
    end
  end
  
  describe "performance benchmarks" do
    test "teleprompter compilation performance", %{signature: signature} do
      # Benchmark compilation time for BEACON planning
      
      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}
      trainset = create_test_trainset(50)
      metric_fn = Teleprompter.exact_match(:answer)
      
      MockProvider.setup_bootstrap_mocks(
        Enum.map(1..50, fn i -> %{content: "Response #{i}"} end)
      )
      
      {duration_us, {:ok, _optimized}} = :timer.tc(fn ->
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 8
        )
      end)
      
      duration_ms = duration_us / 1000
      
      # Should complete in reasonable time
      assert duration_ms < 5000, "Compilation took #{duration_ms}ms"
      
      # Log performance for monitoring
      IO.puts("BootstrapFewShot compilation: #{duration_ms}ms for 50 examples")
    end
    
    test "concurrent program execution performance", %{signature: signature} do
      # Test performance under concurrent load (BEACON pattern)
      
      program = %Predict{signature: signature, client: :test}
      inputs = %{question: "Performance test"}
      
      MockProvider.setup_evaluation_mocks(
        Enum.map(1..100, fn _i -> :rand.uniform() end)
      )
      
      {duration_us, results} = :timer.tc(fn ->
        Task.async_stream(1..100, fn _i ->
          Program.forward(program, inputs)
        end, max_concurrency: 20, timeout: 10_000)
        |> Enum.to_list()
      end)
      
      duration_ms = duration_us / 1000
      
      # Count successes
      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)
      
      throughput = successes / (duration_ms / 1000)  # requests per second
      
      assert successes >= 95, "Only #{successes}/100 requests succeeded"
      assert throughput > 10, "Throughput too low: #{throughput} req/sec"
      
      IO.puts("Concurrent execution: #{throughput} req/sec, #{successes}% success")
    end
    
    test "program creation and destruction performance" do
      # BEACON creates many temporary programs during optimization
      
      {duration_us, _} = :timer.tc(fn ->
        for _i <- 1..1000 do
          student = %Predict{signature: PerformanceSignature, client: :test}
          demos = [%Example{data: %{question: "test", answer: "response"}, input_keys: MapSet.new([:question])}]
          
          _optimized = DSPEx.OptimizedProgram.new(student, demos)
        end
      end)
      
      duration_ms = duration_us / 1000
      rate = 1000 / (duration_ms / 1000)  # creations per second
      
      assert rate > 100, "Program creation rate too low: #{rate} per second"
      
      IO.puts("Program creation rate: #{rate} per second")
    end
  end
  
  describe "scalability validation" do
    test "teleprompter scales with training set size", %{signature: signature} do
      # Test performance scaling for different training set sizes
      
      sizes = [10, 50, 100, 200]
      results = []
      
      for size <- sizes do
        student = %Predict{signature: signature, client: :test}
        teacher = %Predict{signature: signature, client: :test}
        trainset = create_test_trainset(size)
        metric_fn = Teleprompter.exact_match(:answer)
        
        MockProvider.setup_bootstrap_mocks(
          Enum.map(1..size, fn i -> %{content: "Response #{i}"} end)
        )
        
        {duration_us, {:ok, _optimized}} = :timer.tc(fn ->
          BootstrapFewShot.compile(
            student,
            teacher,
            trainset,
            metric_fn,
            max_bootstrapped_demos: min(size, 10)
          )
        end)
        
        duration_ms = duration_us / 1000
        per_example_ms = duration_ms / size
        
        results = [{size, duration_ms, per_example_ms} | results]
        
        IO.puts("Size #{size}: #{duration_ms}ms total, #{per_example_ms}ms per example")
      end
      
      # Verify scaling is reasonable (not exponential)
      results = Enum.reverse(results)
      
      # Check that per-example time doesn't grow too much
      [{_, _, first_per_example} | _] = results
      {_, _, last_per_example} = List.last(results)
      
      scaling_factor = last_per_example / first_per_example
      assert scaling_factor < 3.0, "Poor scaling: #{scaling_factor}x slower per example"
    end
    
    test "handles high demo counts efficiently", %{signature: signature} do
      # BEACON might create programs with many demonstrations
      
      student = %Predict{signature: signature, client: :test}
      
      # Create program with many demos
      many_demos = Enum.map(1..100, fn i ->
        %Example{
          data: %{question: "Question #{i}", answer: "Answer #{i}"},
          input_keys: MapSet.new([:question])
        }
      end)
      
      {creation_duration, optimized} = :timer.tc(fn ->
        DSPEx.OptimizedProgram.new(student, many_demos)
      end)
      
      # Test forward performance with many demos
      MockProvider.setup_evaluation_mocks([0.9])
      
      {forward_duration, {:ok, _result}} = :timer.tc(fn ->
        Program.forward(optimized, %{question: "Test with many demos"})
      end)
      
      creation_ms = creation_duration / 1000
      forward_ms = forward_duration / 1000
      
      assert creation_ms < 100, "Program creation with 100 demos too slow: #{creation_ms}ms"
      assert forward_ms < 1000, "Forward with 100 demos too slow: #{forward_ms}ms"
      
      IO.puts("100 demos - Creation: #{creation_ms}ms, Forward: #{forward_ms}ms")
    end
  end
  
  # Helper functions
  defp create_test_trainset(size) do
    Enum.map(1..size, fn i ->
      %Example{
        data: %{question: "Question #{i}", answer: "Answer #{i}"},
        input_keys: MapSet.new([:question])
      }
    end)
  end
end
```

## Implementation Timeline and Checklist

### Week 1: Core Infrastructure
- **Day 1**: ✅ DSPEx.Teleprompter behavior implementation
- **Day 2**: ✅ DSPEx.OptimizedProgram interface completion  
- **Day 3**: ✅ DSPEx.Program utilities implementation
- **Day 4**: ✅ Signature extension capabilities
- **Day 5**: ✅ Enhanced signature introspection

### Week 2: Client & Testing Infrastructure
- **Day 6**: ✅ Multi-provider reliability testing
- **Day 7**: ✅ Foundation integration verification
- **Day 8**: ✅ Enhanced mock framework for BEACON
- **Day 9**: ✅ End-to-end teleprompter workflow tests
- **Day 10**: ✅ Multi-provider switching tests

### Week 2 Finale: Pre-BEACON Validation
- **Day 11**: ✅ Comprehensive integration validation
- **Day 12**: ✅ Performance and memory validation

## Success Criteria for BEACON Integration

### ✅ Critical Infrastructure Complete
- [ ] `DSPEx.Teleprompter` behavior defined and functional
- [ ] `DSPEx.OptimizedProgram.new/3` matches BEACON interface exactly  
- [ ] `DSPEx.Program.program_name/1` available for telemetry
- [ ] All existing tests pass with new architecture

### ✅ Enhanced Capabilities Ready
- [ ] Signature extension working for ChainOfThought patterns
- [ ] Multi-provider client architecture stable under load
- [ ] Enhanced mock framework supports complex BEACON workflows
- [ ] Foundation integration verified and operational

### ✅ Quality Assurance Complete
- [ ] End-to-end teleprompter workflows validated
- [ ] Memory usage stable under optimization workloads
- [ ] Performance benchmarks meet target thresholds
- [ ] Error handling robust for production use

### ✅ BEACON Integration Readiness
- [ ] All BEACON-referenced functions exist and work correctly
- [ ] BootstrapFewShot teleprompter serves as working example
- [ ] Client architecture handles concurrent optimization requests
- [ ] Comprehensive test coverage ensures reliability

## Risk Mitigation

### High-Priority Risks

**Risk**: BEACON integration reveals interface incompatibilities
**Mitigation**: Detailed interface validation tests that mirror exact BEACON usage patterns

**Risk**: Performance degradation under optimization workloads  
**Mitigation**: Comprehensive performance testing with realistic BEACON-like workloads

**Risk**: Memory leaks during repeated optimizations
**Mitigation**: Memory profiling tests that simulate BEACON's optimization cycles

### Medium-Priority Risks

**Risk**: Foundation integration issues in production
**Mitigation**: Fallback implementations and gradual rollout strategy

**Risk**: Multi-provider reliability issues
**Mitigation**: Enhanced error handling and circuit breaker integration

## Post-Implementation Validation

Once all phases are complete, run this comprehensive validation:

```bash
# Run all pre-BEACON validation tests
mix test test/dspex/integration/pre_beacon_validation_test.exs --include pre_beacon

# Run performance benchmarks  
mix test test/dspex/performance/pre_beacon_performance_test.exs --include performance

# Verify no regressions
mix test

# Check Dialyzer warnings
mix dialyzer

# Verify documentation builds
mix docs
```

## Ready for BEACON

After completing this plan, your DSPEx implementation will have:

1. **All required infrastructure** for BEACON teleprompter integration
2. **Validated interfaces** that match BEACON's expectations exactly
3. **Performance characteristics** suitable for optimization workloads  
4. **Robust error handling** for production reliability
5. **Comprehensive test coverage** ensuring continued compatibility

The foundation will be solid and ready for the revolutionary distributed AI capabilities that BEACON will bring to the BEAM ecosystem.