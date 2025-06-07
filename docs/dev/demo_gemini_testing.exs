#!/usr/bin/env elixir

# Demo script showing DSPEx Gemini adapter testing
# Run with: mix run demo_gemini_testing.exs

# Define test signature
defmodule TestSignature do
  @moduledoc "Answer questions clearly and concisely"
  use DSPEx.Signature, "question -> answer"
end

IO.puts("\n🧪 DSPEx Gemini Adapter Testing Demo")
IO.puts("=" |> String.duplicate(50))

# Test 1: Mock Testing (No API Key Required)
IO.puts("\n📝 Test 1: Mock Testing Pipeline")
IO.puts("-" |> String.duplicate(30))

try do
  # Step 1: Format inputs to messages
  inputs = %{question: "What is 2+2?"}
  {:ok, messages} = DSPEx.Adapter.format_messages(TestSignature, inputs)
  
  IO.puts("✅ Step 1 - Format inputs:")
  IO.inspect(messages, label: "Messages")
  
  # Step 2: Simulate API response (instead of real HTTP call)
  mock_response = %{
    choices: [
      %{message: %{content: "4"}}
    ]
  }
  
  IO.puts("\n✅ Step 2 - Mock API response:")
  IO.inspect(mock_response, label: "Mock Response")
  
  # Step 3: Parse response to outputs
  {:ok, outputs} = DSPEx.Adapter.parse_response(TestSignature, mock_response)
  
  IO.puts("\n✅ Step 3 - Parse outputs:")
  IO.inspect(outputs, label: "Parsed Outputs")
  
  IO.puts("\n🎉 Mock test successful!")
  
rescue
  error ->
    IO.puts("\n❌ Mock test failed: #{inspect(error)}")
end

# Test 2: Live API Testing (Requires GEMINI_API_KEY)
IO.puts("\n🌐 Test 2: Live Gemini API Testing")
IO.puts("-" |> String.duplicate(30))

api_key = System.get_env("GEMINI_API_KEY")

if api_key && api_key != "" do
  try do
    # Step 1: Format inputs
    inputs = %{question: "What is the capital of France?"}
    {:ok, messages} = DSPEx.Adapter.format_messages(TestSignature, inputs)
    
    IO.puts("✅ Step 1 - Format inputs:")
    IO.inspect(messages, label: "Messages")
    
    # Step 2: Real API call
    IO.puts("\n📡 Step 2 - Making real Gemini API call...")
    {:ok, response} = DSPEx.Client.request(messages)
    
    IO.puts("✅ API call successful:")
    IO.inspect(response, label: "Live Response")
    
    # Step 3: Parse real response
    {:ok, outputs} = DSPEx.Adapter.parse_response(TestSignature, response)
    
    IO.puts("\n✅ Step 3 - Parse outputs:")
    IO.inspect(outputs, label: "Parsed Outputs")
    
    IO.puts("\n🎉 Live API test successful!")
    
  rescue
    error ->
      IO.puts("\n❌ Live API test failed: #{inspect(error)}")
      IO.puts("This could be due to network issues, invalid API key, or rate limiting.")
  end
else
  IO.puts("⚠️  GEMINI_API_KEY not set - skipping live API test")
  IO.puts("To test with live API, run:")
  IO.puts("export GEMINI_API_KEY=\"your-api-key\"")
  IO.puts("mix run demo_gemini_testing.exs")
end

# Test 3: Complete Adapter + Client Integration
IO.puts("\n🔗 Test 3: Complete Adapter + Client Integration")
IO.puts("-" |> String.duplicate(30))

try do
  # This demonstrates the full Phase 1 pipeline: Signature -> Adapter -> Client
  
  # Step 1: Define a more complex signature
  defmodule ComplexSignature do
    @moduledoc "Analyze text and provide insights"
    use DSPEx.Signature, "text, context -> analysis, sentiment"
  end
  
  # Step 2: Prepare inputs
  inputs = %{
    text: "I love this new technology!",
    context: "social media post"
  }
  
  IO.puts("✅ Step 1 - Complex signature with multiple inputs/outputs:")
  IO.puts("Instructions: #{ComplexSignature.instructions()}")
  IO.puts("Input fields: #{inspect(ComplexSignature.input_fields())}")
  IO.puts("Output fields: #{inspect(ComplexSignature.output_fields())}")
  IO.puts("All fields: #{inspect(ComplexSignature.fields())}")
  
  # Step 3: Format with adapter
  {:ok, messages} = DSPEx.Adapter.format_messages(ComplexSignature, inputs)
  
  IO.puts("\n✅ Step 2 - Adapter formatting:")
  IO.inspect(messages, label: "Formatted Messages")
  
  # Step 4: Process with client (mock response for demo)
  if api_key && api_key != "" do
    IO.puts("\n📡 Step 3 - Live API call...")
    {:ok, response} = DSPEx.Client.request(messages)
    
    # Step 5: Parse back to structured outputs  
    {:ok, outputs} = DSPEx.Adapter.parse_response(ComplexSignature, response)
    
    IO.puts("\n✅ Step 4 - Complete integration result:")
    IO.inspect(outputs, label: "Final Structured Outputs")
  else
    # Mock mode
    mock_response = %{
      choices: [
        %{message: %{content: "Positive sentiment detected. This appears to be enthusiastic about technology adoption."}}
      ]
    }
    
    {:ok, outputs} = DSPEx.Adapter.parse_response(ComplexSignature, mock_response)
    
    IO.puts("\n✅ Step 3 - Mock integration result:")
    IO.inspect(outputs, label: "Final Structured Outputs")
  end
  
  IO.puts("\n🎉 Complete integration test successful!")
  IO.puts("✨ Phase 1 components (Signature + Adapter + Client) working together!")
  
rescue
  error ->
    IO.puts("\n❌ Integration test failed: #{inspect(error)}")
end

IO.puts("\n" <> "=" |> String.duplicate(50))
IO.puts("🏁 Demo complete!")

if api_key && api_key != "" do
  IO.puts("✅ Ran with live API key")
else
  IO.puts("📝 Ran in mock mode only")
end