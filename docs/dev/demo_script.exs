#!/usr/bin/env elixir

# Simple demonstration script for DSPEx Client and Adapter integration
# Run with: mix run demo_script.exs

defmodule DemoSignature do
  @moduledoc "Simple demo signature"
  use DSPEx.Signature, "question -> answer"
end

defmodule DemoRunner do
  def run do
    IO.puts("🧪 DSPEx Client + Adapter Integration Demo")
    IO.puts("=" |> String.duplicate(50))
    
    # Test 1: Basic Adapter functionality
    IO.puts("\n📋 Test 1: Adapter Message Formatting")
    inputs = %{question: "What is 2+2?"}
    
    case DSPEx.Adapter.format_messages(DemoSignature, inputs) do
      {:ok, messages} ->
        IO.puts("   ✅ Successfully formatted inputs into messages:")
        IO.puts("      #{inspect(messages, pretty: true)}")
        
        # Test 2: Mock response parsing
        IO.puts("\n📥 Test 2: Adapter Response Parsing")
        mock_response = %{
          choices: [%{message: %{content: "The answer is 4"}}]
        }
        
        case DSPEx.Adapter.parse_response(DemoSignature, mock_response) do
          {:ok, outputs} ->
            IO.puts("   ✅ Successfully parsed mock response:")
            IO.puts("      #{inspect(outputs, pretty: true)}")
            
            # Test 3: Client validation (without actual API call)
            IO.puts("\n🔍 Test 3: Client Message Validation")
            test_client_validation(messages)
            
          {:error, reason} ->
            IO.puts("   ❌ Response parsing failed: #{reason}")
        end
        
      {:error, reason} ->
        IO.puts("   ❌ Message formatting failed: #{reason}")
    end
    
    IO.puts("\n🎉 Demo completed!")
    IO.puts("\nTo test with live Gemini API:")
    IO.puts("1. Set GEMINI_API_KEY environment variable")
    IO.puts("2. Run: mix test test/examples/client_adapter_example_test.exs --include external_api")
  end
  
  defp test_client_validation(messages) do
    # Test that the messages pass Client validation
    # (without actually making HTTP requests)
    
    valid_cases = [
      {messages, "formatted adapter messages"},
      {[%{role: "user", content: "hello"}], "simple user message"},
      {[%{role: "user", content: "q"}, %{role: "assistant", content: "a"}], "conversation"}
    ]
    
    invalid_cases = [
      {[], "empty message list"},
      {[%{content: "missing role"}], "missing role"},
      {[%{role: "user"}], "missing content"},
      {[%{role: 123, content: "non-string role"}], "invalid role type"}
    ]
    
    IO.puts("   Valid cases:")
    for {test_messages, description} <- valid_cases do
      case DSPEx.Client.request(test_messages) do
        {:ok, _response} ->
          IO.puts("     ✅ #{description}: would succeed (API call)")
        {:error, :invalid_messages} ->
          IO.puts("     ❌ #{description}: failed validation")
        {:error, reason} ->
          IO.puts("     ⚠️  #{description}: validation passed, but #{reason} (expected without API)")
      end
    end
    
    IO.puts("   Invalid cases:")
    for {test_messages, description} <- invalid_cases do
      case DSPEx.Client.request(test_messages) do
        {:ok, _response} ->
          IO.puts("     ❌ #{description}: should have failed validation")
        {:error, :invalid_messages} ->
          IO.puts("     ✅ #{description}: correctly rejected")
        {:error, reason} ->
          IO.puts("     ⚠️  #{description}: got #{reason} instead of validation error")
      end
    end
  end
end

# Run the demo
DemoRunner.run()