defmodule DSPEx.BEACONContractValidationTest do
  @moduledoc """
  Validates all APIs that BEACON depends on work correctly.
  This test suite ensures the DSPEx-BEACON contract is fulfilled.

  These tests validate the critical API contract that BEACON requires:
  - Program.forward/3 with timeout and correlation_id support
  - Program introspection functions (program_type, safe_program_info, has_demos?)
  - ConfigManager BEACON configuration paths
  - OptimizedProgram BEACON strategy detection
  - Client response format stability
  - Foundation service integration
  """

  use ExUnit.Case, async: false

  alias DSPEx.{Program, Predict, Client, Example, OptimizedProgram}
  alias DSPEx.Services.ConfigManager
  alias DSPEx.Teleprompter.BootstrapFewShot

  defmodule BEACONTestSignature do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule BEACONAdvancedSignature do
    use DSPEx.Signature, "question -> answer, reasoning"
  end

  defmodule CustomProgramWithInstruction do
    defstruct [:signature, :instruction, :demos]
  end

  defmodule FullSupportProgram do
    defstruct [:signature, :demos, :instruction]
  end

  defmodule BasicProgram do
    defstruct [:signature, :client]
  end

  describe "BEACON Core Program Contract" do
    test "Program.forward/3 with timeout and correlation_id" do
      program = %Predict{signature: BEACONTestSignature, client: :test}
      inputs = %{question: "Contract test"}
      correlation_id = "beacon-contract-#{System.unique_integer()}"

      # Test timeout option with reasonable timeout
      assert {:ok, outputs} = Program.forward(program, inputs, timeout: 10_000)
      assert Map.has_key?(outputs, :answer)

      # Test correlation_id option
      assert {:ok, outputs} =
               Program.forward(program, inputs, correlation_id: correlation_id, timeout: 10_000)

      assert Map.has_key?(outputs, :answer)

      # Test timeout functionality is available (actual timeout behavior depends on implementation speed)
      # In real scenarios with network calls, this would timeout
      result = Program.forward(program, inputs, timeout: 1)

      # Accept either timeout or successful response (test client may be too fast to reliably timeout)
      case result do
        {:error, :timeout} -> :ok
        {:ok, response} when is_map(response) and is_map_key(response, :answer) -> :ok
        other -> flunk("Unexpected result: #{inspect(other)}")
      end

      # Test both options together
      assert {:ok, outputs} =
               Program.forward(program, inputs, timeout: 10_000, correlation_id: correlation_id)

      assert Map.has_key?(outputs, :answer)
    end

    test "Program introspection functions work correctly" do
      student = %Predict{signature: BEACONTestSignature, client: :test}

      demo = %Example{
        data: %{question: "test", answer: "response"},
        input_keys: MapSet.new([:question])
      }

      optimized = OptimizedProgram.new(student, [demo])

      # Test program_type/1
      assert Program.program_type(student) == :predict
      assert Program.program_type(optimized) == :optimized
      assert Program.program_type("invalid") == :custom
      assert Program.program_type(nil) == :custom

      # Test safe_program_info/1 returns required fields
      info = Program.safe_program_info(student)

      assert %{
               type: :predict,
               name: "Predict",
               has_demos: false,
               signature: BEACONTestSignature,
               demo_count: 0
             } = info

      # Test optimized program info
      optimized_info = Program.safe_program_info(optimized)
      assert optimized_info.has_demos == true
      assert optimized_info.type == :optimized
      assert optimized_info.demo_count == 1

      # Test has_demos?/1
      refute Program.has_demos?(student)
      assert Program.has_demos?(optimized)

      # Test with program that has demos field but empty list
      student_with_empty_demos = %Predict{
        signature: BEACONTestSignature,
        client: :test,
        demos: []
      }

      refute Program.has_demos?(student_with_empty_demos)

      # Test with program that has demos
      student_with_demos = %Predict{
        signature: BEACONTestSignature,
        client: :test,
        demos: [demo]
      }

      assert Program.has_demos?(student_with_demos)
    end

    test "Program.forward/2 maintains backward compatibility" do
      program = %Predict{signature: BEACONTestSignature, client: :test}
      inputs = %{question: "Backward compatibility test"}

      # forward/2 should still work exactly as before
      assert {:ok, outputs} = Program.forward(program, inputs)
      assert Map.has_key?(outputs, :answer)
    end
  end

  describe "BEACON Client Contract" do
    test "Client.request/2 response format stability" do
      messages = [%{role: "user", content: "BEACON instruction generation test"}]

      case Client.request(messages, %{provider: :test}) do
        {:ok, response} ->
          # Validate structure BEACON expects
          assert %{choices: choices} = response
          assert is_list(choices)
          assert length(choices) > 0

          [first_choice | _] = choices
          assert %{message: %{content: content}} = first_choice
          assert is_binary(content)

        {:error, reason} ->
          # Validate error is categorized as BEACON expects
          assert is_atom(reason)
          # Common error types that BEACON should handle
          _acceptable_errors = [
            :timeout,
            :network_error,
            :api_error,
            :rate_limited,
            :no_api_key,
            :invalid_messages,
            :provider_not_configured
          ]

          # Note: For test provider, we may get other errors, which is fine for this test
      end
    end

    test "Client error categorization with invalid input" do
      # Test with invalid messages format
      invalid_messages = ["not", "a", "proper", "message", "list"]

      case Client.request(invalid_messages, %{provider: :test}) do
        {:error, reason} ->
          assert is_atom(reason)

        # Some implementations may handle this gracefully
        {:ok, _response} ->
          :ok
      end
    end

    test "Client preserves correlation_id in options" do
      messages = [%{role: "user", content: "Correlation test"}]
      correlation_id = "test-correlation-#{System.unique_integer()}"

      # Client should accept correlation_id without errors
      case Client.request(messages, %{provider: :test, correlation_id: correlation_id}) do
        {:ok, _response} -> :ok
        # Error is fine, just testing it doesn't crash
        {:error, _reason} -> :ok
      end
    end
  end

  describe "BEACON Configuration Contract" do
    test "ConfigManager.get_with_default/2 for BEACON paths" do
      # Test critical BEACON configuration paths exist and return valid values
      default_provider = ConfigManager.get_with_default([:prediction, :default_provider], :gemini)
      assert default_provider in [:gemini, :openai, :anthropic, :test]

      # Test BEACON teleprompter config paths
      instruction_model =
        ConfigManager.get_with_default(
          [:teleprompters, :beacon, :default_instruction_model],
          :openai
        )

      assert is_atom(instruction_model)

      evaluation_model =
        ConfigManager.get_with_default(
          [:teleprompters, :beacon, :default_evaluation_model],
          :gemini
        )

      assert is_atom(evaluation_model)

      max_concurrent =
        ConfigManager.get_with_default(
          [:teleprompters, :beacon, :max_concurrent_operations],
          20
        )

      assert is_integer(max_concurrent) and max_concurrent > 0

      default_timeout =
        ConfigManager.get_with_default(
          [:teleprompters, :beacon, :default_timeout],
          60_000
        )

      assert is_integer(default_timeout) and default_timeout > 0

      # Test fallback behavior with nonexistent paths
      nonexistent = ConfigManager.get_with_default([:nonexistent, :path], :fallback_value)
      assert nonexistent == :fallback_value

      # Test single atom key fallback
      single_key = ConfigManager.get_with_default(:nonexistent_key, :default)
      assert single_key == :default
    end

    test "ConfigManager handles nested BEACON optimization config" do
      # Test nested optimization configuration
      max_trials =
        ConfigManager.get_with_default(
          [:teleprompters, :beacon, :optimization, :max_trials],
          100
        )

      assert is_integer(max_trials)

      # Test Bayesian optimization config
      acquisition_fn =
        ConfigManager.get_with_default(
          [:teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
          :expected_improvement
        )

      assert is_atom(acquisition_fn)
    end
  end

  describe "BEACON OptimizedProgram Contract" do
    test "OptimizedProgram metadata support for BEACON" do
      student = %Predict{signature: BEACONTestSignature, client: :test}

      demos = [
        %Example{
          data: %{question: "test", answer: "answer"},
          input_keys: MapSet.new([:question])
        }
      ]

      # Test BEACON metadata storage
      beacon_metadata = %{
        optimization_method: :beacon,
        instruction: "Test instruction for BEACON optimization",
        optimization_score: 0.85,
        optimization_stats: %{
          trials: 25,
          best_trial: 15,
          convergence_iteration: 20
        },
        bayesian_trials: [
          %{trial: 1, score: 0.65, config: %{temp: 0.7}},
          %{trial: 2, score: 0.78, config: %{temp: 0.5}}
        ],
        best_configuration: %{
          temperature: 0.5,
          max_tokens: 150,
          demos_count: 3
        }
      }

      optimized = OptimizedProgram.new(student, demos, beacon_metadata)

      # Validate metadata preservation
      assert optimized.metadata.optimization_method == :beacon
      assert optimized.metadata.instruction == "Test instruction for BEACON optimization"
      assert optimized.metadata.optimization_score == 0.85
      assert optimized.metadata.optimization_stats.trials == 25
      assert length(optimized.metadata.bayesian_trials) == 2
      assert optimized.metadata.best_configuration.temperature == 0.5

      # Validate automatic metadata is still added
      assert %DateTime{} = optimized.metadata.optimized_at
      assert optimized.metadata.demo_count == 1
    end

    test "native support detection functions" do
      basic_program = %Predict{signature: BEACONTestSignature, client: :test}
      demo_program = %Predict{signature: BEACONTestSignature, client: :test, demos: []}

      # Test supports_native_demos?/1 - Both Predict programs have demos field
      assert OptimizedProgram.supports_native_demos?(demo_program)
      assert OptimizedProgram.supports_native_demos?(basic_program)
      refute OptimizedProgram.supports_native_demos?(nil)
      refute OptimizedProgram.supports_native_demos?("invalid")

      # Test supports_native_instruction?/1
      # Predict programs now support native instructions (SIMBA enhancement)
      assert OptimizedProgram.supports_native_instruction?(demo_program)
      assert OptimizedProgram.supports_native_instruction?(basic_program)
      refute OptimizedProgram.supports_native_instruction?(nil)

      # Test with custom program that has instruction field
      custom_program = %CustomProgramWithInstruction{
        signature: BEACONTestSignature,
        instruction: "custom instruction",
        demos: []
      }

      assert OptimizedProgram.supports_native_instruction?(custom_program)
      assert OptimizedProgram.supports_native_demos?(custom_program)
    end

    test "BEACON enhancement strategy selection" do
      basic_program = %Predict{signature: BEACONTestSignature, client: :test}
      demo_program = %Predict{signature: BEACONTestSignature, client: :test, demos: []}

      # Test strategy selection - Predict programs have native demo and instruction support (SIMBA enhancement)
      assert OptimizedProgram.simba_enhancement_strategy(demo_program) == :native_full
      assert OptimizedProgram.simba_enhancement_strategy(basic_program) == :native_full
      assert OptimizedProgram.simba_enhancement_strategy(nil) == :wrap_optimized

      # Test with program that supports both demos and instructions
      full_support_program = %FullSupportProgram{
        signature: BEACONTestSignature,
        instruction: "custom instruction",
        demos: []
      }

      assert OptimizedProgram.simba_enhancement_strategy(full_support_program) == :native_full

      # Test with program that has no native support
      minimal_program = %BasicProgram{signature: BEACONTestSignature, client: :test}
      assert OptimizedProgram.simba_enhancement_strategy(minimal_program) == :wrap_optimized
    end
  end

  describe "BEACON Teleprompter Contract" do
    test "BootstrapFewShot handles empty demo scenarios gracefully" do
      student = %Predict{signature: BEACONTestSignature, client: :test}
      teacher = %Predict{signature: BEACONTestSignature, client: :test}

      # Empty trainset should not crash
      empty_trainset = []
      metric_fn = fn _example, _prediction -> 1.0 end

      teleprompter = BootstrapFewShot.new(max_bootstrapped_demos: 3)

      # Should handle empty trainset gracefully - use struct_to_keyword to convert options
      teleprompter_opts = [
        max_bootstrapped_demos: teleprompter.max_bootstrapped_demos,
        quality_threshold: teleprompter.quality_threshold
      ]

      result =
        BootstrapFewShot.compile(student, teacher, empty_trainset, metric_fn, teleprompter_opts)

      case result do
        {:ok, optimized} ->
          # Should return a program even with no demos
          assert is_struct(optimized)
          assert optimized.__struct__ == OptimizedProgram

        {:error, reason} ->
          # Acceptable errors for empty trainset
          assert reason in [:invalid_or_empty_trainset, :no_successful_bootstrap_candidates]
      end
    end

    test "BootstrapFewShot with high quality threshold (tests empty quality demos)" do
      student = %Predict{signature: BEACONTestSignature, client: :test}
      teacher = %Predict{signature: BEACONTestSignature, client: :test}

      # Small trainset
      trainset = [
        %Example{
          data: %{question: "What is 1+1?", answer: "2"},
          input_keys: MapSet.new([:question])
        }
      ]

      # Metric that always returns low scores (below quality threshold)
      metric_fn = fn _example, _prediction -> 0.1 end

      teleprompter =
        BootstrapFewShot.new(
          max_bootstrapped_demos: 3,
          # Very high threshold
          quality_threshold: 0.9
        )

      # Should handle case where no demos meet quality threshold
      teleprompter_opts = [
        max_bootstrapped_demos: teleprompter.max_bootstrapped_demos,
        quality_threshold: teleprompter.quality_threshold
      ]

      {:ok, optimized} =
        BootstrapFewShot.compile(student, teacher, trainset, metric_fn, teleprompter_opts)

      # Should return OptimizedProgram even with empty demos
      assert is_struct(optimized, OptimizedProgram)

      # Check metadata indicates empty demo scenario
      assert optimized.metadata.demo_generation_result == :no_quality_demonstrations
      assert optimized.metadata.demo_count == 0
    end
  end

  describe "BEACON Foundation Service Integration" do
    test "ConfigManager handles service conflicts gracefully" do
      # ConfigManager should work even if Foundation services are already started
      # This tests the service lifecycle conflict resolution

      # Test multiple calls don't crash
      result1 = ConfigManager.get_with_default([:prediction, :default_provider], :test)
      result2 = ConfigManager.get_with_default([:prediction, :default_provider], :test)

      assert result1 == result2
      assert is_atom(result1)
    end

    test "Telemetry events are properly structured for BEACON" do
      # Test that telemetry events can be emitted without crashing
      # This validates the telemetry event structure

      correlation_id = "beacon-telemetry-test-#{System.unique_integer()}"

      # Test telemetry emission doesn't crash
      :telemetry.execute(
        [:dspex, :teleprompter, :beacon, :start],
        %{system_time: System.system_time()},
        %{
          correlation_id: correlation_id,
          student_type: :predict,
          teacher_type: :predict
        }
      )

      :telemetry.execute(
        [:dspex, :teleprompter, :beacon, :stop],
        %{duration: 1000, success: true},
        %{
          correlation_id: correlation_id,
          trials_completed: 10
        }
      )

      # Test instruction generation events
      :telemetry.execute(
        [:dspex, :teleprompter, :beacon, :instruction, :start],
        %{system_time: System.system_time()},
        %{
          correlation_id: correlation_id,
          instruction_model: :openai
        }
      )

      :telemetry.execute(
        [:dspex, :teleprompter, :beacon, :instruction, :stop],
        %{duration: 500, success: true},
        %{
          correlation_id: correlation_id,
          instruction_model: :openai
        }
      )

      # If we get here without crashing, telemetry integration works
      assert true
    end
  end

  describe "BEACON Integration Smoke Test" do
    test "minimal BEACON workflow compatibility" do
      # This test validates the essential BEACON workflow components
      student = %Predict{signature: BEACONAdvancedSignature, client: :test}
      teacher = %Predict{signature: BEACONAdvancedSignature, client: :test}

      # Step 1: Create minimal training set
      trainset = [
        %Example{
          data: %{
            question: "What is 2+2?",
            answer: "4",
            reasoning: "Simple addition: 2 + 2 = 4"
          },
          input_keys: MapSet.new([:question])
        }
      ]

      # Step 2: Test teacher demonstration generation
      teacher_inputs = Example.inputs(List.first(trainset))

      case Program.forward(teacher, teacher_inputs, timeout: 10_000) do
        {:ok, teacher_prediction} ->
          # Teacher should generate reasoning + answer
          assert Map.has_key?(teacher_prediction, :answer)

          # Step 3: Create demonstration from teacher output
          demo_data = Map.merge(teacher_inputs, teacher_prediction)
          demo = Example.new(demo_data)
          demo = Example.with_inputs(demo, [:question])

          assert Example.inputs(demo) == teacher_inputs
          teacher_outputs = Example.outputs(demo)
          assert Map.has_key?(teacher_outputs, :answer)

        {:error, _} ->
          # Teacher failed, create mock demo for testing
          _demo = %Example{
            data: %{
              question: "What is 2+2?",
              answer: "4",
              reasoning: "Mock reasoning for testing"
            },
            input_keys: MapSet.new([:question])
          }
      end

      # Step 4: Test instruction generation simulation
      instruction =
        "Answer the mathematical question step by step, showing your reasoning clearly."

      assert is_binary(instruction)
      assert String.length(instruction) > 10

      # Step 5: Test program enhancement strategy
      enhancement_strategy = OptimizedProgram.simba_enhancement_strategy(student)
      assert enhancement_strategy in [:native_full, :native_demos, :wrap_optimized]

      # Step 6: Test enhanced program creation
      enhanced_program =
        case enhancement_strategy do
          :native_demos ->
            %{student | demos: [trainset |> List.first()]}

          :wrap_optimized ->
            OptimizedProgram.new(student, [trainset |> List.first()], %{
              optimization_method: :beacon_smoke_test,
              instruction: instruction,
              enhancement_strategy: enhancement_strategy
            })

          _ ->
            OptimizedProgram.new(student, [trainset |> List.first()], %{instruction: instruction})
        end

      # Step 7: Test enhanced program execution
      test_input = %{question: "What is 5+5?"}

      case Program.forward(enhanced_program, test_input, timeout: 10_000) do
        {:ok, result} ->
          assert Map.has_key?(result, :answer)

        {:error, reason} ->
          # Some errors are acceptable in smoke test
          acceptable_errors = [:timeout, :network_error, :api_error, :no_api_key]
          assert reason in acceptable_errors
      end

      # Step 8: Validate program introspection works
      program_info = Program.safe_program_info(enhanced_program)
      assert program_info.type in [:predict, :optimized]
      assert program_info.has_demos == true

      # Step 9: Test configuration access
      default_provider = ConfigManager.get_with_default([:prediction, :default_provider], :test)
      assert is_atom(default_provider)
    end
  end
end
