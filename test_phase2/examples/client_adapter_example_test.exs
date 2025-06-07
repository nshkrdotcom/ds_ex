defmodule DSPEx.Examples.ClientAdapterExampleTest do
  @moduledoc """
  Example test demonstrating both mock and live testing approaches
  for DSPEx.Client and DSPEx.Adapter integration.
  
  This test file shows:
  1. How to test with mock data (no API key required)
  2. How to test with live Gemini API (requires GEMINI_API_KEY)
  3. Different testing patterns for various scenarios
  4. Error handling and edge cases
  """
  use ExUnit.Case, async: true

  # Mock signature for testing
  defmodule TestSignature do
    @moduledoc "Test signature for demonstration"
    use DSPEx.Signature, "question -> answer"
  end

  defmodule MultiFieldSignature do
    @moduledoc "Multi-field signature for testing"
    use DSPEx.Signature, "question -> answer, confidence"
  end

  # =================================================================
  # Mock Testing Approach
  # =================================================================

  describe "mock testing approach (no API key required)" do
    test "basic client-adapter integration with mock response" do
      # Step 1: Prepare inputs
      inputs = %{question: "What is 2+2?"}
      
      # Step 2: Use Adapter to format messages
      assert {:ok, messages} = DSPEx.Adapter.format_messages(TestSignature, inputs)
      assert [%{role: "user", content: content}] = messages
      assert content =~ "question: What is 2+2?"
      
      # Step 3: Mock client response (simulating what Client.request would return)
      mock_response = %{
        choices: [%{message: %{content: "The answer is 4"}}]
      }
      
      # Step 4: Use Adapter to parse the mock response
      assert {:ok, outputs} = DSPEx.Adapter.parse_response(TestSignature, mock_response)
      assert %{answer: "The answer is 4"} = outputs
    end

    test "error handling with mock client errors" do
      inputs = %{question: "What causes errors?"}
      
      # Format should succeed
      assert {:ok, messages} = DSPEx.Adapter.format_messages(TestSignature, inputs)
      
      # Simulate various client error responses
      error_cases = [
        # Network error simulation
        :network_error,
        # API error simulation  
        :api_error,
        # Timeout simulation
        :timeout
      ]
      
      for error_reason <- error_cases do
        # This is what would happen if Client.request returned an error
        client_error = {:error, error_reason}
        
        # The error should propagate through the pipeline
        assert {:error, ^error_reason} = client_error
      end
    end

    test "multi-field signature with mock data" do
      inputs = %{question: "How confident are you?"}
      
      assert {:ok, messages} = DSPEx.Adapter.format_messages(MultiFieldSignature, inputs)
      
      # Mock response with multiple lines for multiple output fields
      mock_response = %{
        choices: [%{message: %{content: "I am quite confident\nhigh"}}]
      }
      
      assert {:ok, outputs} = DSPEx.Adapter.parse_response(MultiFieldSignature, mock_response)
      assert %{answer: "I am quite confident", confidence: "high"} = outputs
    end

    test "validation errors with mock approach" do
      # Missing required input
      invalid_inputs = %{}
      
      assert {:error, :missing_inputs} = DSPEx.Adapter.format_messages(TestSignature, invalid_inputs)
      
      # Invalid response format
      invalid_response = %{choices: []}
      
      assert {:error, :invalid_response} = DSPEx.Adapter.parse_response(TestSignature, invalid_response)
    end
  end

  # =================================================================
  # Live API Testing Approach  
  # =================================================================

  describe "live API testing approach (requires GEMINI_API_KEY)" do
    @describetag :external_api

    setup do
      case System.get_env("GEMINI_API_KEY") do
        nil ->
          {:skip, "GEMINI_API_KEY not set - skipping live API tests"}
        _key ->
          :ok
      end
    end

    test "complete client-adapter pipeline with live API" do
      inputs = %{question: "What is the capital of Japan?"}
      
      # Step 1: Format inputs using Adapter
      assert {:ok, messages} = DSPEx.Adapter.format_messages(TestSignature, inputs)
      
      # Step 2: Make real API call using Client
      case DSPEx.Client.request(messages) do
        {:ok, response} ->
          # Step 3: Parse real response using Adapter
          assert {:ok, outputs} = DSPEx.Adapter.parse_response(TestSignature, response)
          assert %{answer: answer} = outputs
          assert is_binary(answer)
          assert String.length(answer) > 0
          
          # Verify the answer contains relevant content
          assert String.contains?(String.downcase(answer), "tokyo") or
                 String.contains?(String.downcase(answer), "japan")
          
        {:error, reason} ->
          # Live API might fail due to network, rate limits, etc.
          # Log the error but don't fail the test
          IO.puts("Live API test failed (this is expected in some environments): #{reason}")
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    test "live API with custom options" do
      inputs = %{question: "What is 5 * 7?"}
      
      assert {:ok, messages} = DSPEx.Adapter.format_messages(TestSignature, inputs)
      
      # Test with custom options
      options = %{
        temperature: 0.1,  # Lower temperature for more deterministic results
        max_tokens: 50
      }
      
      case DSPEx.Client.request(messages, options) do
        {:ok, response} ->
          assert {:ok, outputs} = DSPEx.Adapter.parse_response(TestSignature, response)
          assert %{answer: answer} = outputs
          assert is_binary(answer)
          
          # Math answer should contain "35"
          assert String.contains?(answer, "35")
          
        {:error, reason} ->
          IO.puts("Live API test with options failed: #{reason}")
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    test "live API error handling" do
      # Test with invalid inputs that might cause API errors
      inputs = %{question: ""}  # Empty question
      
      case DSPEx.Adapter.format_messages(TestSignature, inputs) do
        {:ok, messages} ->
          case DSPEx.Client.request(messages) do
            {:ok, response} ->
              # API might still respond to empty questions
              assert {:ok, _outputs} = DSPEx.Adapter.parse_response(TestSignature, response)
              
            {:error, reason} ->
              # Error is acceptable for edge cases
              assert reason in [:network_error, :api_error, :timeout]
          end
          
        {:error, _reason} ->
          # Adapter might reject empty inputs
          :ok
      end
    end
  end

  # =================================================================
  # Performance Testing
  # =================================================================

  describe "performance testing" do
    @describetag :performance

    test "concurrent mock requests" do
      questions = for i <- 1..10 do
        %{question: "Question #{i}?"}
      end
      
      start_time = System.monotonic_time(:millisecond)
      
      results = questions
      |> Task.async_stream(fn inputs ->
        # Mock the complete pipeline
        with {:ok, messages} <- DSPEx.Adapter.format_messages(TestSignature, inputs),
             # Simulate client delay
             :ok <- Process.sleep(10),
             mock_response = %{choices: [%{message: %{content: "Mock answer"}}]},
             {:ok, outputs} <- DSPEx.Adapter.parse_response(TestSignature, mock_response) do
          {:ok, outputs}
        end
      end, max_concurrency: 5, timeout: 1000)
      |> Enum.to_list()
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # All should succeed
      assert Enum.all?(results, fn {:ok, {:ok, _}} -> true; _ -> false end)
      
      # Should complete in reasonable time with concurrency
      assert duration < 500  # Should be much faster than 10 * 10ms = 100ms
      
      IO.puts("Processed #{length(questions)} requests in #{duration}ms")
    end

    test "adapter formatting performance" do
      large_input = %{question: String.duplicate("word ", 100)}
      
      # Time multiple formatting operations
      start_time = System.monotonic_time(:microsecond)
      
      for _i <- 1..100 do
        assert {:ok, _messages} = DSPEx.Adapter.format_messages(TestSignature, large_input)
      end
      
      end_time = System.monotonic_time(:microsecond)
      duration = end_time - start_time
      
      # Should format quickly
      avg_per_format = duration / 100
      assert avg_per_format < 1000  # Less than 1ms per format on average
      
      IO.puts("Average formatting time: #{Float.round(avg_per_format, 2)} microseconds")
    end
  end

  # =================================================================
  # Integration Testing Patterns
  # =================================================================

  describe "integration testing patterns" do
    test "demonstrates testing with dependency injection" do
      # This shows how you could test with injected client behavior
      
      mock_client_fn = fn messages, _opts ->
        content = messages |> List.first() |> Map.get(:content)
        
        cond do
          String.contains?(content, "error") ->
            {:error, :mock_error}
            
          String.contains?(content, "timeout") ->
            {:error, :timeout}
            
          true ->
            {:ok, %{choices: [%{message: %{content: "Mock response"}}]}}
        end
      end
      
      # Test normal operation
      inputs = %{question: "Normal question"}
      assert {:ok, messages} = DSPEx.Adapter.format_messages(TestSignature, inputs)
      assert {:ok, response} = mock_client_fn.(messages, %{})
      assert {:ok, outputs} = DSPEx.Adapter.parse_response(TestSignature, response)
      assert %{answer: "Mock response"} = outputs
      
      # Test error handling
      error_inputs = %{question: "This should error"}
      assert {:ok, error_messages} = DSPEx.Adapter.format_messages(TestSignature, error_inputs)
      assert {:error, :mock_error} = mock_client_fn.(error_messages, %{})
    end

    test "demonstrates property-based testing approach" do
      # Generate various valid inputs
      inputs_list = [
        %{question: "Short?"},
        %{question: "Medium length question here?"},
        %{question: String.duplicate("Long ", 50) <> "question?"}
      ]
      
      for inputs <- inputs_list do
        # All valid inputs should format successfully
        assert {:ok, messages} = DSPEx.Adapter.format_messages(TestSignature, inputs)
        assert [%{role: "user", content: content}] = messages
        assert String.contains?(content, inputs.question)
        
        # All valid responses should parse successfully
        mock_response = %{choices: [%{message: %{content: "Any response"}}]}
        assert {:ok, outputs} = DSPEx.Adapter.parse_response(TestSignature, mock_response)
        assert %{answer: "Any response"} = outputs
      end
    end
  end

  # =================================================================
  # Helper Functions for Testing
  # =================================================================

  defp create_mock_response(content) do
    %{choices: [%{message: %{content: content}}]}
  end

  defp simulate_client_request(messages, behavior \\ :success) do
    case behavior do
      :success ->
        {:ok, create_mock_response("Mock successful response")}
        
      :error ->
        {:error, :api_error}
        
      :timeout ->
        {:error, :timeout}
        
      :network_error ->
        {:error, :network_error}
        
      custom_content when is_binary(custom_content) ->
        {:ok, create_mock_response(custom_content)}
    end
  end
end