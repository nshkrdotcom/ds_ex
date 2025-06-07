defmodule DSPEx.Examples.ClientAdapterDemo do
  @moduledoc """
  Comprehensive demonstration of DSPEx.Client and DSPEx.Adapter working together.
  
  This example shows:
  1. How Client and Adapter integrate for Gemini API calls
  2. Mock testing approaches for offline development
  3. Live API testing approaches with real Gemini API
  4. Error handling and edge cases
  5. Performance considerations
  
  ## Current Phase 1 Implementation Status
  
  The current implementation provides:
  - DSPEx.Client: Basic HTTP client for Gemini API with validation and error handling
  - DSPEx.Adapter: Translation layer between signatures and LLM messages
  - Full integration through DSPEx.Predict that orchestrates both components
  
  ## Usage Examples
  
  ### Mock Testing (Offline Development)
  ```elixir
  # Run tests without API keys - uses mock responses
  DSPEx.Examples.ClientAdapterDemo.demo_with_mocks()
  ```
  
  ### Live API Testing (Requires GEMINI_API_KEY)
  ```elixir
  # Set your API key first:
  # export GEMINI_API_KEY="your-api-key"
  DSPEx.Examples.ClientAdapterDemo.demo_with_live_api()
  ```
  
  ## Test File Organization
  
  The testing approach is organized across multiple files:
  
  ### Unit Tests (Mock-based)
  - `test/unit/client_test.exs` - Client validation and request building
  - `test/unit/adapter_test.exs` - Message formatting and response parsing
  
  ### Integration Tests (Mock-based)
  - `test/integration/client_adapter_test.exs` - Client + Adapter working together
  - `test/integration/signature_adapter_test.exs` - Signature + Adapter integration
  
  ### End-to-End Tests (Live API capable)
  - These demonstrate the complete pipeline including live API calls
  
  ## Architecture Overview
  
  ```
  DSPEx.Signature (defines input/output contract)
           ↓
  DSPEx.Adapter (formats signature → messages, parses responses)
           ↓  
  DSPEx.Client (makes HTTP requests to Gemini API)
           ↓
  DSPEx.Predict (orchestrates the complete pipeline)
  ```
  """

  # =================================================================
  # Mock Components for Testing
  # =================================================================

  defmodule MockGeminiClient do
    @moduledoc """
    Mock implementation of Gemini API responses for testing.
    Simulates various response patterns and error conditions.
    """

    def request(messages, _opts \\ %{}) do
      # Simulate processing delay
      Process.sleep(50)
      
      case extract_content(messages) do
        content when content =~ ~r/math|calculate|solve/i ->
          {:ok, %{
            choices: [%{
              message: %{
                role: "assistant", 
                content: "The answer is 4. This is calculated by adding 2 + 2."
              }
            }]
          }}
          
        content when content =~ ~r/capital.*france/i ->
          {:ok, %{
            choices: [%{
              message: %{
                role: "assistant",
                content: "Paris is the capital of France. It has been the capital since 987 AD."
              }
            }]
          }}
          
        content when content =~ ~r/error|fail/i ->
          {:error, :api_error}
          
        content when content =~ ~r/timeout/i ->
          {:error, :timeout}
          
        _content ->
          {:ok, %{
            choices: [%{
              message: %{
                role: "assistant",
                content: "I understand your request and here is my response."
              }
            }]
          }}
      end
    end
    
    defp extract_content(messages) do
      messages
      |> Enum.map(fn %{content: content} -> content end)
      |> Enum.join(" ")
    end
  end

  # =================================================================
  # Test Signatures for Demonstrations
  # =================================================================

  defmodule MathSignature do
    @moduledoc "Solve math problems"
    use DSPEx.Signature, "problem -> answer"
  end
  
  defmodule QASignature do
    @moduledoc "Answer questions with reasoning"
    use DSPEx.Signature, "question -> answer, reasoning"
  end
  
  defmodule FactSignature do
    @moduledoc "Provide factual information"
    use DSPEx.Signature, "query -> fact"
  end

  # =================================================================
  # Demo Functions
  # =================================================================

  @doc """
  Demonstrates Client and Adapter integration using mock responses.
  This approach allows development and testing without API keys.
  """
  def demo_with_mocks do
    IO.puts("🧪 Running DSPEx Client + Adapter Demo with Mock Data")
    IO.puts("=" |> String.duplicate(60))
    
    # Test 1: Basic Math Problem
    IO.puts("\n📐 Test 1: Math Problem Solving")
    test_math_with_mocks()
    
    # Test 2: Question Answering
    IO.puts("\n❓ Test 2: Question Answering")
    test_qa_with_mocks()
    
    # Test 3: Error Handling
    IO.puts("\n⚠️  Test 3: Error Handling")
    test_error_handling_with_mocks()
    
    # Test 4: Performance Testing
    IO.puts("\n🚀 Test 4: Performance Testing")
    test_performance_with_mocks()
    
    IO.puts("\n✅ Mock demo completed successfully!")
  end

  @doc """
  Demonstrates Client and Adapter integration using live Gemini API.
  Requires GEMINI_API_KEY environment variable to be set.
  """
  def demo_with_live_api do
    case System.get_env("GEMINI_API_KEY") do
      nil ->
        IO.puts("⚠️  GEMINI_API_KEY not set. Please set your API key:")
        IO.puts("   export GEMINI_API_KEY=\"your-api-key-here\"")
        {:error, :missing_api_key}
        
      _api_key ->
        IO.puts("🌐 Running DSPEx Client + Adapter Demo with Live Gemini API")
        IO.puts("=" |> String.duplicate(60))
        
        # Test 1: Simple Question
        IO.puts("\n📝 Test 1: Simple Question")
        test_simple_question_live()
        
        # Test 2: Math Problem  
        IO.puts("\n🔢 Test 2: Math Problem")
        test_math_problem_live()
        
        # Test 3: Multiple Requests
        IO.puts("\n🔄 Test 3: Multiple Requests")
        test_multiple_requests_live()
        
        IO.puts("\n✅ Live API demo completed!")
    end
  end

  # =================================================================
  # Mock Testing Implementation
  # =================================================================

  defp test_math_with_mocks do
    # Step 1: Format inputs using Adapter
    inputs = %{problem: "What is 2 + 2?"}
    
    case DSPEx.Adapter.format_messages(MathSignature, inputs) do
      {:ok, messages} ->
        IO.puts("   📤 Formatted messages: #{inspect(messages, pretty: true)}")
        
        # Step 2: Mock client request
        case MockGeminiClient.request(messages) do
          {:ok, response} ->
            IO.puts("   📥 Mock API response: #{inspect(response, pretty: true)}")
            
            # Step 3: Parse response using Adapter
            case DSPEx.Adapter.parse_response(MathSignature, response) do
              {:ok, outputs} ->
                IO.puts("   ✅ Parsed outputs: #{inspect(outputs)}")
                {:ok, outputs}
                
              {:error, reason} ->
                IO.puts("   ❌ Parse error: #{reason}")
                {:error, reason}
            end
            
          {:error, reason} ->
            IO.puts("   ❌ Mock API error: #{reason}")
            {:error, reason}
        end
        
      {:error, reason} ->
        IO.puts("   ❌ Format error: #{reason}")
        {:error, reason}
    end
  end

  defp test_qa_with_mocks do
    inputs = %{question: "What is the capital of France?"}
    
    with {:ok, messages} <- DSPEx.Adapter.format_messages(QASignature, inputs),
         {:ok, response} <- MockGeminiClient.request(messages),
         {:ok, outputs} <- DSPEx.Adapter.parse_response(QASignature, response) do
      
      IO.puts("   ✅ Q&A Success:")
      IO.puts("     Question: #{inputs.question}")
      IO.puts("     Answer: #{outputs.answer}")
      
      # QASignature has multiple outputs, but current simple parsing puts everything in first field
      if Map.has_key?(outputs, :reasoning) do
        IO.puts("     Reasoning: #{outputs.reasoning}")
      end
      
      {:ok, outputs}
    else
      {:error, reason} ->
        IO.puts("   ❌ Q&A failed: #{reason}")
        {:error, reason}
    end
  end

  defp test_error_handling_with_mocks do
    # Test various error conditions
    error_cases = [
      {%{problem: "trigger error condition"}, "API error simulation"},
      {%{problem: "trigger timeout condition"}, "Timeout simulation"},
      {%{}, "Missing required inputs"}
    ]
    
    Enum.each(error_cases, fn {inputs, description} ->
      IO.puts("   🔍 Testing: #{description}")
      
      case DSPEx.Adapter.format_messages(MathSignature, inputs) do
        {:ok, messages} ->
          case MockGeminiClient.request(messages) do
            {:ok, response} ->
              case DSPEx.Adapter.parse_response(MathSignature, response) do
                {:ok, outputs} ->
                  IO.puts("     ✅ Unexpected success: #{inspect(outputs)}")
                {:error, reason} ->
                  IO.puts("     ⚠️  Parse error (expected): #{reason}")
              end
              
            {:error, reason} ->
              IO.puts("     ⚠️  API error (expected): #{reason}")
          end
          
        {:error, reason} ->
          IO.puts("     ⚠️  Format error (expected): #{reason}")
      end
    end)
  end

  defp test_performance_with_mocks do
    questions = [
      %{query: "What is the population of Tokyo?"},
      %{query: "What is the tallest mountain?"},
      %{query: "What is the speed of light?"},
      %{query: "What is quantum computing?"},
      %{query: "What is machine learning?"}
    ]
    
    start_time = System.monotonic_time(:millisecond)
    
    results = questions
    |> Task.async_stream(fn inputs ->
      with {:ok, messages} <- DSPEx.Adapter.format_messages(FactSignature, inputs),
           {:ok, response} <- MockGeminiClient.request(messages),
           {:ok, outputs} <- DSPEx.Adapter.parse_response(FactSignature, response) do
        {:ok, outputs}
      else
        error -> error
      end
    end, max_concurrency: 3, timeout: 5000)
    |> Enum.to_list()
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    successful = Enum.count(results, fn {:ok, {:ok, _}} -> true; _ -> false end)
    
    IO.puts("   📊 Performance Results:")
    IO.puts("     Total requests: #{length(questions)}")
    IO.puts("     Successful: #{successful}")
    IO.puts("     Duration: #{duration}ms")
    IO.puts("     Avg per request: #{div(duration, length(questions))}ms")
  end

  # =================================================================
  # Live API Testing Implementation  
  # =================================================================

  defp test_simple_question_live do
    inputs = %{query: "What is the capital of Japan?"}
    
    with {:ok, messages} <- DSPEx.Adapter.format_messages(FactSignature, inputs),
         {:ok, response} <- DSPEx.Client.request(messages),
         {:ok, outputs} <- DSPEx.Adapter.parse_response(FactSignature, response) do
      
      IO.puts("   ✅ Live API Success:")
      IO.puts("     Query: #{inputs.query}")
      IO.puts("     Response: #{outputs.fact}")
      {:ok, outputs}
    else
      {:error, reason} ->
        IO.puts("   ❌ Live API failed: #{reason}")
        IO.puts("     This might be due to network issues or API rate limits")
        {:error, reason}
    end
  end

  defp test_math_problem_live do
    inputs = %{problem: "Calculate the square root of 144"}
    
    case DSPEx.Adapter.format_messages(MathSignature, inputs) do
      {:ok, messages} ->
        IO.puts("   📤 Sending to live API: #{inspect(messages)}")
        
        case DSPEx.Client.request(messages) do
          {:ok, response} ->
            IO.puts("   📥 Live API response received")
            
            case DSPEx.Adapter.parse_response(MathSignature, response) do
              {:ok, outputs} ->
                IO.puts("   ✅ Math result: #{outputs.answer}")
                {:ok, outputs}
                
              {:error, reason} ->
                IO.puts("   ❌ Parse error: #{reason}")
                {:error, reason}
            end
            
          {:error, reason} ->
            IO.puts("   ❌ Live API error: #{reason}")
            IO.puts("     Check your API key and network connection")
            {:error, reason}
        end
        
      {:error, reason} ->
        IO.puts("   ❌ Format error: #{reason}")
        {:error, reason}
    end
  end

  defp test_multiple_requests_live do
    inputs_list = [
      {FactSignature, %{query: "What is the largest planet?"}},
      {FactSignature, %{query: "What is the smallest country?"}},
      {MathSignature, %{problem: "What is 15 * 7?"}}
    ]
    
    IO.puts("   🔄 Testing #{length(inputs_list)} requests...")
    
    start_time = System.monotonic_time(:millisecond)
    
    results = inputs_list
    |> Enum.with_index(1)
    |> Enum.map(fn {{signature, inputs}, index} ->
      IO.puts("     Request #{index}: #{inspect(inputs)}")
      
      with {:ok, messages} <- DSPEx.Adapter.format_messages(signature, inputs),
           {:ok, response} <- DSPEx.Client.request(messages),
           {:ok, outputs} <- DSPEx.Adapter.parse_response(signature, response) do
        IO.puts("     ✅ Request #{index} success")
        {:ok, outputs}
      else
        {:error, reason} ->
          IO.puts("     ❌ Request #{index} failed: #{reason}")
          {:error, reason}
      end
    end)
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    successful = Enum.count(results, fn {:ok, _} -> true; _ -> false end)
    
    IO.puts("   📊 Live API Results:")
    IO.puts("     Total requests: #{length(inputs_list)}")
    IO.puts("     Successful: #{successful}")
    IO.puts("     Duration: #{duration}ms")
  end

  # =================================================================
  # Testing Utilities
  # =================================================================

  @doc """
  Demonstrates the complete integration through DSPEx.Predict.
  This shows how Client and Adapter work together in the real system.
  """
  def demo_complete_integration do
    IO.puts("\n🔗 Complete Integration Demo via DSPEx.Predict")
    IO.puts("-" |> String.duplicate(50))
    
    # This would use the actual DSPEx.Predict module that orchestrates
    # the Client and Adapter together. For Phase 1, this demonstrates
    # the integration pattern that the Predict module follows.
    
    inputs = %{question: "How do Client and Adapter work together?"}
    
    # Step 1: Adapter formats the signature inputs into messages
    case DSPEx.Adapter.format_messages(QASignature, inputs) do
      {:ok, messages} ->
        IO.puts("1️⃣  Adapter formatted inputs → messages")
        IO.puts("    #{inspect(messages, pretty: true)}")
        
        # Step 2: Client sends messages to API
        case DSPEx.Client.request(messages) do
          {:ok, response} ->
            IO.puts("2️⃣  Client sent messages → received response")
            IO.puts("    Status: Success")
            
            # Step 3: Adapter parses API response back to signature outputs
            case DSPEx.Adapter.parse_response(QASignature, response) do
              {:ok, outputs} ->
                IO.puts("3️⃣  Adapter parsed response → outputs")
                IO.puts("    #{inspect(outputs, pretty: true)}")
                IO.puts("\n✅ Complete pipeline successful!")
                {:ok, outputs}
                
              {:error, reason} ->
                IO.puts("3️⃣  ❌ Adapter parse failed: #{reason}")
                {:error, reason}
            end
            
          {:error, reason} ->
            IO.puts("2️⃣  ❌ Client request failed: #{reason}")
            {:error, reason}
        end
        
      {:error, reason} ->
        IO.puts("1️⃣  ❌ Adapter format failed: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Shows how to run tests with different configurations.
  """
  def demo_test_configurations do
    IO.puts("\n⚙️  Test Configuration Examples")
    IO.puts("-" |> String.duplicate(40))
    
    IO.puts("""
    
    ## Unit Tests (Mock-based, no API key needed)
    ```bash
    # Test individual components
    mix test test/unit/client_test.exs
    mix test test/unit/adapter_test.exs
    
    # Test with verbose output
    mix test test/unit/client_test.exs --trace
    ```
    
    ## Integration Tests (Mock-based)
    ```bash
    # Test components working together
    mix test test/integration/client_adapter_test.exs
    mix test test/integration/signature_adapter_test.exs
    ```
    
    ## Live API Tests (Requires GEMINI_API_KEY)
    ```bash
    # Set API key first
    export GEMINI_API_KEY="your-key-here"
    
    # Run live tests (when implemented)
    mix test --include external_api
    ```
    
    ## Performance Tests
    ```bash
    # Run performance benchmarks
    mix test --include performance
    ```
    
    ## Current Phase 1 Test Command
    ```bash
    # Run all stable Phase 1 tests
    mix test test/unit/client_test.exs test/unit/adapter_test.exs --exclude phase2_features
    ```
    """)
  end
end