# DSPEx Contract Implementation Roadmap

**Objective:** Implement the APIs defined in the DSPEx-SIMBA Contract Specification  
**Timeline:** 2-3 days of focused implementation  
**Priority:** Critical blocker for SIMBA integration

## Phase 1: Core Program Contract Implementation (Day 1)

### 1.1 Program.forward/3 Options Support

**File:** `lib/dspex/program.ex`

**Current State:**
```elixir
# Existing implementation only supports forward/2
def forward(program, inputs) when is_map(inputs) do
  # ... existing implementation
end
```

**Required Implementation:**
```elixir
# Add forward/3 with options support
@spec forward(t(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}
def forward(program, inputs, opts) when is_map(inputs) and is_list(opts) do
  # Extract and validate options
  correlation_id = Keyword.get(opts, :correlation_id) || generate_correlation_id()
  timeout = Keyword.get(opts, :timeout, 30_000)
  
  # Wrap existing forward/2 with timeout and telemetry
  task = Task.async(fn ->
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
  end)
  
  case Task.yield(task, timeout) do
    {:ok, result} -> result
    nil ->
      Task.shutdown(task, :brutal_kill)
      {:error, :timeout}
  end
end

# Maintain backward compatibility
def forward(program, inputs) when is_map(inputs) do
  forward(program, inputs, [])
end
```

### 1.2 Program Introspection Functions

**File:** `lib/dspex/program.ex`

**Add Missing Functions:**
```elixir
@doc """
Determine the type of a program for optimization strategies.
"""
@spec program_type(t()) :: :predict | :optimized | :custom | :unknown
def program_type(program) when is_struct(program) do
  case program.__struct__ |> Module.split() |> List.last() do
    "Predict" -> :predict
    "OptimizedProgram" -> :optimized
    _ -> :custom
  end
end
def program_type(_), do: :unknown

@doc """
Extract safe program information without sensitive data.
Critical: Used by SIMBA for program analysis and telemetry.
"""
@spec safe_program_info(t()) :: %{
  type: atom(),
  name: atom(),
  has_demos: boolean(),
  signature: atom() | nil
}
def safe_program_info(program) when is_struct(program) do
  %{
    type: program_type(program),
    name: program_name(program),
    has_demos: has_demos?(program),
    signature: get_signature_module(program)
  }
end

@doc """
Check if a program contains demonstration examples.
Critical: Used by SIMBA to determine wrapping strategy.
"""
@spec has_demos?(t()) :: boolean()
def has_demos?(program) when is_struct(program) do
  cond do
    Map.has_key?(program, :demos) and is_list(program.demos) ->
      length(program.demos) > 0
    true -> 
      false
  end
end

# Private helper function
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
```

### 1.3 Validation Tests

**File:** `test/unit/program_contract_test.exs`

```elixir
defmodule DSPEx.ProgramContractTest do
  use ExUnit.Case, async: true
  
  alias DSPEx.{Program, Predict, OptimizedProgram, Example}
  
  defmodule TestSignature do
    use DSPEx.Signature, "question -> answer"
  end
  
  setup do
    predict_program = %Predict{signature: TestSignature, client: :test}
    demo = %Example{data: %{q: "test", a: "answer"}, input_keys: MapSet.new([:q])}
    optimized_program = OptimizedProgram.new(predict_program, [demo])
    
    %{
      predict: predict_program,
      optimized: optimized_program,
      demo: demo
    }
  end
  
  describe "Program.forward/3 contract" do
    test "supports timeout option", %{predict: program} do
      inputs = %{question: "test"}
      
      # Should work with timeout
      assert {:ok, _} = Program.forward(program, inputs, timeout: 5000)
      
      # Should timeout on very short timeout
      assert {:error, :timeout} = Program.forward(program, inputs, timeout: 1)
    end
    
    test "supports correlation_id option", %{predict: program} do
      inputs = %{question: "test"}
      correlation_id = "test-#{System.unique_integer()}"
      
      # Should accept correlation_id without error
      assert {:ok, _} = Program.forward(program, inputs, correlation_id: correlation_id)
    end
    
    test "maintains backward compatibility", %{predict: program} do
      inputs = %{question: "test"}
      
      # forward/2 should still work
      assert {:ok, _} = Program.forward(program, inputs)
    end
  end
  
  describe "program introspection contract" do
    test "program_type/1 classifies correctly", %{predict: predict, optimized: optimized} do
      assert Program.program_type(predict) == :predict
      assert Program.program_type(optimized) == :optimized
      assert Program.program_type("invalid") == :unknown
    end
    
    test "safe_program_info/1 returns required fields", %{predict: predict} do
      info = Program.safe_program_info(predict)
      
      assert %{
        type: :predict,
        name: :Predict,
        has_demos: false,
        signature: TestSignature
      } = info
    end
    
    test "has_demos?/1 detects demonstrations correctly", %{predict: predict, optimized: optimized} do
      refute Program.has_demos?(predict)
      assert Program.has_demos?(optimized)
    end
  end
end
```

## Phase 2: Client Contract Stabilization (Day 1-2)

### 2.1 Client Response Format Stabilization

**File:** `lib/dspex/client.ex`

**Current Issue:** Response format may vary between providers

**Required Implementation:**
```elixir
# Add response format normalization
defp normalize_response(response, provider) do
  case provider do
    provider when provider in [:gemini] ->
      case parse_gemini_response(response) do
        {:ok, normalized} -> {:ok, ensure_stable_format(normalized)}
        error -> error
      end
    
    provider when provider in [:openai] ->
      case parse_openai_response(response) do
        {:ok, normalized} -> {:ok, ensure_stable_format(normalized)}
        error -> error
      end
  end
end

# Ensure response always has expected structure for SIMBA
defp ensure_stable_format(response) do
  %{
    choices: response.choices |> Enum.map(&ensure_choice_format/1)
  }
end

defp ensure_choice_format(choice) do
  %{
    message: %{
      role: get_in(choice, [:message, :role]) || "assistant",
      content: get_in(choice, [:message, :content]) || ""
    }
  }
end
```

### 2.2 Error Categorization

**File:** `lib/dspex/client.ex`

**Add Consistent Error Types:**
```elixir
@type error_reason ::
  :timeout | :network_error | :api_error | :rate_limited |
  :invalid_messages | :provider_not_configured | :no_api_key

# Ensure all error paths return categorized errors
defp categorize_client_error(error) do
  case error do
    %{reason: :timeout} -> :timeout
    %{reason: :closed} -> :network_error
    %{reason: :econnrefused} -> :network_error
    %HTTPoison.Error{reason: :timeout} -> :timeout
    %HTTPoison.Error{reason: :nxdomain} -> :network_error
    _ -> :api_error
  end
end
```

### 2.3 Correlation ID Preservation

**File:** `lib/dspex/client.ex`

**Enhance Error Handling:**
```elixir
defp handle_client_error(error, correlation_id, provider) do
  categorized_error = categorize_client_error(error)
  
  # Emit telemetry with correlation_id preserved
  :telemetry.execute(
    [:dspex, :client, :request, :exception],
    %{},
    %{
      provider: provider,
      error_type: categorized_error,
      correlation_id: correlation_id
    }
  )
  
  {:error, categorized_error}
end
```

## Phase 3: Service Integration Contract (Day 2)

### 3.1 ConfigManager Enhancement

**File:** `lib/dspex/services/config_manager.ex`

**Current Issue:** get_with_default/2 may not handle all SIMBA paths

**Required Implementation:**
```elixir
@doc """
Get configuration with default value - SIMBA critical function.
Handles nested paths like [:prediction, :default_provider].
"""
@spec get_with_default([atom()] | atom(), term()) :: term()
def get_with_default(path, default) when is_list(path) do
  case get_from_fallback_config(path) do
    {:ok, value} -> value
    {:error, _} -> default
  end
end

def get_with_default(key, default) when is_atom(key) do
  get_with_default([key], default)
end

# Enhance fallback config to include SIMBA-required paths
defp get_default_config do
  base_config = %{
    providers: %{
      gemini: %{
        api_key: {:system, "GEMINI_API_KEY"},
        base_url: "https://generativelanguage.googleapis.com/v1beta/models",
        default_model: "gemini-2.5-flash-preview-05-20",
        timeout: 30_000
      },
      openai: %{
        api_key: {:system, "OPENAI_API_KEY"},
        base_url: "https://api.openai.com/v1",
        default_model: "gpt-4",
        timeout: 30_000
      }
    },
    prediction: %{
      default_provider: :gemini,  # SIMBA depends on this
      default_temperature: 0.7,
      default_max_tokens: 150
    },
    teleprompters: %{
      simba: %{
        default_instruction_model: :openai,  # SIMBA instruction generation
        default_evaluation_model: :gemini,   # SIMBA evaluation
        max_concurrent_operations: 20,
        default_timeout: 60_000
      }
    }
  }
  
  # Merge with Mix config for environment-specific overrides
  mix_config = Application.get_env(:dspex, :providers, %{})
  mix_prediction_config = Application.get_env(:dspex, :prediction, %{})
  mix_teleprompter_config = Application.get_env(:dspex, :teleprompters, %{})
  
  base_config
  |> put_in([:providers], Map.merge(base_config.providers, mix_config))
  |> put_in([:prediction], Map.merge(base_config.prediction, mix_prediction_config))
  |> put_in([:teleprompters], Map.merge(base_config.teleprompters, mix_teleprompter_config))
end
```

### 3.2 Service Lifecycle Conflict Resolution

**File:** `lib/dspex/services/config_manager.ex`

**Issue:** SIMBA may try to start services that are already running

**Required Implementation:**
```elixir
@impl GenServer
def init(_opts) do
  # Enhanced initialization with conflict resolution
  case wait_for_foundation() do
    :ok ->
      # Foundation available, proceed with setup
      setup_dspex_config()
      setup_circuit_breakers()
      
      # Register with Foundation's service registry safely
      case Foundation.ServiceRegistry.register(:production, :config_server, self()) do
        :ok -> 
          {:ok, %{fallback_config: get_default_config(), foundation_available: true}}
        {:error, :already_registered} ->
          # Another instance already registered, operate in fallback mode
          {:ok, %{fallback_config: get_default_config(), foundation_available: false}}
        {:error, reason} ->
          Logger.warning("Foundation registration failed: #{inspect(reason)}, using fallback")
          {:ok, %{fallback_config: get_default_config(), foundation_available: false}}
      end
      
    :timeout ->
      # Foundation not available, use pure fallback mode
      Logger.info("Foundation not available, ConfigManager running in fallback mode")
      {:ok, %{fallback_config: get_default_config(), foundation_available: false}}
  end
end

# Enhanced Foundation waiting with timeout
defp wait_for_foundation do
  wait_for_foundation(5000) # 5 second timeout
end

defp wait_for_foundation(timeout) when timeout <= 0, do: :timeout

defp wait_for_foundation(timeout) do
  case Foundation.available?() do
    true -> :ok
    false ->
      Process.sleep(100)
      wait_for_foundation(timeout - 100)
  end
end
```

### 3.3 TelemetrySetup Enhancement

**File:** `lib/dspex/services/telemetry_setup.ex`

**Add SIMBA Telemetry Events:**
```elixir
defp setup_dspex_telemetry do
  # Enhanced event list including SIMBA events
  events = [
    [:dspex, :predict, :start],
    [:dspex, :predict, :stop],
    [:dspex, :predict, :exception],
    [:dspex, :client, :request, :start],
    [:dspex, :client, :request, :stop],
    [:dspex, :client, :request, :exception],
    [:dspex, :program, :forward, :start],
    [:dspex, :program, :forward, :stop],
    [:dspex, :teleprompter, :bootstrap, :start],
    [:dspex, :teleprompter, :bootstrap, :stop],
    # SIMBA-specific events
    [:dspex, :teleprompter, :simba, :start],
    [:dspex, :teleprompter, :simba, :stop],
    [:dspex, :teleprompter, :simba, :optimization, :start],
    [:dspex, :teleprompter, :simba, :optimization, :stop],
    [:dspex, :teleprompter, :simba, :instruction, :start],
    [:dspex, :teleprompter, :simba, :instruction, :stop]
  ]
  
  # Rest of implementation...
end
```

## Phase 4: OptimizedProgram Contract Enhancement (Day 2-3)

### 4.1 Metadata Support Validation

**File:** `lib/dspex/optimized_program.ex`

**Ensure Unlimited Metadata Support:**
```elixir
@doc """
Create a new optimized program wrapper with SIMBA metadata support.
SIMBA stores optimization results, instructions, and Bayesian optimization data.
"""
@spec new(struct(), [DSPEx.Example.t()], map()) :: t()
def new(program, demos, metadata \\ %{}) do
  # Validate metadata is serializable for SIMBA
  validated_metadata = validate_simba_metadata(metadata)
  
  %__MODULE__{
    program: program,
    demos: demos,
    metadata: Map.merge(
      %{
        optimized_at: DateTime.utc_now(),
        demo_count: length(demos)
      },
      validated_metadata
    )
  }
end

# SIMBA metadata validation
defp validate_simba_metadata(metadata) when is_map(metadata) do
  # Ensure SIMBA metadata fields are preserved
  required_simba_fields = [
    :optimization_method,
    :instruction,
    :optimization_score,
    :optimization_stats,
    :bayesian_trials,
    :best_configuration
  ]
  
  # Keep all SIMBA fields, sanitize others
  Enum.reduce(metadata, %{}, fn {key, value}, acc ->
    cond do
      key in required_simba_fields ->
        Map.put(acc, key, value)
      is_atom(key) and is_serializable?(value) ->
        Map.put(acc, key, value)
      true ->
        # Skip non-serializable values but log warning
        Logger.debug("Skipping non-serializable metadata field: #{inspect(key)}")
        acc
    end
  end)
end

defp validate_simba_metadata(_), do: %{}

defp is_serializable?(value) do
  try do
    Jason.encode!(value)
    true
  rescue
    _ -> false
  end
end
```

### 4.2 Native Support Detection

**File:** `lib/dspex/optimized_program.ex`

**Add SIMBA Strategy Functions:**
```elixir
@doc """
Check if a program natively supports demonstrations.
Used by SIMBA to determine wrapping strategy.
"""
@spec supports_native_demos?(struct()) :: boolean()
def supports_native_demos?(program) when is_struct(program) do
  Map.has_key?(program, :demos)
end

def supports_native_demos?(_), do: false

@doc """
Check if a program natively supports instructions.
Used by SIMBA to determine enhancement strategy.
"""
@spec supports_native_instruction?(struct()) :: boolean()
def supports_native_instruction?(program) when is_struct(program) do
  Map.has_key?(program, :instruction)
end

def supports_native_instruction?(_), do: false

@doc """
Determine SIMBA enhancement strategy for a program.
"""
@spec simba_enhancement_strategy(struct()) :: :native_full | :native_demos | :wrap_optimized
def simba_enhancement_strategy(program) when is_struct(program) do
  cond do
    supports_native_demos?(program) and supports_native_instruction?(program) ->
      :native_full
    supports_native_demos?(program) ->
      :native_demos
    true ->
      :wrap_optimized
  end
end

def simba_enhancement_strategy(_), do: :wrap_optimized
```

## Phase 5: Teleprompter Contract Fixes (Day 3)

### 5.1 BootstrapFewShot Empty Demo Handling

**File:** `lib/dspex/teleprompter/bootstrap_fewshot.ex`

**Current Issue:** Crashes when no demos are generated successfully

**Required Fix:**
```elixir
defp select_best_demonstrations(quality_demos, config) do
  # Sort by quality score (highest first) and take the best ones
  selected = quality_demos
    |> Enum.sort_by(fn demo -> demo.data[:__quality_score] || 0.0 end, :desc)
    |> Enum.take(config.max_bootstrapped_demos)

  if config.progress_callback do
    progress = %{
      phase: :demonstration_selection,
      selected_count: length(selected),
      total_candidates: length(quality_demos),
      quality_threshold: config.quality_threshold
    }

    config.progress_callback.(progress)
  end

  # CRITICAL FIX: Always return selected demonstrations (even if empty)
  # This allows SIMBA to handle empty demo scenarios gracefully
  {:ok, selected}
end

defp create_optimized_student(student, selected_demos, config) do
  # Enhanced to handle empty demo lists
  optimized = case selected_demos do
    [] ->
      # No demos available, return enhanced student with metadata only
      case student do
        %{demos: _} ->
          %{student | demos: []}
        _ ->
          DSPEx.OptimizedProgram.new(student, [], %{
            teleprompter: :bootstrap_fewshot,
            quality_threshold: config.quality_threshold,
            optimization_type: :bootstrap_few_shot,
            demo_generation_failed: true,
            fallback_reason: "No quality demonstrations generated"
          })
      end
    
    demos ->
      # Normal path with demonstrations
      case student do
        %{demos: _} ->
          %{student | demos: demos}
        _ ->
          DSPEx.OptimizedProgram.new(student, demos, %{
            teleprompter: :bootstrap_fewshot,
            quality_threshold: config.quality_threshold,
            optimization_type: :bootstrap_few_shot,
            demo_count: length(demos)
          })
      end
  end

  {:ok, optimized}
end
```

### 5.2 Progress Callback Integration

**File:** `lib/dspex/teleprompter/bootstrap_fewshot.ex`

**Enhance for SIMBA Integration:**
```elixir
defp generate_bootstrap_candidates(teacher, trainset, config) do
  total_examples = length(trainset)
  
  # SIMBA-compatible progress reporting
  emit_progress = fn completed ->
    if config.progress_callback do
      progress = %{
        phase: :bootstrap_generation,
        completed: completed,
        total: total_examples,
        percentage: (completed / total_examples * 100),
        correlation_id: get_correlation_id(config),
        teacher: teacher_name(teacher)
      }
      
      config.progress_callback.(progress)
    end
  end

  # Generate bootstrap demonstrations with enhanced progress tracking
  candidates = trainset
    |> Stream.with_index()
    |> Task.async_stream(
      fn {example, index} ->
        result = generate_single_demonstration(teacher, example, config)
        
        # Report progress for every example (SIMBA needs granular updates)
        emit_progress.(index + 1)
        
        case result do
          {:ok, demo} -> {:ok, {example, demo}}
          error -> error
        end
      end,
      max_concurrency: config.max_concurrency,
      timeout: config.timeout,
      on_timeout: :kill_task
    )
    |> Stream.filter(&match?({:ok, {:ok, _}}, &1))
    |> Stream.map(fn {:ok, {:ok, pair}} -> pair end)
    |> Enum.to_list()

  # Always return candidates list (even if empty) for SIMBA compatibility
  {:ok, candidates}
end

# Helper to extract correlation_id from config
defp get_correlation_id(config) do
  case config do
    %{correlation_id: id} -> id
    _ -> "bootstrap-#{System.unique_integer()}"
  end
end
```

## Phase 6: Contract Validation Tests (Day 3)

### 6.1 Comprehensive Contract Test Suite

**File:** `test/integration/simba_contract_validation_test.exs`

```elixir
defmodule DSPEx.SIMBAContractValidationTest do
  @moduledoc """
  Validates all APIs that SIMBA depends on work correctly.
  This test suite ensures the DSPEx-SIMBA contract is fulfilled.
  """
  
  use ExUnit.Case, async: false
  
  alias DSPEx.{Program, Predict, Client, Example, OptimizedProgram}
  alias DSPEx.Services.ConfigManager
  alias DSPEx.Teleprompter.BootstrapFewShot
  
  defmodule SIMBATestSignature do
    use DSPEx.Signature, "question -> answer"
  end
  
  describe "SIMBA Core Program Contract" do
    test "Program.forward/3 with timeout and correlation_id" do
      program = %Predict{signature: SIMBATestSignature, client: :test}
      inputs = %{question: "Contract test"}
      correlation_id = "simba-contract-#{System.unique_integer()}"
      
      # Test timeout option
      assert {:ok, outputs} = Program.forward(program, inputs, timeout: 5000)
      assert Map.has_key?(outputs, :answer)
      
      # Test correlation_id option
      assert {:ok, outputs} = Program.forward(program, inputs, 
        correlation_id: correlation_id, timeout: 5000)
      assert Map.has_key?(outputs, :answer)
      
      # Test very short timeout should fail
      assert {:error, :timeout} = Program.forward(program, inputs, timeout: 1)
    end
    
    test "Program introspection functions" do
      student = %Predict{signature: SIMBATestSignature, client: :test}
      demo = %Example{data: %{question: "test", answer: "response"}, input_keys: MapSet.new([:question])}
      optimized = OptimizedProgram.new(student, [demo])
      
      # Test program_type/1
      assert Program.program_type(student) == :predict
      assert Program.program_type(optimized) == :optimized
      assert Program.program_type("invalid") == :unknown
      
      # Test safe_program_info/1
      info = Program.safe_program_info(student)
      assert %{
        type: :predict,
        name: :Predict,
        has_demos: false,
        signature: SIMBATestSignature
      } = info
      
      optimized_info = Program.safe_program_info(optimized)
      assert optimized_info.has_demos == true
      assert optimized_info.type == :optimized
      
      # Test has_demos?/1
      refute Program.has_demos?(student)
      assert Program.has_demos?(optimized)
    end
  end
  
  describe "SIMBA Client Contract" do
    test "Client.request/2 response format stability" do
      messages = [%{role: "user", content: "SIMBA instruction generation test"}]
      
      case Client.request(messages, %{provider: :gemini}) do
        {:ok, response} ->
          # Validate structure SIMBA expects
          assert %{choices: choices} = response
          assert is_list(choices)
          assert length(choices) > 0
          
          [first_choice | _] = choices
          assert %{message: %{content: content}} = first_choice
          assert is_binary(content)
          
        {:error, reason} ->
          # Validate error is categorized as SIMBA expects
          assert reason in [:timeout, :network_error, :api_error, :rate_limited, :no_api_key]
      end
    end
    
    test "Client error categorization" do
      # Test with invalid messages (should get categorized error)
      invalid_messages = ["not", "a", "proper", "message", "list"]
      
      assert {:error, reason} = Client.request(invalid_messages, %{provider: :test})
      assert is_atom(reason)
    end
  end
  
  describe "SIMBA Configuration Contract" do
    test "ConfigManager.get_with_default/2 for SIMBA paths" do
      # Test critical SIMBA configuration paths
      default_provider = ConfigManager.get_with_default([:prediction, :default_provider], :gemini)
      assert default_provider in [:gemini, :openai, :anthropic]
      
      # Test teleprompter config
      instruction_model = ConfigManager.get_with_default(
        [:teleprompters, :simba, :default_instruction_model], 
        :openai
      )
      assert is_atom(instruction_model)
      
      # Test fallback behavior
      nonexistent = ConfigManager.get_with_default([:nonexistent, :path], :fallback_value)
      assert nonexistent == :fallback_value
    end
  end
  
  describe "SIMBA OptimizedProgram Contract" do
    test "OptimizedProgram metadata support" do
      student = %Predict{signature: SIMBATestSignature, client: :test}
      demos = [%Example{data: %{q: "test", a: "answer"}, input_keys: MapSet.new([:q])}]
      
      # Test SIMBA metadata storage
      simba_metadata = %{
        optimization_method: :simba,
        instruction: "Test instruction for SIMBA",
        optimization_score: 0.85,
        optimization_stats: %{
          trials: 25,
          best_trial: 15,
          convergence_iteration: 20
        },
        bayesian_trials: [
          %{trial: 1, score: 0.65},
          %{trial: 2, score: 0.78}
        ]
      }
      
      optimized = OptimizedProgram.new(student, demos, simba_metadata)
      
      # Validate metadata preservation
      assert optimized.metadata.optimization_method == :simba
      assert optimized.metadata.instruction == "Test instruction for SIMBA"
      assert optimized.metadata.optimization_score == 0.85
      assert optimized.metadata.optimization_stats.trials == 25
      assert length(optimized.metadata.bayesian_trials) == 2
      
      # Validate automatic metadata
      assert %DateTime{} = optimized.metadata.optimized_at
      assert optimized.metadata.demo_count == 1
    end
    
    test "native support detection" do
      basic_program = %Predict{signature: SIMBATestSignature, client: :test}
      demo_program = %Predict{signature: SIMBATestSignature, client: :test, demos: []}
      
      # Test detection functions
      assert OptimizedProgram.supports_native_demos?(demo_program)
      refute OptimizedProgram.supports_native_demos?(basic_program)
      
      # Neither supports native instructions (would need custom program type)
      refute OptimizedProgram.supports_native_instruction?(demo_program)
      refute OptimizedProgram.supports_native_instruction?(basic_program)
      
      # Test strategy selection
      assert OptimizedProgram.simba_enhancement_strategy(demo_program) == :native_demos
      assert OptimizedProgram.simba_enhancement_strategy(basic_program) == :wrap_optimized
    end
  end
  
  describe "SIMBA Teleprompter Contract" do
    test "BootstrapFewShot handles empty demo scenarios" do
      student = %Predict{signature: SIMBATestSignature, client: :test}
      teacher = %Predict{signature: SIMBATestSignature, client: :test}
      
      # Empty trainset should not crash
      empty_trainset = []
      metric_fn = fn _example, _prediction -> 1.0 end
      
      teleprompter = BootstrapFewShot.new(max_bootstrapped_demos: 3)
      
      # Should handle empty trainset gracefully
      result = teleprompter.compile(student, teacher, empty_trainset, metric_fn)
      
      case result do
        {:ok, optimized} ->
          # Should return a program even with no demos
          assert is_struct(optimized)
          
        {:error, reason} ->
          # Acceptable errors for empty trainset
          assert reason in [:invalid_or_empty_trainset, :no_successful_bootstrap_candidates]
      end
    end
  end
end
```

### 6.2 SIMBA Integration Smoke Test

**File:** `test/integration/simba_integration_smoke_test.exs`

```elixir
defmodule DSPEx.SIMBAIntegrationSmokeTest do
  @moduledoc """
  Smoke test that validates the essential SIMBA workflow can execute.
  This simulates the core SIMBA optimization loop without full implementation.
  """
  
  use ExUnit.Case, async: false
  
  alias DSPEx.{Program, Predict, Example, OptimizedProgram}
  alias DSPEx.Services.ConfigManager
  
  defmodule SIMBAWorkflowSignature do
    use DSPEx.Signature, "question -> answer, reasoning"
  end
  
  test "minimal SIMBA workflow compatibility" do
    # Step 1: Create student and teacher programs
    student = %Predict{signature: SIMBAWorkflowSignature, client: :gemini}
    teacher = %Predict{signature: SIMBAWorkflowSignature, client: :openai}
    
    # Step 2: Create minimal training set
    trainset = [
      %Example{
        data: %{
          question: "What is 2+2?",
          answer: "4", 
          reasoning: "Simple addition: 2 + 2 = 4"
        },
        input_keys: MapSet.new([:question])
      },
      %Example{
        data: %{
          question: "What is 3+3?",
          answer: "6",
          reasoning: "Simple addition: 3 + 3 = 6"
        },
        input_keys: MapSet.new([:question])
      }
    ]
    
    # Step 3: Test teacher demonstration generation (SIMBA bootstrap step)
    teacher_inputs = Example.inputs(List.first(trainset))
    
    case Program.forward(teacher, teacher_inputs) do
      {:ok, teacher_prediction} ->
        # Teacher should generate reasoning + answer
        assert Map.has_key?(teacher_prediction, :answer)
        assert Map.has_key?(teacher_prediction, :reasoning)
        
        # Step 4: Create demonstration from teacher output
        demo_data = Map.merge(teacher_inputs, teacher_prediction)
        demo = Example.new(demo_data)
        demo = Example.with_inputs(demo, [:question])
        
        assert Example.inputs(demo) == teacher_inputs
        teacher_outputs = Example.outputs(demo)
        assert Map.has_key?(teacher_outputs, :answer)
        assert Map.has_key?(teacher_outputs, :reasoning)
        
      {:error, _} ->
        # Teacher failed, create mock demo for testing
        demo = %Example{
          data: %{
            question: "What is 2+2?",
            answer: "4",
            reasoning: "Mock reasoning for testing"
          },
          input_keys: MapSet.new([:question])
        }
    end
    
    # Step 5: Test instruction generation (simulated)
    instruction_messages = [%{
      role: "user",
      content: """
      Create an instruction for answering mathematical questions with reasoning.
      Input: question
      Output: answer, reasoning
      
      Be precise and show your work step by step.
      """
    }]
    
    instruction = case DSPEx.Client.request(instruction_messages, %{provider: :openai}) do
      {:ok, response} ->
        response.choices
        |> List.first()
        |> get_in([:message, :content])
        |> String.trim()
        
      {:error, _} ->
        # Fallback instruction for testing
        "Answer the mathematical question step by step, showing your reasoning."
    end
    
    assert is_binary(instruction)
    assert String.length(instruction) > 10
    
    # Step 6: Test program enhancement (SIMBA wrapping strategy)
    enhancement_strategy = OptimizedProgram.simba_enhancement_strategy(student)
    
    enhanced_program = case enhancement_strategy do
      :native_demos ->
        %{student | demos: [demo]}
        
      :wrap_optimized ->
        OptimizedProgram.new(student, [demo], %{
          optimization_method: :simba_smoke_test,
          instruction: instruction,
          enhancement_strategy: enhancement_strategy
        })
        
      _ ->
        OptimizedProgram.new(student, [demo], %{instruction: instruction})
    end
    
    # Step 7: Test enhanced program execution
    test_input = %{question: "What is 5+5?"}
    
    case Program.forward(enhanced_program, test_input) do
      {:ok, result} ->
        assert Map.has_key?(result, :answer)
        # May or may not have reasoning depending on implementation
        
      {:error, reason} ->
        # Some errors are acceptable in smoke test
        assert reason in [:timeout, :network_error, :api_error, :no_api_key]
    end
    
    # Step 8: Validate program introspection works
    program_info = Program.safe_program_info(enhanced_program)
    assert program_info.type in [:predict, :optimized]
    assert program_info.has_demos == true
    
    # Step 9: Test configuration access
    default_provider = ConfigManager.get_with_default([:prediction, :default_provider], :gemini)
    assert is_atom(default_provider)
  end
end
```

## Implementation Timeline and Priorities

### Day 1: Critical Foundation
- ✅ Program.forward/3 implementation
- ✅ Program introspection functions
- ✅ Basic contract validation tests
- ✅ Client response format stabilization

### Day 2: Service Integration
- ✅ ConfigManager enhancement for SIMBA paths
- ✅ Service lifecycle conflict resolution
- ✅ TelemetrySetup SIMBA event support
- ✅ OptimizedProgram metadata validation

### Day 3: Completion and Validation
- ✅ BootstrapFewShot empty demo handling
- ✅ Comprehensive contract test suite
- ✅ SIMBA integration smoke test
- ✅ Performance baseline validation

## Success Criteria

### Contract Implementation Complete When:

1. **All contract tests pass** - Every API SIMBA depends on works
2. **Integration smoke test passes** - Core SIMBA workflow executes
3. **No regressions** - Existing tests continue to pass
4. **Service conflicts resolved** - Multiple service starts work
5. **Error recovery validated** - All error scenarios handled

### Ready for SIMBA Integration When:

1. **Contract specification fully implemented**
2. **All validation tests passing consistently**
3. **Performance baselines established**
4. **Documentation updated**
5. **Team confident in API stability**

This roadmap transforms the current broken contract situation into a solid foundation ready for SIMBA implementation.
