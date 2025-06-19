# DSPEx Behaviours Integration Status & Mocking Strategy

## Current State Analysis

Based on the analysis of the DSPEx codebase, here's the current status of behaviours and mocking infrastructure as of the latest codebase review:

### ✅ Already Implemented Behaviours

#### 1. DSPEx.Program (COMPLETE)
**Location**: `lib/dspex/program.ex`
**Status**: ✅ Fully implemented with proper callbacks

```elixir
@callback forward(program(), inputs()) :: {:ok, outputs()} | {:error, term()}
@callback forward(program(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}
@optional_callbacks forward: 3
```

**Implementing Modules**:
- Examples in `examples/sample_programs.ex` (4 implementations)
- `lib/dspex/predict_structured.ex`
- Various teleprompter and strategy modules

#### 2. DSPEx.Teleprompter (COMPLETE)
**Location**: `lib/dspex/teleprompter.ex`
**Status**: ✅ Fully implemented with proper callbacks

```elixir
@callback compile(
  student :: program(),
  teacher :: program(),
  trainset :: trainset(),
  metric_fn :: metric_fn(),
  opts :: opts()
) :: compilation_result()
```

**Implementing Modules**:
- `lib/dspex/teleprompter/bootstrap_fewshot.ex`
- `lib/dspex/teleprompter/beacon.ex`
- `lib/dspex/teleprompter/simba.ex`
- Strategy modules under `lib/dspex/teleprompter/simba/strategy/`

#### 3. DSPEx.Signature (COMPLETE)
**Location**: `lib/dspex/signature.ex`
**Status**: ✅ Fully implemented with proper callbacks

```elixir
@callback instructions() :: String.t()
@callback input_fields() :: [atom()]
@callback output_fields() :: [atom()]
@callback fields() :: [atom()]
```

#### 4. DSPEx.Teleprompter.SIMBA.Strategy (COMPLETE)
**Location**: `lib/dspex/teleprompter/simba/strategy.ex`
**Status**: ✅ Fully implemented

```elixir
@callback apply(Bucket.t(), struct(), map()) :: {:ok, Bucket.t()} | {:error, term()}
@callback applicable?(Bucket.t(), map()) :: boolean()
```

### ❌ Missing Critical Behaviours (HIGH PRIORITY)

#### 1. DSPEx.Client (MISSING)
**Location**: `lib/dspex/client.ex`
**Current Status**: ❌ **NO BEHAVIOUR DEFINED**
**Impact**: **CRITICAL** - Cannot mock client layer, major testing gap

**Required Implementation**:
```elixir
defmodule DSPEx.Client do
  @callback request(messages :: [message()], opts :: request_options()) :: 
    {:ok, response()} | {:error, error_reason()}
  
  @callback request(client_id :: atom(), messages :: [message()], opts :: request_options()) :: 
    {:ok, response()} | {:error, error_reason()}
end
```

#### 2. DSPEx.Adapter (MISSING)
**Location**: `lib/dspex/adapter.ex`
**Current Status**: ❌ **NO BEHAVIOUR DEFINED**
**Impact**: **CRITICAL** - Cannot mock adapter layer, breaks contract-first testing

**Required Implementation**:
```elixir
defmodule DSPEx.Adapter do
  @callback format_messages(signature :: signature(), inputs :: inputs()) :: 
    {:ok, messages()} | {:error, atom()}
  
  @callback parse_response(signature :: signature(), response :: api_response()) :: 
    {:ok, outputs()} | {:error, atom()}
end
```

#### 3. DSPEx.Evaluator (MISSING)
**Location**: `lib/dspex/evaluate.ex`
**Current Status**: ❌ **NO BEHAVIOUR DEFINED**
**Impact**: **HIGH** - Cannot mock evaluation for teleprompter testing

**Required Implementation**:
```elixir
defmodule DSPEx.Evaluator do
  @callback run(program :: DSPEx.Program.t(), examples :: [DSPEx.Example.t()], 
                metric_fn :: function(), opts :: evaluation_options()) :: 
    {:ok, evaluation_result()} | {:error, term()}
  
  @callback run_local(program :: DSPEx.Program.t(), examples :: [DSPEx.Example.t()], 
                      metric_fn :: function(), opts :: evaluation_options()) :: 
    {:ok, evaluation_result()} | {:error, term()}
  
  @callback run_distributed(program :: DSPEx.Program.t(), examples :: [DSPEx.Example.t()], 
                            metric_fn :: function(), opts :: evaluation_options()) :: 
    {:ok, evaluation_result()} | {:error, term()}
end
```

### 🔄 Current Mocking Infrastructure Status

#### ✅ What's Working

1. **Mox Dependency**: ✅ Already added to `mix.exs`
2. **Mock Helpers**: ✅ Comprehensive `MockHelpers` module exists
3. **Test Infrastructure**: ✅ Sophisticated test setup with clean environment validation
4. **Mock Client Manager**: ✅ `DSPEx.MockClientManager` provides client mocking
5. **Ad-hoc Program Mocks**: ✅ Many tests use inline `MockProgram` modules

#### ❌ What's Missing

1. **Formal Mox Setup**: ❌ No `Mox.defmock` calls in `test_helper.exs`
2. **Behaviour-Based Mocking**: ❌ Not using `@behaviour` for systematic mocking
3. **Centralized Mock Definitions**: ❌ Mock implementations scattered across test files
4. **Contract Enforcement**: ❌ No systematic verification that implementations follow behaviours

## Integration Strategy

### Phase 1: Define Missing Behaviours (Week 1)

#### 1.1 Client Behaviour
```elixir
# lib/dspex/client.ex - Add behaviour definition
defmodule DSPEx.Client do
  @type message :: %{role: String.t(), content: String.t()}
  @type request_options :: %{
    optional(:provider) => atom(),
    optional(:model) => String.t(),
    optional(:temperature) => float(),
    optional(:max_tokens) => pos_integer(),
    optional(:correlation_id) => String.t(),
    optional(:timeout) => pos_integer()
  }
  @type response :: %{choices: [%{message: message()}]}
  @type error_reason :: :timeout | :network_error | :invalid_response | :api_error
  
  @callback request(messages :: [message()]) :: {:ok, response()} | {:error, error_reason()}
  @callback request(messages :: [message()], opts :: request_options()) :: 
    {:ok, response()} | {:error, error_reason()}
  @callback request(client_id :: atom(), messages :: [message()], opts :: request_options()) :: 
    {:ok, response()} | {:error, error_reason()}

  # Keep existing implementation but add @behaviour DSPEx.Client
  # to concrete client implementations
end
```

#### 1.2 Adapter Behaviour
```elixir
# lib/dspex/adapter.ex - Add behaviour definition
defmodule DSPEx.Adapter do
  @type signature :: module()
  @type inputs :: map()
  @type outputs :: map()
  @type messages :: [DSPEx.Client.message()]
  @type api_response :: DSPEx.Client.response()

  @callback format_messages(signature :: signature(), inputs :: inputs()) :: 
    {:ok, messages()} | {:error, atom()}
  @callback parse_response(signature :: signature(), response :: api_response()) :: 
    {:ok, outputs()} | {:error, atom()}

  # Keep existing implementation as default behaviour
end
```

#### 1.3 Evaluator Behaviour
```elixir
# lib/dspex/evaluate.ex - Add behaviour definition
defmodule DSPEx.Evaluator do
  @type evaluation_result :: %{
    score: float(),
    stats: %{
      total_examples: non_neg_integer(),
      successful: non_neg_integer(),
      failed: non_neg_integer(),
      duration_ms: non_neg_integer(),
      success_rate: float(),
      throughput: float(),
      errors: [term()]
    }
  }
  @type evaluation_options :: keyword()

  @callback run(program :: DSPEx.Program.t(), examples :: [DSPEx.Example.t()], 
                metric_fn :: function(), opts :: evaluation_options()) :: 
    {:ok, evaluation_result()} | {:error, term()}

  # Add @behaviour DSPEx.Evaluator to the module itself
end
```

### Phase 2: Implement Centralized Mocking (Week 1-2)

#### 2.1 Update test_helper.exs
```elixir
# test/test_helper.exs - Add centralized mock definitions
ExUnit.start()

# Define all behaviour-based mocks
Mox.defmock(DSPEx.MockClient, for: DSPEx.Client)
Mox.defmock(DSPEx.MockAdapter, for: DSPEx.Adapter) 
Mox.defmock(DSPEx.MockEvaluator, for: DSPEx.Evaluator)
Mox.defmock(DSPEx.MockProgram, for: DSPEx.Program)
Mox.defmock(DSPEx.MockTeleprompter, for: DSPEx.Teleprompter)

# Load existing test support files
Code.require_file("support/mock_helpers.exs", __DIR__)
Code.require_file("support/test_helpers.exs", __DIR__)
Code.require_file("support/beacon_test_mocks.exs", __DIR__)
Code.require_file("support/mock_provider.ex", __DIR__)

# New centralized mock support
Code.require_file("support/behaviour_mocks.exs", __DIR__)

# Configure existing settings...
```

#### 2.2 Create Centralized Mock Behaviors
```elixir
# test/support/behaviour_mocks.exs
defmodule DSPEx.BehaviourMocks do
  @moduledoc """
  Centralized mock behaviors and helpers for contract-first testing.
  
  This module provides pre-configured mock implementations that follow
  the established behaviours, making tests more reliable and reducing
  boilerplate.
  """
  
  import Mox
  
  def setup_standard_client_mock(provider \\ :openai) do
    expect(DSPEx.MockClient, :request, fn messages, _opts ->
      # Standard success response
      content = generate_mock_response(messages)
      {:ok, %{choices: [%{message: %{role: "assistant", content: content}}]}}
    end)
  end
  
  def setup_standard_adapter_mock() do
    expect(DSPEx.MockAdapter, :format_messages, fn _signature, inputs ->
      # Convert inputs to simple message format
      content = Map.values(inputs) |> Enum.join(", ")
      {:ok, [%{role: "user", content: content}]}
    end)
    
    expect(DSPEx.MockAdapter, :parse_response, fn signature, response ->
      # Extract first output field and populate with response content
      output_fields = signature.output_fields()
      first_field = List.first(output_fields)
      content = get_in(response, [:choices, Access.at(0), :message, :content])
      {:ok, %{first_field => content}}
    end)
  end
  
  def setup_standard_evaluator_mock(score \\ 0.8) do
    expect(DSPEx.MockEvaluator, :run, fn _program, examples, _metric_fn, _opts ->
      count = length(examples)
      {:ok, %{
        score: score,
        stats: %{
          total_examples: count,
          successful: count,
          failed: 0,
          duration_ms: 1000,
          success_rate: score,
          throughput: count / 1.0,
          errors: []
        }
      }}
    end)
  end
  
  def setup_standard_program_mock(outputs \\ %{answer: "mocked response"}) do
    expect(DSPEx.MockProgram, :forward, fn _program, _inputs, _opts ->
      {:ok, outputs}
    end)
  end
  
  def setup_failing_client_mock(error \\ :network_error) do
    expect(DSPEx.MockClient, :request, fn _messages, _opts ->
      {:error, error}
    end)
  end
  
  # Helper to generate contextual mock responses
  defp generate_mock_response(messages) do
    last_message = List.last(messages)
    content = Map.get(last_message, :content, "")
    
    cond do
      String.contains?(content, "2+2") -> "4"
      String.contains?(content, "capital") -> "The capital is..."
      String.contains?(content, "summarize") -> "Summary: ..."
      true -> "Mock response for: #{String.slice(content, 0, 50)}"
    end
  end
end
```

### Phase 3: Refactor Existing Tests (Week 2-3)

#### 3.1 Migration Strategy
1. **Identify affected tests**: All tests using inline mocks or `MockClient` implementations
2. **Gradual replacement**: Replace ad-hoc mocks with behaviour-based mocks
3. **Verification**: Ensure all tests pass with new mocking approach

#### 3.2 Example Test Migration
**Before (Current approach)**:
```elixir
# Scattered across tests
defmodule MockClient do
  def request(messages) do
    {:ok, %{choices: [%{message: %{content: "4"}}]}}
  end
end

defmodule MockProgram do
  def forward(_program, _inputs, _opts) do
    {:ok, %{answer: "test response"}}
  end
end
```

**After (Behaviour-based approach)**:
```elixir
test "program evaluation with mocked components" do
  # Setup all mocks consistently
  DSPEx.BehaviourMocks.setup_standard_client_mock()
  DSPEx.BehaviourMocks.setup_standard_adapter_mock()
  DSPEx.BehaviourMocks.setup_standard_program_mock()
  
  # Test with dependency injection
  program = %DSPEx.Predict{
    signature: TestSignature,
    client: DSPEx.MockClient,  # Injected mock
    adapter: DSPEx.MockAdapter # Injected mock
  }
  
  # Test execution
  {:ok, result} = DSPEx.Program.forward(program, %{question: "2+2?"})
  assert result.answer == "mocked response"
  
  # Verify all mocks were called as expected
  verify!(DSPEx.MockClient)
  verify!(DSPEx.MockAdapter)
end
```

### Phase 4: Dependency Injection Infrastructure (Week 3-4)

#### 4.1 Configuration-Based Injection
```elixir
# lib/dspex/program.ex - Enhanced for dependency injection
defmodule DSPEx.Program do
  # Add configuration resolution for testability
  def resolve_client(program, opts) do
    cond do
      # Explicit injection (highest priority - for tests)
      client = Keyword.get(opts, :client) -> client
      # Program-specific client
      Map.has_key?(program, :client) -> program.client
      # Global test configuration
      Application.get_env(:dspex, :test_client) -> Application.get_env(:dspex, :test_client)
      # Default production behavior
      true -> DSPEx.Client
    end
  end
  
  def resolve_adapter(program, opts) do
    cond do
      adapter = Keyword.get(opts, :adapter) -> adapter
      Map.has_key?(program, :adapter) -> program.adapter
      Application.get_env(:dspex, :test_adapter) -> Application.get_env(:dspex, :test_adapter)
      true -> DSPEx.Adapter
    end
  end
  
  def resolve_evaluator(opts) do
    cond do
      evaluator = Keyword.get(opts, :evaluator) -> evaluator
      Application.get_env(:dspex, :test_evaluator) -> Application.get_env(:dspex, :test_evaluator)
      true -> DSPEx.Evaluate
    end
  end
end
```

#### 4.2 Test Configuration Helper
```elixir
# test/support/dependency_injection.exs
defmodule DSPEx.TestDependencies do
  @moduledoc """
  Helpers for injecting mock dependencies into programs and tests.
  """
  
  def configure_test_environment() do
    Application.put_env(:dspex, :test_client, DSPEx.MockClient)
    Application.put_env(:dspex, :test_adapter, DSPEx.MockAdapter)
    Application.put_env(:dspex, :test_evaluator, DSPEx.MockEvaluator)
  end
  
  def reset_test_environment() do
    Application.delete_env(:dspex, :test_client)
    Application.delete_env(:dspex, :test_adapter)
    Application.delete_env(:dspex, :test_evaluator)
  end
  
  def with_mocked_dependencies(test_fn) do
    configure_test_environment()
    
    try do
      test_fn.()
    after
      reset_test_environment()
    end
  end
end
```

### Phase 5: Integration Testing Framework (Week 4)

#### 5.1 Contract Verification Tests
```elixir
# test/integration/behaviour_contracts_test.exs
defmodule DSPEx.BehaviourContractsTest do
  use ExUnit.Case, async: true
  
  describe "Client behaviour contract verification" do
    test "all client implementations follow DSPEx.Client behaviour" do
      implementations = [
        DSPEx.ClientManager,  # If it implements the behaviour
        DSPEx.MockClientManager  # Should be updated to implement behaviour
      ]
      
      for impl <- implementations do
        assert behaviour_implemented?(impl, DSPEx.Client),
               "#{impl} does not implement DSPEx.Client behaviour"
      end
    end
  end
  
  describe "Adapter behaviour contract verification" do
    test "all adapter implementations follow DSPEx.Adapter behaviour" do
      implementations = [
        DSPEx.Adapters.InstructorLiteGemini,  # Should implement behaviour
        # Add others as they're converted
      ]
      
      for impl <- implementations do
        assert behaviour_implemented?(impl, DSPEx.Adapter),
               "#{impl} does not implement DSPEx.Adapter behaviour"
      end
    end
  end
  
  defp behaviour_implemented?(module, behaviour) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        behaviours = module.module_info(:attributes) |> Keyword.get(:behaviour, [])
        behaviour in behaviours
      _ ->
        false
    end
  end
end
```

#### 5.2 End-to-End Mock Integration Tests
```elixir
# test/integration/full_stack_mock_test.exs
defmodule DSPEx.FullStackMockTest do
  use ExUnit.Case, async: true
  import Mox
  
  setup :verify_on_exit!
  setup :set_mox_from_context
  
  test "complete teleprompter workflow with fully mocked stack" do
    # This demonstrates the power of the behaviour-based approach
    
    # Setup teacher program mock - generates "good" demonstrations
    expect(DSPEx.MockProgram, :forward, 5, fn _program, inputs, _opts ->
      case Map.get(inputs, :question) do
        q when q =~ "easy" -> {:ok, %{answer: "easy correct answer"}}
        q when q =~ "hard" -> {:ok, %{answer: "hard correct answer"}}
        _ -> {:ok, %{answer: "generic correct answer"}}
      end
    end)
    
    # Setup evaluator mock - scores demonstrations
    expect(DSPEx.MockEvaluator, :run, 3, fn _program, _examples, _metric_fn, _opts ->
      {:ok, %{
        score: 0.9,  # High score for "good" demonstrations
        stats: %{total_examples: 10, successful: 9, failed: 1, 
                 duration_ms: 500, success_rate: 0.9, throughput: 20.0, errors: []}
      }}
    end)
    
    # Setup client mock for any internal requests
    expect(DSPEx.MockClient, :request, fn _messages, _opts ->
      {:ok, %{choices: [%{message: %{role: "assistant", content: "Generated instruction"}}]}}
    end)
    
    # Setup adapter mock
    DSPEx.BehaviourMocks.setup_standard_adapter_mock()
    
    # Execute teleprompter with fully mocked dependencies
    student = %DSPEx.Predict{signature: TestSignature, client: DSPEx.MockClient}
    teacher = %DSPEx.Predict{signature: TestSignature, client: DSPEx.MockClient}
    trainset = [
      DSPEx.Example.new(%{question: "easy question"}, %{answer: "easy answer"}),
      DSPEx.Example.new(%{question: "hard question"}, %{answer: "hard answer"})
    ]
    
    teleprompter = DSPEx.Teleprompter.BootstrapFewShot.new(evaluator: DSPEx.MockEvaluator)
    
    {:ok, optimized_student} = DSPEx.Teleprompter.compile(
      teleprompter, student, teacher, trainset, 
      &DSPEx.Teleprompter.exact_match(:answer)
    )
    
    # Verify the optimization worked
    assert optimized_student != student
    assert length(optimized_student.demos) > 0
    
    # Verify all mocks were called as expected
    verify!(DSPEx.MockProgram)
    verify!(DSPEx.MockEvaluator)
    verify!(DSPEx.MockClient)
    verify!(DSPEx.MockAdapter)
  end
end
```

## Implementation Priority

### Immediate Actions (This Week)
1. **Add missing behaviours** to `DSPEx.Client`, `DSPEx.Adapter`, `DSPEx.Evaluate`
2. **Update test_helper.exs** with centralized Mox definitions
3. **Create behaviour_mocks.exs** support module

### Short Term (Next 2 Weeks)  
1. **Migrate critical tests** to use behaviour-based mocks
2. **Add dependency injection** infrastructure to core modules
3. **Implement contract verification** tests

### Medium Term (Next Month)
1. **Complete test migration** across entire codebase
2. **Add behaviour compliance** to CI/CD pipeline
3. **Documentation** and developer guides

## Benefits of This Approach

### 1. **Contract Enforcement**
- All implementations must follow defined interfaces
- Compile-time verification of behaviour compliance
- Clear API contracts for all major components

### 2. **Superior Testability**
- Fast, deterministic unit tests without network calls
- Isolated testing of complex orchestration logic
- Predictable test behavior across environments

### 3. **Development Velocity**
- Parallel development on different components
- Faster debugging with controlled mock behavior
- Reduced flaky tests from external dependencies

### 4. **Architectural Clarity**
- Explicit interfaces make system boundaries clear
- Easier to reason about component interactions
- Better separation of concerns

## Migration Risks & Mitigation

### Risk 1: Breaking Existing Tests
**Mitigation**: Gradual migration with parallel support for old and new approaches

### Risk 2: Behavior Divergence Between Mocks and Real Implementations
**Mitigation**: Contract verification tests and shared behavior specifications

### Risk 3: Increased Complexity
**Mitigation**: Centralized mock helpers and clear documentation

## Success Metrics

1. **100% behaviour compliance** for core modules (Client, Adapter, Evaluator, Program, Teleprompter)
2. **90% reduction** in test execution time for integration tests
3. **Zero flaky tests** from external API dependencies
4. **100% test coverage** for complex orchestration logic (Teleprompter)

This implementation will establish DSPEx as having best-in-class testability and development experience, following the contract-first approach outlined in COUPLINGS_02.md.

## Nx Integration for Advanced Behaviour Testing

### Enhanced Behaviour Testing with Nx

```elixir
# lib/dspex/behaviours/nx_test_helpers.ex
defmodule DSPEx.Behaviours.NxTestHelpers do
  @moduledoc """
  Nx-powered testing utilities for behaviour validation.
  
  Provides numerical analysis of behaviour implementations to ensure
  performance consistency, output quality, and statistical reliability.
  """
  
  import Nx.Defn
  
  @doc """
  Analyze behaviour implementation performance characteristics.
  """
  def analyze_behaviour_performance(implementation_results) do
    times = Enum.map(implementation_results, & &1.time)
    qualities = Enum.map(implementation_results, & &1.quality)
    
    time_tensor = Nx.tensor(times)
    quality_tensor = Nx.tensor(qualities)
    
    analyze_performance_impl(time_tensor, quality_tensor)
  end
  
  defn analyze_performance_impl(times, qualities) do
    # Performance metrics
    mean_time = Nx.mean(times)
    time_stability = 1.0 / (1.0 + Nx.standard_deviation(times) / mean_time)
    
    # Quality metrics
    mean_quality = Nx.mean(qualities)
    quality_consistency = 1.0 / (1.0 + Nx.standard_deviation(qualities))
    
    # Combined performance score
    performance_score = (time_stability + quality_consistency + mean_quality) / 3.0
    
    %{
      performance_score: performance_score,
      mean_time: mean_time,
      time_stability: time_stability,
      mean_quality: mean_quality,
      quality_consistency: quality_consistency
    }
  end
  
  @doc """
  Property-based testing for behaviour contracts using Nx.
  """
  def validate_behaviour_contract(behaviour_module, implementation, test_data) do
    results = 
      test_data
      |> Enum.map(fn test_case ->
        validate_single_contract(behaviour_module, implementation, test_case)
      end)
    
    analyze_contract_validation(results)
  end
  
  defp validate_single_contract(behaviour_module, implementation, test_case) do
    try do
      # Check if implementation satisfies behaviour
      case apply(implementation, :module_info, [:attributes]) do
        attributes ->
          behaviours = Keyword.get_values(attributes, :behaviour)
          
          if behaviour_module in behaviours do
            # Run test case
            result = run_test_case(implementation, test_case)
            validate_result_properties(result, test_case)
          else
            {:error, :behaviour_not_implemented}
          end
      end
    rescue
      error -> {:error, {:exception, error}}
    end
  end
  
  defp analyze_contract_validation(validation_results) do
    success_count = Enum.count(validation_results, fn result -> 
      case result do
        %{all_valid: true} -> true
        _ -> false
      end
    end)
    
    total_count = length(validation_results)
    success_rate = success_count / total_count
    
    # Extract numerical metrics where available
    numerical_results = extract_numerical_validation_metrics(validation_results)
    
    case numerical_results do
      [] ->
        %{success_rate: success_rate, numerical_analysis: :unavailable}
      
      metrics ->
        tensor = Nx.tensor(metrics)
        numerical_analysis = analyze_numerical_validation(tensor)
        
        Map.merge(%{success_rate: success_rate}, numerical_analysis)
    end
  end
  
  defn analyze_numerical_validation(metrics) do
    %{
      mean_metric: Nx.mean(metrics),
      metric_stability: 1.0 / (1.0 + Nx.standard_deviation(metrics)),
      min_metric: Nx.reduce_min(metrics),
      max_metric: Nx.reduce_max(metrics)
    }
  end
  
  # Helper functions
  
  defp run_test_case(implementation, test_case) do
    function_name = Map.get(test_case, :function)
    args = Map.get(test_case, :args, [])
    
    apply(implementation, function_name, args)
  end
  
  defp validate_result_properties(result, test_case) do
    expected_properties = Map.get(test_case, :expected_properties, %{})
    
    property_validations = 
      Enum.map(expected_properties, fn {property, expected_value} ->
        actual_value = extract_property(result, property)
        validate_property_match(property, expected_value, actual_value)
      end)
    
    %{
      result: result,
      property_validations: property_validations,
      all_valid: Enum.all?(property_validations, & &1.valid)
    }
  end
  
  defp extract_property(result, property) do
    case result do
      map when is_map(map) -> Map.get(map, property)
      _ -> nil
    end
  end
  
  defp validate_property_match(property, expected, actual) do
    %{
      property: property,
      expected: expected,
      actual: actual,
      valid: expected == actual
    }
  end
  
  defp extract_numerical_validation_metrics(validation_results) do
    validation_results
    |> Enum.flat_map(fn result ->
      case result do
        %{result: %{score: score}} when is_number(score) -> [score]
        %{result: %{quality: quality}} when is_number(quality) -> [quality]
        _ -> []
      end
    end)
  end
end
```

### Nx Configuration for Behaviour Testing

```elixir
# config/config.exs - Nx Configuration for Behaviour Testing
config :dspex, :behaviours,
  # Nx backend configuration
  nx_backend: {Nx.BinaryBackend, []},
  
  # Testing and validation settings
  testing: %{
    performance_analysis: true,
    statistical_comparison: true,
    property_validation: true,
    numerical_precision: 1.0e-6
  },
  
  # Mock behaviour validation
  mock_validation: %{
    enabled: true,
    pattern_analysis: true,
    consistency_threshold: 0.8,
    response_tracking: true
  },
  
  # Implementation comparison
  comparison: %{
    min_samples: 10,
    confidence_threshold: 0.8,
    effect_size_threshold: 0.5
  }
```

### Dependencies Integration

```elixir
# mix.exs - Add Nx dependency for behaviour testing
defp deps do
  [
    # ... existing dependencies ...
    {:nx, "~> 0.6"},              # Numerical computing for behaviour testing
    {:mox, "~> 1.0", only: :test}, # Already present - Mock testing
    # ... other dependencies ...
  ]
end
```

## Implementation Roadmap

### Phase 1: Missing Behaviours (Week 1)
- [ ] Define DSPEx.Client behaviour with comprehensive callbacks
- [ ] Define DSPEx.Adapter behaviour for response formatting  
- [ ] Define DSPEx.Evaluate behaviour for evaluation components
- [ ] Define DSPEx.Retrieve behaviour for retrieval systems
- [ ] **Integrate Nx dependency for advanced behaviour testing**
- [ ] **Implement Nx-powered behaviour validation utilities**

### Phase 2: Enhanced Testing (Week 2)
- [ ] Update existing implementations to implement new behaviours
- [ ] Create behaviour-specific mock modules using Mox
- [ ] **Deploy Nx-based performance analysis for implementations**
- [ ] **Add statistical comparison capabilities for behaviour testing**

### Phase 3: Migration & Integration (Week 3)
- [ ] Migrate existing tests to use behaviour-based mocks
- [ ] Add dependency injection support to core modules
- [ ] **Implement contract validation using Nx analytics**
- [ ] Create integration testing framework

### Phase 4: Optimization & Documentation (Week 4)
- [ ] **Performance optimization using Nx insights**
- [ ] **Statistical validation of mock vs real behaviour consistency**
- [ ] Comprehensive documentation and developer guides
- [ ] CI/CD integration for behaviour compliance checking 