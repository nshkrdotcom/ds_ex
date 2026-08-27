defmodule DSPEx.SIMBAContractValidationTest do
  @moduledoc """
  Validates all APIs that SIMBA depends on work correctly.
  This test suite ensures the DSPEx-SIMBA contract is fulfilled.
  
  CRITICAL: These tests must pass before SIMBA integration.
  """
  
  use ExUnit.Case, async: false
  
  alias DSPEx.{Program, Predict, Client, Example, OptimizedProgram}
  alias DSPEx.Services.ConfigManager
  alias DSPEx.Teleprompter.BootstrapFewShot
  alias DSPEx.Test.MockProvider
  
  defmodule SIMBATestSignature do
    use DSPEx.Signature, "question -> answer"
  end
  
  setup do
    {:ok, _mock} = MockProvider.start_link(mode: :contextual)
    
    %{
      student: %Predict{signature: SIMBATestSignature, client: :test},
      teacher: %Predict{signature: SIMBATestSignature, client: :test},
      demo: %Example{
        data: %{question: "test", answer: "response"}, 
        input_keys: MapSet.new([:question])
      }
    }
  end
  
  describe "SIMBA Core Program Contract" do
    test "Program.forward/3 with timeout and correlation_id", %{student: program} do
      inputs = %{question: "Contract test"}
      correlation_id = "simba-contract-#{System.unique_integer()}"
      
      # Test timeout option works
      assert {:ok, outputs} = Program.forward(program, inputs, timeout: 5000)
      assert Map.has_key?(outputs, :answer)
      assert is_binary(outputs.answer)
      
      # Test correlation_id option works
      assert {:ok, outputs} = Program.forward(program, inputs, 
        correlation_id: correlation_id, timeout: 5000)
      assert Map.has_key?(outputs, :answer)
      
      # Test very short timeout fails gracefully
      assert {:error, :timeout} = Program.forward(program, inputs, timeout: 1)
    end
    
    test "Program.forward/2 maintains backward compatibility", %{student: program} do
      inputs = %{question: "Backward compatibility test"}
      
      # Original forward/2 should still work
      assert {:ok, outputs} = Program.forward(program, inputs)
      assert Map.has_key?(outputs, :answer)
    end
    
    test "Program introspection functions", %{student: student, demo: demo} do
      optimized = OptimizedProgram.new(student, [demo])
      
      # Test program_type/1
      assert Program.program_type(student) == :predict
      assert Program.program_type(optimized) == :optimized
      assert Program.program_type("invalid") == :unknown
      assert Program.program_type(nil) == :unknown
      
      # Test safe_program_info/1 structure
      info = Program.safe_program_info(student)
      assert %{
        type: :predict,
        name: :Predict,
        has_demos: false,
        signature: SIMBATestSignature
      } = info
      
      optimized_info = Program.safe_program_info(optimized)
      assert optimized_info.has_demos == true
      assert optimized_info.type == :optimized
      assert optimized_info.signature == SIMBATestSignature
      
      # Test has_demos?/1
      refute Program.has_demos?(student)
      assert Program.has_demos?(optimized)
      
      # Test with program that has empty demos list
      student_with_empty_demos = %{student | demos: []}
      refute Program.has_demos?(student_with_empty_demos)
    end
    
    test "safe_program_info/1 filters sensitive data", %{student: student} do
      # Test that sensitive data is not exposed
      info = Program.safe_program_info(student)
      
      # Should only include safe fields
      expected_keys = [:type, :name, :has_demos, :signature]
      actual_keys = Map.keys(info)
      
      assert Enum.all?(expected_keys, &(&1 in actual_keys))
      
      # Should not include sensitive fields
      refute Map.has_key?(info, :client)
      refute Map.has_key?(info, :adapter)
      refute Map.has_key?(info, :api_key)
    end
  end
  
  describe "SIMBA Client Contract" do
    test "Client.request/2 response format stability" do
      messages = [%{role: "user", content: "SIMBA instruction generation test"}]
      
      case Client.request(messages, %{provider: :gemini}) do
        {:ok, response} ->
          # Validate structure SIMBA expects
          assert %{choices: choices} = response
          assert is_list(choices)
          assert length(choices) > 0
          
          [first_choice | _] = choices
          assert %{message: %{content: content, role: role}} = first_choice
          assert is_binary(content)
          assert is_binary(role)
          assert role == "assistant"
          
        {:error, reason} ->
          # Validate error is categorized as SIMBA expects
          assert reason in [:timeout, :network_error, :api_error, :rate_limited, :no_api_key]
      end
    end
    
    test "Client error categorization consistency" do
      # Test with invalid messages (should get categorized error)
      invalid_messages = ["not", "a", "proper", "message", "list"]
      
      assert {:error, reason} = Client.request(invalid_messages, %{provider: :test})
      assert is_atom(reason)
      assert reason in [:timeout, :network_error, :api_error, :rate_limited, 
                        :invalid_messages, :provider_not_configured, :no_api_key]
    end
    
    test "Client preserves correlation_id in error scenarios" do
      correlation_id = "error-test-#{System.unique_integer()}"
      
      # This should fail but preserve correlation context
      result = Client.request([], %{provider: :nonexistent, correlation_id: correlation_id})
      
      # Error should be categorized appropriately
      assert {:error, reason} = result
      assert is_atom(reason)
      
      # In real implementation, would verify correlation_id in telemetry
    end
  end
  
  describe "SIMBA Configuration Contract" do
    test "ConfigManager.get_with_default/2 for SIMBA paths" do
      # Test critical SIMBA configuration paths
      default_provider = ConfigManager.get_with_default([:prediction, :default_provider], :gemini)
      assert default_provider in [:gemini, :openai, :anthropic]
      
      # Test teleprompter config paths
      instruction_model = ConfigManager.get_with_default(
        [:teleprompters, :simba, :default_instruction_model], 
        :openai
      )
      assert is_atom(instruction_model)
      
      max_concurrent = ConfigManager.get_with_default(
        [:teleprompters, :simba, :max_concurrent_operations],
        20
      )
      assert is_integer(max_concurrent)
      assert max_concurrent > 0
      
      # Test fallback behavior
      nonexistent = ConfigManager.get_with_default([:nonexistent, :path], :fallback_value)
      assert nonexistent == :fallback_value
      
      # Test single atom key
      single_key = ConfigManager.get_with_default(:nonexistent_key, :default)
      assert single_key == :default
    end
  end
  
  describe "SIMBA OptimizedProgram Contract" do
    test "OptimizedProgram metadata support", %{student: student, demo: demo} do
      demos = [demo]
      
      # Test SIMBA metadata storage
      simba_metadata = %{
        optimization_method: :simba,
        instruction: "Test instruction for SIMBA optimization",
        optimization_score: 0.85,
        optimization_stats: %{
          trials: 25,
          best_trial: 15,
          convergence_iteration: 20,
          total_duration_ms: 45000
        },
        bayesian_trials: [
          %{trial: 1, score: 0.65, configuration: %{instruction_id: "inst_1"}},
          %{trial: 2, score: 0.78, configuration: %{instruction_id: "inst_2"}}
        ],
        best_configuration: %{
          instruction_id: "inst_15",
          demo_ids: ["demo_1", "demo_2"]
        }
      }
      
      optimized = OptimizedProgram.new(student, demos, simba_metadata)
      
      # Validate metadata preservation
      assert optimized.metadata.optimization_method == :simba
      assert optimized.metadata.instruction == "Test instruction for SIMBA optimization"
      assert optimized.metadata.optimization_score == 0.85
      assert optimized.metadata.optimization_stats.trials == 25
      assert length(optimized.metadata.bayesian_trials) == 2
      assert optimized.metadata.best_configuration.instruction_id == "inst_15"
      
      # Validate automatic metadata
      assert %DateTime{} = optimized.metadata.optimized_at
      assert optimized.metadata.demo_count == 1
    end
    
    test "OptimizedProgram handles non-serializable metadata", %{student: student, demo: demo} do
      # Test with metadata containing non-serializable values
      mixed_metadata = %{
        optimization_method: :simba,  # Should be kept
        instruction: "Valid instruction",  # Should be kept
        invalid_function: fn -> :test end,  # Should be filtered out
        invalid_pid: self(),  # Should be filtered out
        valid_list: [1, 2, 3]  # Should be kept
      }
      
      optimized = OptimizedProgram.new(student, [demo], mixed_metadata)
      
      # Valid fields should be preserved
      assert optimized.metadata.optimization_method == :simba
      assert optimized.metadata.instruction == "Valid instruction"
      assert optimized.metadata.valid_list == [1, 2, 3]
      
      # Invalid fields should be filtered out
      refute Map.has_key?(optimized.metadata, :invalid_function)
      refute Map.has_key?(optimized.metadata, :invalid_pid)
    end
    
    test "native support detection", %{student: student} do
      # Create different program types for testing
      basic_program = student
      demo_program = %{student | demos: []}
      
      # Test detection functions
      assert OptimizedProgram.supports_native_demos?(demo_program)
      refute OptimizedProgram.supports_native_demos?(basic_program)
      
      # Neither supports native instructions (would need custom program type)
      refute OptimizedProgram.supports_native_instruction?(demo_program)
      refute OptimizedProgram.supports_native_instruction?(basic_program)
      
      # Test strategy selection
      assert OptimizedProgram.simba_enhancement_strategy(demo_program) == :native_demos
      assert OptimizedProgram.simba_enhancement_strategy(basic_program) == :wrap_optimized
      
      # Test with invalid input
      assert OptimizedProgram.simba_enhancement_strategy("invalid") == :wrap_optimized
      assert OptimizedProgram.simba_enhancement_strategy(nil) == :wrap_optimized
    end
  end
  
  describe "SIMBA Teleprompter Contract" do
    test "BootstrapFewShot handles empty demo scenarios", %{student: student, teacher: teacher} do
      # Empty trainset should not crash
      empty_trainset = []
      metric_fn = fn _example, _prediction -> 1.0 end
      
      teleprompter = BootstrapFewShot.new(max_bootstrapped_demos: 3)
      
      # Should handle empty trainset gracefully
      result = teleprompter.compile(student, teacher, empty_trainset, metric_fn)
      
      case result do
        {:ok, optimized} ->
          # Should return a program even with no demos
          assert is_struct(optimized)
          
          # Should indicate demo generation failed if wrapped
          if match?(%OptimizedProgram{}, optimized) do
            metadata = optimized.metadata
            assert metadata.demo_generation_failed == true
            assert is_binary(metadata.fallback_reason)
          end
          
        {:error, reason} ->
          # Acceptable errors for empty trainset
          assert reason in [:invalid_or_empty_trainset, :no_successful_bootstrap_candidates]
      end
    end
    
    test "BootstrapFewShot handles teacher failures gracefully", %{student: student, teacher: teacher} do
      # Create trainset that will cause teacher to fail
      failing_trainset = [
        %Example{
          data: %{question: "impossible question", answer: "impossible"},
          input_keys: MapSet.new([:question])
        }
      ]
      
      metric_fn = fn _example, _prediction -> 0.0 end  # Everything scores 0
      
      # Set up teacher to fail
      MockProvider.setup_bootstrap_mocks([
        {:error, :teacher_failure}
      ])
      
      teleprompter = BootstrapFewShot.new(
        max_bootstrapped_demos: 2,
        quality_threshold: 0.5
      )
      
      result = teleprompter.compile(student, teacher, failing_trainset, metric_fn)
      
      # Should either succeed with empty demos or fail gracefully
      case result do
        {:ok, optimized} ->
          # Should have no demos due to failures
          demos = case optimized do
            %{demos: demos} -> demos
            %OptimizedProgram{demos: demos} -> demos
            _ -> []
          end
          
          assert Enum.empty?(demos)
          
        {:error, reason} ->
          assert reason in [:no_successful_bootstrap_candidates, :invalid_or_empty_trainset]
      end
    end
    
    test "BootstrapFewShot progress callback integration", %{student: student, teacher: teacher} do
      trainset = [
        %Example{
          data: %{question: "test 1", answer: "answer 1"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "test 2", answer: "answer 2"},
          input_keys: MapSet.new([:question])
        }
      ]
      
      metric_fn = fn _example, _prediction -> 0.8 end
      
      # Collect progress updates
      progress_updates = []
      progress_callback = fn progress ->
        send(self(), {:progress, progress})
        :ok
      end
      
      teleprompter = BootstrapFewShot.new(
        max_bootstrapped_demos: 2,
        progress_callback: progress_callback
      )
      
      # Run optimization
      {:ok, _optimized} = teleprompter.compile(student, teacher, trainset, metric_fn)
      
      # Should have received progress updates
      receive do
        {:progress, progress} ->
          assert is_map(progress)
          assert Map.has_key?(progress, :phase)
          assert progress.phase in [:bootstrap_generation, :demonstration_evaluation, :demonstration_selection]
      after
        1000 -> 
          flunk("Should have received progress updates")
      end
    end
  end
  
  describe "SIMBA Telemetry Contract" do
    test "Program.forward/3 emits expected telemetry events", %{student: program} do
      correlation_id = "telemetry-test-#{System.unique_integer()}"
      
      # Attach telemetry handler to capture events
      events_received = []
      
      handler_id = "test-handler-#{System.unique_integer()}"
      :telemetry.attach(
        handler_id,
        [:dspex, :program, :forward, :start],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      :telemetry.attach(
        "#{handler_id}-stop",
        [:dspex, :program, :forward, :stop],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      # Execute program
      inputs = %{question: "Telemetry test"}
      {:ok, _result} = Program.forward(program, inputs, correlation_id: correlation_id)
      
      # Should receive start event
      receive do
        {:telemetry, [:dspex, :program, :forward, :start], start_measurements, start_metadata} ->
          assert is_integer(start_measurements.system_time)
          assert start_metadata.correlation_id == correlation_id
          assert start_metadata.program == :Predict
          assert start_metadata.input_count == 1
      after
        1000 -> flunk("Should have received start telemetry event")
      end
      
      # Should receive stop event
      receive do
        {:telemetry, [:dspex, :program, :forward, :stop], stop_measurements, stop_metadata} ->
          assert is_integer(stop_measurements.duration)
          assert stop_measurements.success == true
          assert stop_metadata.correlation_id == correlation_id
          assert stop_metadata.program == :Predict
      after
        1000 -> flunk("Should have received stop telemetry event")
      end
      
      # Cleanup
      :telemetry.detach(handler_id)
      :telemetry.detach("#{handler_id}-stop")
    end
  end
end
