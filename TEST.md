# DSPEx Phase 1 Testing Guide

Simple guide to testing the implemented Phase 1 features.

## Quick Test Commands

```bash
# Run all Phase 1 tests (recommended)
mix test

# Phase 1 unit tests only  
mix test test/unit/

# Test with live Gemini API
export GEMINI_API_KEY="your-api-key"
mix test --include external_api

# Test specific components
mix test test/unit/signature_test.exs
mix test test/unit/client_test.exs  
mix test test/unit/adapter_test.exs
```

## Phase 1 Components Tested

✅ **DSPEx.Signature** - Macro-based signature parsing  
✅ **DSPEx.Example** - Core data structures  
✅ **DSPEx.Client** - HTTP requests to Gemini API  
✅ **DSPEx.Adapter** - Message formatting and response parsing  
✅ **DSPEx.Predict** - Basic orchestration pipeline  

## Testing Gemini Adapter

### Mock Testing (No API Key Required)

Test the full pipeline with mock responses:

```elixir
# Example test
defmodule TestSignature do
  use DSPEx.Signature, "question -> answer"
end

# 1. Format inputs to messages
{:ok, messages} = DSPEx.Adapter.format_messages(TestSignature, %{question: "What is 2+2?"})
# Returns: [%{role: "user", content: "Please process the following input\n\nquestion: What is 2+2?"}]

# 2. Mock API response (skip real HTTP call)
mock_response = %{choices: [%{message: %{content: "4"}}]}

# 3. Parse response to outputs  
{:ok, outputs} = DSPEx.Adapter.parse_response(TestSignature, mock_response)
# Returns: %{answer: "4"}
```

### Live API Testing (Requires GEMINI_API_KEY)

Test with real Gemini API calls:

```bash
# Set your API key
export GEMINI_API_KEY="your-actual-api-key-here"

# Run live tests
mix test --include external_api
```

Example live test:
```elixir
# 1. Format inputs
{:ok, messages} = DSPEx.Adapter.format_messages(TestSignature, %{question: "What is the capital of France?"})

# 2. Real API call
{:ok, response} = DSPEx.Client.request(messages)

# 3. Parse real response
{:ok, outputs} = DSPEx.Adapter.parse_response(TestSignature, response)

# outputs = %{answer: "Paris"}
```

### Complete Pipeline Test

Test the full DSPEx.Predict pipeline:

```elixir
# Create a signature
defmodule QASignature do
  @moduledoc "Answer questions clearly and concisely"
  use DSPEx.Signature, "question -> answer"
end

# Create prediction pipeline
predict = DSPEx.Predict.new(
  signature: QASignature,
  client: :gemini_client,
  adapter: DSPEx.Adapter
)

# Execute prediction (mock or live depending on setup)
{:ok, prediction} = DSPEx.Predict.forward(predict, %{question: "What is 2+2?"})

# Check results
assert prediction.answer == "4"
```

## Configuration

### Environment Variables
```bash
export GEMINI_API_KEY="your-api-key"           # Required for live tests
export GEMINI_MODEL="gemini-2.5-flash-preview-05-20"  # Optional, has default
```

### Application Config
```elixir
# config/test.exs
config :dspex,
  gemini_api_key: "your-api-key",
  model: "gemini-2.5-flash-preview-05-20"
```

## Test Organization

**Unit Tests** (`test/unit/`): Individual module testing with mocks  
**Integration Tests**: Cross-module functionality (most tagged `:phase2_features`)  
**Property Tests** (`test/property/`): Edge cases and invariants  
**External API Tests**: Real API calls (tagged `:external_api`)  

## Excluded Tests

Phase 2+ features are excluded by default:
- `:phase2_features` - Unimplemented advanced features
- `:integration` - Multi-component integration tests  
- `:end_to_end` - Complete workflow tests
- `:performance` - Performance benchmarks
- `:external_api` - Live API tests (unless explicitly included)

To include specific test types:
```bash
mix test --include phase2_features    # See what's coming next
mix test --include external_api       # Test with real APIs
mix test --include integration        # Run integration tests
```

## Common Issues

**Missing API key**: Set `GEMINI_API_KEY` environment variable  
**Network errors**: Check internet connection for live tests  
**Rate limiting**: Use mock tests for development, live tests sparingly  
**Warning messages**: Phase 2+ compilation warnings are expected and suppressed

## Phase 1 Success Criteria

✅ All 129 Phase 1 tests passing  
✅ Zero test failures  
✅ 268 Phase 2+ tests properly excluded  
✅ Mock testing works without API key  
✅ Live testing works with valid API key  
✅ Complete signature → adapter → client → response pipeline functional