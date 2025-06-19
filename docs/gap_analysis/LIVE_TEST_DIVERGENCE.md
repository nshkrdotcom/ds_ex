# Live API Divergence Strategy

## Overview

DSPEx now features a sophisticated **three-mode test architecture** that handles the gradual divergence from seamless fallback to dedicated live API testing. This document outlines the strategic approach to implementing live API requirements while maintaining development velocity.

## Test Mode Architecture

### 1. **Pure Mock Mode** (🟦 Default)
```bash
mix test              # Uses pure mock mode
mix test.mock         # Explicit pure mock mode
DSPEX_TEST_MODE=mock mix test
```

**Characteristics:**
- Zero network requests
- Deterministic responses
- Fast execution (< 1s for full suite)
- Perfect for development and CI/CD

**Use Cases:**
- Unit tests for all components
- Basic integration tests
- Development workflow
- CI/CD pipeline validation
- Performance testing (consistent conditions)

### 2. **Fallback Mode** (🟡 Hybrid)
```bash
mix test.fallback     # Live API when available, mock fallback
DSPEX_TEST_MODE=fallback mix test
```

**Characteristics:**
- Attempts live API when keys available
- Seamless fallback to mock when not
- Variable execution time
- Validates both paths work

**Use Cases:**
- Development with optional API keys
- Integration validation with real APIs
- Gradual migration testing
- Local development with intermittent connectivity

### 3. **Live API Mode** (🟢 Strict)
```bash
mix test.live         # Requires API keys, fails without
DSPEX_TEST_MODE=live mix test
```

**Characteristics:**
- Requires valid API keys
- No fallback behavior
- Real API validation
- Slower, potentially flaky

**Use Cases:**
- Pre-production validation
- Real API behavior testing
- Error condition validation
- Performance benchmarking against live APIs

## When Tests Should Require Live APIs

### ✅ **Keep in Mock/Fallback (Recommended)**
Most tests should remain in mock or fallback mode:

```elixir
# Unit tests - always mock
test "program validates input fields correctly" do
  # Mock client ensures consistent behavior
end

# Basic integration - fallback works great
test "end-to-end prediction flow" do
  # setup_adaptive_client/1 handles mode switching
  {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)
  # Test works in any mode
end

# Performance tests - always mock for consistency
test "high-frequency requests are handled efficiently" do
  # Force mock client for consistent timing
  {:ok, client} = DSPEx.MockClientManager.start_link(:gemini, %{
    simulate_delays: false
  })
end
```

### 🔄 **Gradual Migration Candidates**
Tests that may eventually need live API validation:

```elixir
# Mark tests that will eventually need live APIs
@tag :future_live_required
test "complex multi-turn conversation handling" do
  # Currently works with fallback
  # May need live APIs for realistic conversation flow validation
end

@tag :live_preferred  
test "multi-provider optimization" do
  # Works in fallback but benefits from real API behavior
end
```

### 🟢 **Require Live APIs (Selective)**
Only implement live-only requirements for tests that **cannot** be validated with mocks:

```elixir
# 1. Real API-specific behavior that can't be mocked
test "handles gemini rate limiting gracefully" do
  case DSPEx.TestModeConfig.get_test_mode() do
    :live ->
      # Test real rate limiting behavior
      run_rate_limit_test()
    _ ->
      skip("Requires live API mode: mix test.live")
  end
end

# 2. Model-specific response validation
test "gpt-4 vs gpt-3.5 response quality differences" do
  # Requires real model comparison
  require_live_mode!("Model comparison requires real API responses")
end

# 3. Cost and billing validation
test "token usage tracking accuracy" do
  # Real token counting validation
  require_live_mode!("Token counting requires real API usage")
end

# 4. Network and infrastructure testing
test "handles network timeouts and recovers" do
  # Real network conditions
  require_live_mode!("Network testing requires real connections")
end
```

## Implementation Strategy

### Phase 1: Current State - Three-Mode Architecture ✅
The current implementation provides:

```elixir
# Adaptive test helper that respects test modes
{client_type, client} = MockHelpers.setup_adaptive_client(:gemini)

# Mode-aware client setup
case DSPEx.TestModeConfig.get_test_mode() do
  :mock -> setup_isolated_mock_client(provider)
  :fallback -> setup_adaptive_client(provider)
  :live -> setup_live_client(provider)
end
```

### Phase 2: Conditional Live Requirements (In Progress)
Implement smart test skipping and mode validation:

```elixir
defmodule MyIntegrationTest do
  use ExUnit.Case
  import DSPEx.LiveTestHelpers
  
  @tag :live_required
  test "real API rate limiting" do
    require_live_mode!("Rate limiting testing requires real API calls")
    
    # Test implementation
    run_live_rate_limit_test()
  end
  
  @tag :live_preferred
  test "multi-provider optimization" do
    case DSPEx.TestModeConfig.get_test_mode() do
      :live ->
        run_with_live_apis()
      _ ->
        IO.puts("Running with mock/fallback - results may vary from live behavior")
        run_with_adaptive_clients()
    end
  end
end
```

### Phase 3: Dedicated Live Test Suites (Future)
Create separate test directories for different requirements:

```
test/
├── unit/              # Pure mock only
├── integration/       # Adaptive (mock/fallback/live)
├── live_integration/  # Live API only
│   ├── rate_limiting_test.exs
│   ├── cost_validation_test.exs
│   ├── model_comparison_test.exs
│   └── network_resilience_test.exs
└── performance/       # Mock only (consistent conditions)
```

## Technical Implementation Patterns

### 1. **Test Mode Utilities**
```elixir
defmodule DSPEx.LiveTestHelpers do
  def require_live_mode!(message \\ "Test requires live API mode") do
    unless DSPEx.TestModeConfig.live_only_mode?() do
      skip(message <> " - Use: mix test.live")
    end
  end
  
  def skip_unless_live_mode(message \\ "Skipping in mock/fallback mode") do
    unless DSPEx.TestModeConfig.live_only_mode?() do
      skip(message)
    end
  end
  
  def adaptive_test_setup(provider) do
    # Use the established pattern
    MockHelpers.setup_adaptive_client(provider)
  end
end
```

### 2. **Mode-Aware Test Configuration**
```elixir
# config/test.exs
config :dspex, :test_modes,
  default_mode: :mock,
  live_test_timeout: 30_000,
  mock_test_timeout: 5_000,
  enable_mode_logging: true

# Conditional test configuration
case DSPEx.TestModeConfig.get_test_mode() do
  :live ->
    ExUnit.configure(timeout: 30_000, max_failures: 5)
  :fallback ->
    ExUnit.configure(timeout: 15_000)
  :mock ->
    ExUnit.configure(timeout: 5_000, max_failures: :infinity)
end
```

### 3. **Performance Test Isolation**
```elixir
# Performance tests should always use controlled conditions
describe "performance characteristics" do
  test "request processing time is reasonable" do
    # Force mock for consistent performance testing
    {:ok, client} = DSPEx.MockClientManager.start_link(:gemini, %{
      simulate_delays: false,
      responses: :contextual
    })
    
    # Measure only local processing time
    start_time = System.monotonic_time(:millisecond)
    _result = DSPEx.MockClientManager.request(client, messages)
    end_time = System.monotonic_time(:millisecond)
    
    # Assert consistent performance
    assert (end_time - start_time) < 200
  end
end
```

### 4. **Supervision and Fault Tolerance Testing**
```elixir
# Handle process lifecycle properly in supervision tests
describe "supervision and fault tolerance" do
  test "client crash doesn't affect other components" do
    # Start unlinked to prevent exit signal propagation
    {:ok, client} = GenServer.start(DSPEx.ClientManager, {:gemini, %{}})
    program = Predict.new(TestSignature, client)
    
    # Kill the client and handle the resulting exit gracefully
    ref = Process.monitor(client)
    Process.exit(client, :kill)
    
    receive do
      {:DOWN, ^ref, :process, ^client, :killed} -> :ok
    after
      1000 -> flunk("Client process did not die as expected")
    end
    
    # Use try/catch to handle GenServer call to dead process
    result = 
      try do
        Program.forward(program, %{question: "Post-crash test"})
      catch
        :exit, _reason -> {:error, :client_dead}
      end
    
    assert match?({:error, _}, result)
    assert Process.alive?(self())
  end
end
```

## Migration Checklist

### ✅ **Completed (Phase 1)**
- [x] Three-mode test architecture
- [x] Adaptive client setup with `setup_adaptive_client/1`
- [x] Mode-aware logging and indicators
- [x] Mix task integration (`test.mock`, `test.fallback`, `test.live`)
- [x] Environment contamination prevention
- [x] Performance test isolation (400x faster)
- [x] Supervision test reliability

### 🔄 **In Progress (Phase 2)**
- [x] Test mode validation helpers
- [x] Mode-specific test skipping
- [x] Performance test isolation from network conditions
- [x] Supervision and fault tolerance patterns
- [ ] Live test identification and tagging
- [ ] Comprehensive live test helper module
- [ ] Documentation for when to require live APIs

### 📋 **Future (Phase 3)**
- [ ] Dedicated live test suites
- [ ] CI/CD integration for selective live testing
- [ ] Cost monitoring for live test runs
- [ ] Live test result caching and comparison
- [ ] Production environment testing patterns

## Performance Results

### Before Optimization
- Unit performance test: `1674ms` (network dependent)
- Integration performance test: `13090ms` (extremely slow)
- Supervision tests: Failed with process management issues

### After Optimization
- Unit performance test: `4.3ms` (400x faster)
- Integration performance test: `32ms` (400x faster)
- Supervision tests: Reliable with proper error handling
- Full test suite: `< 7 seconds` in mock mode

## Best Practices Summary

### ✅ **DO**
- Use `MockHelpers.setup_adaptive_client/1` for most integration tests
- Force mock clients for performance and timing tests
- Implement mode-aware test skipping for live-only requirements
- Use clear test categorization with tags
- Validate environment cleanliness to prevent contamination
- Handle process lifecycle properly in supervision tests

### ❌ **DON'T**
- Don't require live APIs unless absolutely necessary
- Don't mix live and mock clients in the same test
- Don't depend on network conditions for performance tests
- Don't create live-only tests without fallback documentation
- Don't ignore test mode configuration in client setup
- Don't use linked GenServers in crash testing without proper handling

### 🎯 **GOAL**
Maintain development velocity while providing confidence in live API integration through strategic, selective live API testing.

## Conclusion

The three-mode test architecture successfully balances development velocity with integration confidence. Performance tests now run 400x faster while maintaining reliability. The system gracefully handles the spectrum from pure mock development to strict live API validation, enabling teams to choose the appropriate level of integration testing for their context. 