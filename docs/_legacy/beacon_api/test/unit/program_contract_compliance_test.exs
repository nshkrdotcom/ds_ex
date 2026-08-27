defmodule DSPEx.ProgramContractComplianceTest do
  @moduledoc """
  Unit tests specifically for Program contract compliance.
  Tests individual contract requirements in isolation.
  """
  
  use ExUnit.Case, async: true
  
  alias DSPEx.{Program, Predict, OptimizedProgram, Example}
  
  defmodule ContractTestSignature do
    use DSPEx.Signature, "input -> output"
  end
  
  setup do
    predict_program = %Predict{signature: ContractTestSignature, client: :test}
    demo = %Example{data: %{input: "test", output: "result"}, input_keys: MapSet.new([:input])}
    optimized_program = OptimizedProgram.new(predict_program, [demo])
    
    %{
      predict: predict_program,
      optimized: optimized_program,
      demo: demo
    }
  end
  
  describe "Program.forward/3 contract compliance" do
    test "accepts timeout option and respects it", %{predict: program} do
      inputs = %{input: "timeout test"}
      
      # Should work with reasonable timeout
      assert {:ok, _} = Program.forward(program, inputs, timeout: 5000)
      
      # Should timeout on impossibly short timeout  
      assert {:error, :timeout} = Program.forward(program, inputs, timeout: 1)
    end
    
    test "accepts correlation_id option", %{predict: program} do
      inputs = %{input: "correlation test"}
      correlation_id = "test-correlation-#{System.unique_integer()}"
      
      # Should accept correlation_id without error
      assert {:ok, _} = Program.forward(program, inputs, correlation_id: correlation_id)
    end
    
    test "maintains backward compatibility with forward/2", %{predict: program} do
      inputs = %{input: "compatibility test"}
      
      # forward/2 should still work exactly as before
      assert {:ok, outputs} = Program.forward(program, inputs)
      assert Map.has_key?(outputs, :output)
    end
    
    test "validates input types correctly", %{predict: program} do
      # Valid inputs
      assert {:ok, _} = Program.forward(program, %{input: "valid"})
      
      # Invalid inputs should return proper errors
      assert {:error, {:invalid_inputs, _}} = Program.forward(program, "not a map", [])
      assert {:error, {:invalid_inputs, _}} = Program.forward(program, nil, [])
      assert {:error, {:invalid_inputs, _}} = Program.forward(program, 123, [])
    end
  end
  
  describe "Program introspection contract compliance" do
    test "program_type/1 returns correct types", %{predict: predict, optimized: optimized} do
      assert Program.program_type(predict) == :predict
      assert Program.program_type(optimized) == :optimized
      
      # Test edge cases
      assert Program.program_type("invalid") == :unknown
      assert Program.program_type(nil) == :unknown
      assert Program.program_type(%{}) == :unknown
    end
    
    test "safe_program_info/1 returns required fields", %{predict: predict, optimized: optimized} do
      # Test Predict program
      predict_info = Program.safe_program_info(predict)
      
      assert %{
        type: :predict,
        name: :Predict,
        has_demos: false,
        signature: ContractTestSignature
      } = predict_info
      
      # Test OptimizedProgram
      optimized_info = Program.safe_program_info(optimized)
      
      assert %{
        type: :optimized,
        name: _,  # Name may vary for OptimizedProgram
        has_demos: true,
        signature: ContractTestSignature
      } = optimized_info
    end
    
    test "has_demos?/1 correctly detects demonstrations", %{predict: predict, optimized: optimized} do
      # Basic program without demos
      refute Program.has_demos?(predict)
      
      # OptimizedProgram with demos
      assert Program.has_demos?(optimized)
      
      # Program with empty demos list
      empty_demo_program = %{predict | demos: []}
      refute Program.has_demos?(empty_demo_program)
      
      # Program with nil demos
      nil_demo_program = %{predict | demos: nil}
      refute Program.has_demos?(nil_demo_program)
      
      # Invalid inputs
      refute Program.has_demos?("invalid")
      refute Program.has_demos?(nil)
    end
  end
end

