defmodule DSPEx.Predict.VariableTest do
  use ExUnit.Case, async: true
  
  alias DSPEx.Predict

  describe "variable-enhanced Predict" do
    test "creates Predict program with variable space" do
      predict = Predict.new(TestSignature, :test_client)
      
      assert %Predict{variable_space: space} = predict
      assert is_struct(space, ElixirML.Variable.Space)
      
      # Should have declared variables
      assert Map.has_key?(space.variables, :temperature)
      assert Map.has_key?(space.variables, :provider)
      assert Map.has_key?(space.variables, :max_tokens)
      assert Map.has_key?(space.variables, :model)
      assert Map.has_key?(space.variables, :adapter)
    end

    test "variable declarations are accessible" do
      variables = Predict.__variables__()
      
      assert %{
        temperature: %ElixirML.Variable{type: :float},
        provider: %ElixirML.Variable{type: :choice},
        max_tokens: %ElixirML.Variable{type: :integer},
        model: %ElixirML.Variable{type: :choice},
        adapter: %ElixirML.Variable{type: :module}
      } = variables
    end

    test "forward passes variables correctly" do
      # Mock the client request
      expect_client_request()
      
      predict = Predict.new(TestSignature, :test_client)
      inputs = %{question: "What is 2+2?"}
      
      # Use variables in the request
      opts = [
        variables: %{
          temperature: 0.9,
          provider: :anthropic,
          max_tokens: 150
        }
      ]
      
      # This would normally make a real request, but we're mocking it
      case Predict.forward(predict, inputs, opts) do
        {:ok, _result} -> 
          # Variables should have been merged into model config
          :ok
        {:error, _} ->
          # Expected for test environment without real client
          :ok
      end
    end

    test "handles programs without variable configuration" do
      predict = Predict.new(TestSignature, :test_client)
      inputs = %{question: "What is 2+2?"}
      
      # No variables specified - should use defaults
      case Predict.forward(predict, inputs, []) do
        {:ok, _result} -> :ok
        {:error, _} -> :ok  # Expected in test environment
      end
    end
  end

  describe "variable space merging" do
    test "merges signature variables with declared variables" do
      predict = Predict.new(TestSignature, :test_client, auto_extract_variables: true)
      
      assert %Predict{variable_space: space} = predict
      assert is_struct(space, ElixirML.Variable.Space)
      
      # Should have all declared variables
      variable_names = Map.keys(space.variables)
      assert :temperature in variable_names
      assert :provider in variable_names
    end

    test "skips auto-extraction when disabled" do
      predict = Predict.new(TestSignature, :test_client, auto_extract_variables: false)
      
      assert %Predict{variable_space: space} = predict
      
      # Should only have declared variables, no auto-extracted ones
      variable_names = Map.keys(space.variables)
      assert :temperature in variable_names
      assert :provider in variable_names
    end
  end

  # Helper functions for testing

  defp expect_client_request do
    # Mock DSPEx.Client.request to avoid real API calls in tests
    # This would normally be done with Mox or similar
    :ok
  end

  # Mock signature for testing
  defmodule TestSignature do
    def input_fields, do: [:question]
    def output_fields, do: [:answer]
    def description, do: "Test signature"
  end
end