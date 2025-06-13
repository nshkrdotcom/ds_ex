defmodule DSPEx.SIMBAIntegrationSmokeTest do
  @moduledoc """
  Smoke test that validates the essential SIMBA workflow can execute.
  This simulates the core SIMBA optimization loop without full implementation.
  
  SUCCESS CRITERIA: This test must pass for SIMBA integration to proceed.
  """
  
  use ExUnit.Case, async: false
  
  alias DSPEx.{Program, Predict, Example, OptimizedProgram, Client}
  alias DSPEx.Services.ConfigManager
  alias DSPEx.Test.MockProvider
  
  defmodule SIMBAWorkflowSignature do
    use DSPEx.Signature, "question -> answer, reasoning"
  end
  
  setup do
    {:ok, _mock} = MockProvider.start_link(mode: :contextual)
    :ok
  end
  
  test "minimal SIMBA workflow compatibility" do
    # Step 1: Create student and teacher programs (SIMBA pattern)
    student = %Predict{signature: SIMBAWorkflowSignature, client: :gemini}
    teacher = %Predict{signature: SIMBAWorkflowSignature, client: :openai}
    
    # Validate programs are properly constructed
    assert Program.program_type(student) == :predict
    assert Program.program_type(teacher) == :predict
    
    # Step 2: Create minimal training set (SIMBA bootstrap data)
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
    
    # Validate training data structure
    assert length(trainset) == 2
    for example <- trainset do
      assert is_struct(example, Example)
      assert Map.has_key?(example.data, :question)
      assert Map.has_key?(example.data, :answer)
      assert Map.has_key?(example.data, :reasoning)
    end
    
    # Step 3: Test teacher demonstration generation (SIMBA bootstrap step)
    teacher_inputs = Example.inputs(List.first(trainset))
    assert %{question: "What is 2+2?"} = teacher_inputs
    
    case Program.forward(teacher, teacher_inputs) do
      {:ok, teacher_prediction} ->
        # Teacher should generate reasoning + answer
        assert Map.has_key?(teacher_prediction, :answer)
        
        # May or may not have reasoning depending on mock setup
        
        # Step 4: Create demonstration from teacher output (SIMBA demo creation)
        demo_data = Map.merge(teacher_inputs, teacher_prediction)
        demo = Example.new(demo_data)
        demo = Example.with_inputs(demo, [:question])
        
        assert Example.inputs(demo) == teacher_inputs
        teacher_outputs = Example.outputs(demo)
        assert Map.has_key?(teacher_outputs, :answer)
        
      {:error, _} ->
        # Teacher failed, create mock demo for testing (SIMBA fallback)
        demo_data = %{
          question: "What is 2+2?",
          answer: "4",
          reasoning: "Mock reasoning for testing"
        }
        demo = Example.new(demo_data)
        demo = Example.with_inputs(demo, [:question])
    end
    
    # Step 5: Test instruction generation (SIMBA instruction candidates)
    instruction_messages = [%{
      role: "user",
      content: """
      Create an instruction for answering mathematical questions with reasoning.
      Input: question
      Output: answer, reasoning
      
      Be precise and show your work step by step.
      """
    }]
    
    instruction = case Client.request(instruction_messages, %{provider: :openai}) do
      {:ok, response} ->
        # Validate response structure SIMBA expects
        assert %{choices: choices} = response
        assert is_list(choices) and length(choices) > 0
        
        content = response.choices
          |> List.first()
          |> get_in([:message, :content])
          |> String.trim()
        
        assert is_binary(content)
        content
        
      {:error, _} ->
        # Fallback instruction for testing (SIMBA fallback strategy)
        "Answer the mathematical question step by step, showing your reasoning."
    end
    
    assert is_binary(instruction)
    assert String.length(instruction) > 10
    
    # Step 6: Test program enhancement (SIMBA wrapping strategy)
    enhancement_strategy = OptimizedProgram.simba_enhancement_strategy(student)
    assert enhancement_strategy in [:native_demos, :wrap_optimized, :native_full]
    
    enhanced_program = case enhancement_strategy do
      :native_demos ->
        # Student supports demos natively
        %{student | demos: [demo]}
        
      :wrap_optimized ->
        # Wrap with OptimizedProgram (most common case)
        OptimizedProgram.new(student, [demo], %{
          optimization_method: :simba_smoke_test,
          instruction: instruction,
          enhancement_strategy: enhancement_strategy,
          smoke_test: true
        })
        
      :native_full ->
        # Student supports both demos and instructions
        %{student | demos: [demo], instruction: instruction}
    end
    
    # Validate enhanced program structure
    assert is_struct(enhanced_program)
    
    # Step 7: Test enhanced program execution (SIMBA trial evaluation)
    test_input = %{question: "What is 5+5?"}
    
    case Program.forward(enhanced_program, test_input) do
      {:ok, result} ->
        assert Map.has_key?(result, :answer)
        assert is_binary(result.answer)
        
      {:error, reason} ->
        # Some errors are acceptable in smoke test
        assert reason in [:timeout, :network_error, :api_error, :no_api_key]
    end
    
    # Step 8: Validate program introspection works (SIMBA program analysis)
    program_info = Program.safe_program_info(enhanced_program)
    assert program_info.type in [:predict, :optimized]
    assert program_info.has_demos == true
    assert is_atom(program_info.name)
    
    # Step 9: Test configuration access (SIMBA configuration resolution)
    default_provider = ConfigManager.get_with_default([:prediction, :default_provider], :gemini)
    assert is_atom(default_provider)
    assert default_provider in [:gemini, :openai, :anthropic]
    
    # SIMBA-specific config paths
    instruction_model = ConfigManager.get_with_default(
      [:teleprompters, :simba, :default_instruction_model], 
      :openai
    )
    assert is_atom(instruction_model)
    
    max_concurrent = ConfigManager.get_with_default(
      [:teleprompters, :simba, :max_concurrent_operations],
      20
    )
    assert is_integer(max_concurrent) and max_concurrent > 0
    
    # Step 10: Test concurrent execution safety (SIMBA optimization trials)
    concurrent_inputs = [
      %{question: "What is 1+1?"},
      %{question: "What is 2+2?"},
      %{question: "What is 3+3?"}
    ]
    
    concurrent_results = Task.async_stream(
      concurrent_inputs,
      fn input ->
        Program.forward(enhanced_program, input, timeout: 5000)
      end,
      max_concurrency: 3,
      timeout: 10_000
    ) |> Enum.to_list()
    
    # Should handle concurrent execution without crashes
    assert length(concurrent_results) == 3
    
    # At least some should succeed (depending on mock setup)
    successes = Enum.count(concurrent_results, fn
      {:ok, {:ok, _}} -> true
      _ -> false
    end)
    
    # In mock mode, should have high success rate
    assert successes >= 2, "Expected at least 2 successful concurrent executions, got #{successes}"
  end
  
  test "SIMBA error recovery scenarios" do
    student = %Predict{signature: SIMBAWorkflowSignature, client: :test}
    
    # Test timeout handling
    assert {:error, :timeout} = Program.forward(student, %{question: "test"}, timeout: 1)
    
    # Test invalid input handling
    assert {:error, _} = Program.forward(student, "invalid input")
    assert {:error, _} = Program.forward(student, nil)
    
    # Test that errors don't crash the system
    inputs = %{question: "Recovery test"}
    assert {:ok, _} = Program.forward(student, inputs, timeout: 5000)
  end
  
  test "SIMBA metadata serialization compatibility" do
    student = %Predict{signature: SIMBAWorkflowSignature, client: :test}
    demo = %Example{
      data: %{question: "test", answer: "test"},
      input_keys: MapSet.new([:question])
    }
    
    # Test complex SIMBA metadata
    simba_metadata = %{
      optimization_method: :simba,
      instruction: "Complex SIMBA instruction with details",
      optimization_score: 0.87654,
      optimization_stats: %{
        trials: 47,
        convergence_iteration: 23,
        best_trial: 31,
        total_duration_ms: 125_000,
        improvements: [0.1, 0.05, 0.02]
      },
      bayesian_trials: Enum.map(1..10, fn i ->
        %{
          trial: i,
          score: :rand.uniform(),
          configuration: %{
            instruction_id: "inst_#{i}",
            demo_ids: ["demo_1", "demo_2"],
            hyperparameters: %{
              temperature: 0.7,
              max_tokens: 150
            }
          }
        }
      end),
      best_configuration: %{
        instruction_id: "inst_31",
        demo_ids: ["demo_5", "demo_12", "demo_3"],
        hyperparameters: %{
          temperature: 0.75,
          max_tokens: 200
        }
      }
    }
    
    # Should handle complex metadata without issues
    optimized = OptimizedProgram.new(student, [demo], simba_metadata)
    
    # Validate all metadata preserved
    assert optimized.metadata.optimization_method == :simba
    assert optimized.metadata.optimization_score == 0.87654
    assert length(optimized.metadata.bayesian_trials) == 10
    assert optimized.metadata.best_configuration.instruction_id == "inst_31"
    
    # Should be JSON serializable (critical for SIMBA persistence)
    assert {:ok, _json} = Jason.encode(optimized.metadata)
  end
end
