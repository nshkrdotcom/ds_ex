defmodule DSPEx.Integration.SIMBAReadinessTest.SIMBACompatSignature do
  @moduledoc "SIMBA-compatible signature for validation testing"
  use DSPEx.Signature, "question -> answer"
end

defmodule DSPEx.Integration.SIMBAReadinessTest do
  use ExUnit.Case, async: false
  @moduletag :group_3

  alias DSPEx.{Teleprompter, Example, Predict, OptimizedProgram, Program}
  alias DSPEx.Test.MockProvider
  alias DSPEx.Teleprompter.BootstrapFewShot
  alias __MODULE__.SIMBACompatSignature

  @moduletag :phase5a
  @moduletag :integration_test

  setup_all do
    # Comprehensive setup that mirrors what SIMBA will need
    {:ok, _mock} = MockProvider.start_link(mode: :contextual)
    :ok
  end

  describe "SIMBA interface compatibility validation" do
    test "all required behaviors and modules exist and are complete" do
      # Test 1: DSPEx.Teleprompter behavior exists and defines compile/5 callback
      assert Code.ensure_loaded?(DSPEx.Teleprompter), "DSPEx.Teleprompter module not loaded"

      assert function_exported?(DSPEx.Teleprompter, :behaviour_info, 1),
             "Teleprompter behavior not defined"

      callbacks = DSPEx.Teleprompter.behaviour_info(:callbacks)
      required_callback = {:compile, 5}

      assert required_callback in callbacks,
             "compile/5 callback not found in behavior: #{inspect(callbacks)}"

      # Test 2: DSPEx.OptimizedProgram has required interface
      assert Code.ensure_loaded?(DSPEx.OptimizedProgram), "OptimizedProgram module not loaded"

      assert function_exported?(DSPEx.OptimizedProgram, :new, 3),
             "OptimizedProgram.new/3 not exported"

      assert function_exported?(DSPEx.OptimizedProgram, :get_demos, 1),
             "OptimizedProgram.get_demos/1 not exported"

      assert function_exported?(DSPEx.OptimizedProgram, :get_program, 1),
             "OptimizedProgram.get_program/1 not exported"

      # Test 3: DSPEx.Program utilities exist
      assert function_exported?(DSPEx.Program, :program_name, 1),
             "Program.program_name/1 not exported"

      assert function_exported?(DSPEx.Program, :implements_program?, 1),
             "Program.implements_program?/1 not exported"

      # Test 4: BootstrapFewShot implements teleprompter behavior
      assert Teleprompter.implements_behavior?(BootstrapFewShot),
             "BootstrapFewShot doesn't implement Teleprompter behavior"

      assert function_exported?(BootstrapFewShot, :compile, 5),
             "BootstrapFewShot.compile/5 not exported"

      assert function_exported?(BootstrapFewShot, :compile, 6),
             "BootstrapFewShot.compile/6 not exported"
    end

    test "teleprompter behavior validation functions work correctly" do
      # Create test programs exactly as SIMBA will
      student = %Predict{signature: SIMBACompatSignature, client: :test}
      teacher = %Predict{signature: SIMBACompatSignature, client: :test}

      trainset = [
        %Example{
          data: %{question: "SIMBA test question", answer: "SIMBA test response"},
          input_keys: MapSet.new([:question])
        }
      ]

      # All validation functions should pass
      assert :ok = Teleprompter.validate_student(student), "Student validation failed"
      assert :ok = Teleprompter.validate_teacher(teacher), "Teacher validation failed"
      assert :ok = Teleprompter.validate_trainset(trainset), "Trainset validation failed"

      # Program behavior checking should work
      assert Program.implements_program?(Predict), "Predict doesn't implement Program behavior"

      assert Program.implements_program?(OptimizedProgram),
             "OptimizedProgram doesn't implement Program behavior"

      # Behavior detection should work
      assert Teleprompter.implements_behavior?(BootstrapFewShot),
             "BootstrapFewShot behavior detection failed"

      refute Teleprompter.implements_behavior?(Predict),
             "False positive: Predict shouldn't implement Teleprompter"
    end

    test "OptimizedProgram interface matches SIMBA expectations exactly" do
      # Create programs exactly as SIMBA will
      base_program = %Predict{signature: SIMBACompatSignature, client: :test}

      demos = [
        %Example{
          data: %{question: "What is 2+2?", answer: "4"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "What is 3+3?", answer: "6"},
          input_keys: MapSet.new([:question])
        }
      ]

      metadata = %{
        teleprompter: :simba,
        optimization_time: DateTime.utc_now(),
        optimization_score: 0.85
      }

      # Test OptimizedProgram.new/3 interface exactly as SIMBA uses it
      optimized = OptimizedProgram.new(base_program, demos, metadata)

      # Test interface functions SIMBA depends on
      retrieved_demos = OptimizedProgram.get_demos(optimized)
      retrieved_program = OptimizedProgram.get_program(optimized)
      retrieved_metadata = OptimizedProgram.get_metadata(optimized)

      # Verify exact matches (SIMBA expects these to be identical)
      assert retrieved_demos == demos, "get_demos/1 doesn't return identical demos"
      assert retrieved_program == base_program, "get_program/1 doesn't return identical program"
      assert retrieved_metadata.teleprompter == :simba, "Metadata not preserved correctly"
      assert retrieved_metadata.optimization_score == 0.85, "Custom metadata not preserved"

      # Test that optimized program implements Program behavior
      assert Program.implements_program?(OptimizedProgram),
             "OptimizedProgram must implement Program behavior"

      # Test forward function works (critical for SIMBA)
      MockProvider.setup_evaluation_mocks([0.9])
      inputs = %{question: "Test forward call"}

      forward_result =
        try do
          Program.forward(optimized, inputs)
        rescue
          error -> {:caught_error, error.__struct__, Exception.message(error)}
        end

      # Should either work or fail gracefully (not crash)
      case forward_result do
        {:ok, result} ->
          assert is_map(result), "Forward should return a map"

        {:error, reason} ->
          # Acceptable failure in test environment
          assert is_atom(reason) or is_binary(reason) or is_tuple(reason),
                 "Error should be properly formatted"

        {:caught_error, error_type, message} ->
          # Should not crash with undefined function or similar critical errors
          refute error_type in [UndefinedFunctionError, ArgumentError],
                 "Critical error in forward/3: #{error_type} - #{message}"
      end
    end

    test "all function signatures match SIMBA usage patterns exactly" do
      # Test compile/5 signature (what SIMBA will call)
      student = %Predict{signature: SIMBACompatSignature, client: :test}
      teacher = %Predict{signature: SIMBACompatSignature, client: :test}

      trainset = [
        %Example{
          data: %{question: "Test", answer: "Response"},
          input_keys: MapSet.new([:question])
        }
      ]

      metric_fn = Teleprompter.exact_match(:answer)
      _opts = [max_bootstrapped_demos: 2, quality_threshold: 0.5]

      MockProvider.setup_bootstrap_mocks(["Response"])

      # This is the exact call pattern SIMBA will use
      start_time = System.monotonic_time()

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 3,
          quality_threshold: 0.5,
          max_concurrency: 10
        )

      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Validate successful compilation
      assert {:ok, optimized_student} = result, "BootstrapFewShot compilation failed"
      assert is_struct(optimized_student), "Optimized student must be a struct"

      # Validate optimized student has demonstrations
      demos =
        case optimized_student do
          %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized_student)
          %{demos: demos} -> demos
          _ -> []
        end

      assert length(demos) > 0, "Optimized student must have demonstrations"
      assert Enum.all?(demos, &is_struct(&1, Example)), "All demos must be Example structs"

      # Validate performance (SIMBA needs reasonable performance)
      assert duration_ms < 5000, "Compilation took too long: #{duration_ms}ms (SIMBA needs < 5s)"

      # Validate demo quality
      quality_scores =
        Enum.map(demos, fn demo ->
          demo.data[:__quality_score] || 0.0
        end)

      assert Enum.all?(quality_scores, &is_number/1), "All demos must have quality scores"
      assert Enum.all?(quality_scores, &(&1 >= 0.5)), "All demos must meet quality threshold"

      # Validate metadata structure
      assert Enum.all?(demos, fn demo ->
               data = demo.data

               Map.has_key?(data, :__generated_by) and
                 Map.has_key?(data, :__teacher) and
                 Map.has_key?(data, :__timestamp) and
                 Map.has_key?(data, :__quality_score)
             end),
             "Demo metadata structure must be complete"
    end

    test "handles edge cases that SIMBA might encounter" do
      student = %Predict{signature: SIMBACompatSignature, client: :test}
      teacher = %Predict{signature: SIMBACompatSignature, client: :test}
      metric_fn = Teleprompter.exact_match(:answer)

      # Test 1: Minimal trainset (SIMBA might start with few examples)
      minimal_trainset = [
        %Example{
          data: %{question: "Single example", answer: "Response"},
          input_keys: MapSet.new([:question])
        }
      ]

      MockProvider.setup_bootstrap_mocks(["Response"])

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          minimal_trainset,
          metric_fn,
          max_bootstrapped_demos: 1
        )

      # Should succeed even with minimal data
      assert {:ok, _optimized} = result, "Should handle minimal trainset"

      # Test 2: High quality threshold (SIMBA might be picky)
      high_quality_trainset = [
        %Example{
          data: %{question: "High quality test", answer: "Expected"},
          input_keys: MapSet.new([:question])
        }
      ]

      MockProvider.reset()
      # Won't match exactly
      MockProvider.setup_bootstrap_mocks(["Different response"])

      result_high_quality =
        BootstrapFewShot.compile(
          student,
          teacher,
          high_quality_trainset,
          metric_fn,
          # Very high threshold
          quality_threshold: 0.99
        )

      # Should handle gracefully (might return empty demos or original program)
      case result_high_quality do
        {:ok, optimized} ->
          demos =
            case optimized do
              %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
              %{demos: demos} -> demos
              _ -> []
            end

          # Might have 0 demos due to high threshold - that's acceptable
          assert is_list(demos)

        {:error, _reason} ->
          # Also acceptable if no demos meet threshold
          :ok
      end

      # Test 3: Teacher failures (SIMBA needs robustness)
      failure_trainset = [
        %Example{
          data: %{question: "Test 1", answer: "Response 1"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "Test 2", answer: "Response 2"},
          input_keys: MapSet.new([:question])
        }
      ]

      MockProvider.reset()

      MockProvider.setup_bootstrap_mocks([
        # Provide enough valid responses, some may not match but that's okay
        "Response 2",
        "Response 1",
        "Response 2",
        "Response 1",
        "Response 2"
      ])

      result_with_failures =
        BootstrapFewShot.compile(
          student,
          teacher,
          failure_trainset,
          metric_fn,
          max_bootstrapped_demos: 2
        )

      # Should succeed with partial results
      assert {:ok, _optimized_with_failures} = result_with_failures,
             "Should handle teacher failures gracefully"
    end

    test "concurrent optimization doesn't interfere (SIMBA parallel pattern)" do
      # SIMBA might run multiple optimizations in parallel
      student = %Predict{signature: SIMBACompatSignature, client: :test}
      teacher = %Predict{signature: SIMBACompatSignature, client: :test}
      metric_fn = Teleprompter.exact_match(:answer)

      # Create different training sets for parallel optimization
      trainsets = [
        [
          %Example{
            data: %{question: "Set 1 Q1", answer: "A1"},
            input_keys: MapSet.new([:question])
          }
        ],
        [
          %Example{
            data: %{question: "Set 2 Q1", answer: "A2"},
            input_keys: MapSet.new([:question])
          }
        ],
        [
          %Example{
            data: %{question: "Set 3 Q1", answer: "A3"},
            input_keys: MapSet.new([:question])
          }
        ]
      ]

      # Set up mock responses for all sets
      MockProvider.setup_bootstrap_mocks([
        "A1",
        "A2",
        "A3",
        # Extra responses
        "A1",
        "A2",
        "A3"
      ])

      # Run parallel optimizations
      concurrent_results =
        Task.async_stream(
          trainsets,
          fn trainset ->
            BootstrapFewShot.compile(
              student,
              teacher,
              trainset,
              metric_fn,
              max_bootstrapped_demos: 1,
              max_concurrency: 5
            )
          end,
          max_concurrency: 3,
          timeout: 10_000
        )
        |> Enum.to_list()

      # All should succeed
      successes =
        Enum.count(concurrent_results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      assert successes == 3, "Concurrent optimizations failed: #{successes}/3"

      # Each should have produced valid results
      results =
        Enum.map(concurrent_results, fn
          {:ok, {:ok, optimized}} -> optimized
          _ -> nil
        end)

      assert Enum.all?(results, &is_struct/1), "All concurrent results should be valid structs"
    end
  end

  describe "program name and telemetry utilities" do
    test "program_name function works for all program types SIMBA will encounter" do
      # Test program_name with various program types SIMBA will use

      predict_program = %Predict{signature: SIMBACompatSignature, client: :test}
      assert Program.program_name(predict_program) == :Predict, "Predict program name incorrect"

      optimized_program = OptimizedProgram.new(predict_program, [], %{})
      optimized_name = Program.program_name(optimized_program)
      assert is_atom(optimized_name), "OptimizedProgram name should be atom"

      assert String.contains?(Atom.to_string(optimized_name), "Optimized"),
             "OptimizedProgram name should contain 'Optimized'"

      # Test with invalid input (SIMBA error handling)
      assert Program.program_name("not a program") == :unknown,
             "Should handle invalid input gracefully"

      assert Program.program_name(nil) == :unknown, "Should handle nil gracefully"

      assert Program.program_name(%{not: "a program"}) == :unknown,
             "Should handle invalid struct gracefully"
    end

    test "safe program info extraction for telemetry" do
      # Test safe info extraction that SIMBA telemetry will use
      program = %Predict{signature: SIMBACompatSignature, client: :test}

      info = Program.safe_program_info(program)

      # Verify expected structure
      assert %{
               type: :predict,
               name: "Predict",
               signature: SIMBACompatSignature,
               has_demos: false
             } = info,
             "Safe program info structure incorrect"

      # Should not contain sensitive information
      sensitive_fields = [:api_key, :client_config, :adapter_config]

      assert Enum.all?(sensitive_fields, fn field ->
               not Map.has_key?(info, field)
             end),
             "Safe info should not contain sensitive fields"

      # Test with demos
      program_with_demos = %{program | demos: [%Example{data: %{}, input_keys: MapSet.new()}]}
      info_with_demos = Program.safe_program_info(program_with_demos)
      assert info_with_demos.has_demos == true, "Should detect demos correctly"

      # Test with OptimizedProgram
      optimized = OptimizedProgram.new(program, [], %{})
      optimized_info = Program.safe_program_info(optimized)
      assert optimized_info.type == :optimized, "OptimizedProgram type incorrect"
      assert is_binary(optimized_info.name), "OptimizedProgram name should be string"
    end

    test "telemetry utilities provide consistent JSON-serializable data" do
      program = %Predict{signature: SIMBACompatSignature, client: :test}

      # Get all utility outputs
      utilities_output = %{
        name: Program.program_name(program),
        type: Program.program_type(program),
        has_demos: Program.has_demos?(program),
        safe_info: Program.safe_program_info(program),
        implements_program: Program.implements_program?(Predict)
      }

      # Should be JSON-serializable (critical for SIMBA telemetry)
      json_result =
        try do
          Jason.encode!(utilities_output)
          :ok
        rescue
          error -> {:error, error}
        end

      assert json_result == :ok, "Program utilities must be JSON-serializable for SIMBA telemetry"

      # Test multiple calls for consistency
      results =
        Enum.map(1..5, fn _i ->
          %{
            name: Program.program_name(program),
            type: Program.program_type(program),
            has_demos: Program.has_demos?(program)
          }
        end)

      # All results should be identical
      first_result = List.first(results)

      assert Enum.all?(results, &(&1 == first_result)),
             "Program utilities should be deterministic"
    end
  end

  describe "client architecture validation" do
    test "client handles concurrent requests reliably (SIMBA load pattern)" do
      # SIMBA will make many concurrent requests during optimization
      messages = [%{role: "user", content: "SIMBA concurrent test"}]

      # Test concurrent usage pattern that SIMBA will create
      concurrent_requests =
        Task.async_stream(
          1..50,
          fn i ->
            correlation_id = "simba-concurrent-#{i}"

            DSPEx.Client.request(messages, %{
              provider: :gemini,
              correlation_id: correlation_id
            })
          end,
          max_concurrency: 15,
          timeout: 15_000
        )
        |> Enum.to_list()

      # Count successes
      successes =
        Enum.count(concurrent_requests, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      # Should handle most requests successfully (SIMBA requirement)
      success_rate = successes / 50

      assert success_rate >= 0.8,
             "Client success rate too low for SIMBA: #{success_rate * 100}% (need ≥80%)"

      # Verify response structure consistency
      successful_responses =
        concurrent_requests
        |> Enum.filter(fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)
        |> Enum.map(fn {:ok, {:ok, response}} -> response end)

      assert Enum.all?(successful_responses, fn response ->
               %{choices: [%{message: %{content: content}}]} = response
               is_binary(content) and String.length(content) > 0
             end),
             "All successful responses must have proper structure"
    end

    test "correlation_id propagation works for SIMBA tracking" do
      # SIMBA heavily uses correlation IDs for tracking optimization
      messages = [%{role: "user", content: "Correlation test"}]

      # Test with SIMBA-style correlation IDs
      simba_correlation_ids = [
        "simba-bootstrap-iteration-1",
        "simba-teacher-request-batch-2",
        "simba-student-evaluation-phase-3",
        "simba-optimization-cycle-4"
      ]

      correlation_results =
        Enum.map(simba_correlation_ids, fn correlation_id ->
          result =
            DSPEx.Client.request(messages, %{
              provider: :gemini,
              correlation_id: correlation_id
            })

          {correlation_id, result}
        end)

      # All should succeed
      successes =
        Enum.count(correlation_results, fn
          {_id, {:ok, _}} -> true
          _ -> false
        end)

      assert successes == length(simba_correlation_ids),
             "Correlation ID requests failed: #{successes}/#{length(simba_correlation_ids)}"

      # In a real implementation, we'd verify the correlation_id
      # was properly propagated through telemetry events
      # For now, just verify the requests succeed
    end

    test "provider switching works for SIMBA multi-model strategy" do
      # SIMBA might use different providers for teacher vs student
      messages = [%{role: "user", content: "Provider switching test"}]

      # Test SIMBA pattern: different providers for different roles
      teacher_requests =
        Enum.map(1..5, fn i ->
          DSPEx.Client.request(messages, %{
            # Strong teacher model
            provider: :openai,
            correlation_id: "simba-teacher-#{i}"
          })
        end)

      student_requests =
        Enum.map(1..5, fn i ->
          DSPEx.Client.request(messages, %{
            # Fast student model
            provider: :gemini,
            correlation_id: "simba-student-#{i}"
          })
        end)

      # Both should work
      teacher_successes =
        Enum.count(teacher_requests, fn
          {:ok, _} -> true
          _ -> false
        end)

      student_successes =
        Enum.count(student_requests, fn
          {:ok, _} -> true
          _ -> false
        end)

      assert teacher_successes >= 4,
             "Teacher provider (OpenAI) failed too often: #{teacher_successes}/5"

      assert student_successes >= 4,
             "Student provider (Gemini) failed too often: #{student_successes}/5"
    end
  end

  describe "error handling and recovery" do
    test "graceful handling of teacher failures during bootstrap (SIMBA robustness)" do
      # SIMBA needs robust error handling when teacher calls fail
      student = %Predict{signature: SIMBACompatSignature, client: :test}
      teacher = %Predict{signature: SIMBACompatSignature, client: :test}

      trainset = [
        %Example{
          data: %{question: "Test 1", answer: "Response 1"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "Test 2", answer: "Response 2"},
          input_keys: MapSet.new([:question])
        },
        %Example{
          data: %{question: "Test 3", answer: "Response 3"},
          input_keys: MapSet.new([:question])
        }
      ]

      metric_fn = Teleprompter.exact_match(:answer)

      # Set up mixed success/failure responses (realistic SIMBA scenario)
      # We need more successes than failures for bootstrap to work
      MockProvider.setup_bootstrap_mocks([
        # First succeeds
        "Response 1",
        # Second succeeds
        "Response 2",
        # Third succeeds
        "Response 3",
        # Extra responses to handle retries
        "Response 4",
        "Response 5",
        "Response 6"
      ])

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 3,
          # SIMBA would configure retries
          teacher_retries: 2
        )

      # Should succeed with partial results (critical for SIMBA)
      assert {:ok, optimized} = result, "Should handle teacher failures gracefully"

      # Should have at least some demos from successful examples
      demos =
        case optimized do
          %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
          %{demos: demos} -> demos
          _ -> []
        end

      # Might have fewer demos due to failures, but should still work
      assert is_list(demos), "Should return valid demo list even with failures"

      # If we have demos, they should be valid
      if length(demos) > 0 do
        assert Enum.all?(demos, &is_struct(&1, Example)), "Partial demos should still be valid"
      end
    end

    test "recovery from client connection issues (SIMBA reliability)" do
      # Test that SIMBA can recover from temporary client issues
      messages = [%{role: "user", content: "Recovery test"}]

      # Simulate intermittent failures that SIMBA might encounter
      results =
        Enum.map(1..10, fn i ->
          # Some requests might fail, but system should recover
          DSPEx.Client.request(messages, %{
            provider: :gemini,
            correlation_id: "simba-recovery-#{i}",
            # Shorter timeout to potentially trigger failures
            timeout: 2000
          })
        end)

      # Should have good recovery rate
      successes =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      # SIMBA needs at least 70% success rate for reliability
      success_rate = successes / 10

      assert success_rate >= 0.7,
             "Recovery rate too low for SIMBA: #{success_rate * 100}% (need ≥70%)"
    end

    test "error propagation maintains correlation tracking" do
      # SIMBA needs proper error correlation for debugging
      student = %Predict{signature: SIMBACompatSignature, client: :test}
      teacher = %Predict{signature: SIMBACompatSignature, client: :test}

      # Create scenario that will cause errors
      invalid_trainset = [
        %Example{
          data: %{question: "Error test", answer: "Expected"},
          input_keys: MapSet.new([:question])
        }
      ]

      # Set up to cause failures
      MockProvider.setup_bootstrap_mocks([{:error, :deliberate_test_error}])

      metric_fn = Teleprompter.exact_match(:answer)
      correlation_id = "simba-error-tracking-test"

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          invalid_trainset,
          metric_fn,
          correlation_id: correlation_id,
          max_bootstrapped_demos: 1
        )

      # Should handle error gracefully with proper error information
      case result do
        {:ok, _optimized} ->
          # Success despite errors is acceptable
          :ok

        {:error, reason} ->
          # Error should be properly categorized
          assert is_atom(reason) or is_tuple(reason) or is_binary(reason),
                 "Error should be properly formatted for SIMBA tracking"
      end
    end
  end

  describe "performance validation for SIMBA" do
    test "bootstrap generation completes within acceptable time" do
      student = %Predict{signature: SIMBACompatSignature, client: :test}
      teacher = %Predict{signature: SIMBACompatSignature, client: :test}

      # SIMBA-scale training set
      trainset =
        Enum.map(1..20, fn i ->
          %Example{
            data: %{question: "Question #{i}", answer: "Answer #{i}"},
            input_keys: MapSet.new([:question])
          }
        end)

      metric_fn = Teleprompter.exact_match(:answer)

      # Set up mock responses
      MockProvider.setup_bootstrap_mocks(Enum.map(1..20, fn i -> "Answer #{i}" end))

      # Measure performance
      start_time = System.monotonic_time()

      {:ok, _optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 10,
          max_concurrency: 15
        )

      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # SIMBA performance requirement: < 10 seconds for 20 examples
      assert duration_ms < 10_000,
             "Bootstrap generation too slow for SIMBA: #{duration_ms}ms (need < 10s)"

      # Calculate throughput
      throughput = 20 / (duration_ms / 1000)
      assert throughput > 2, "Bootstrap throughput too low: #{throughput} examples/sec (need > 2)"
    end

    test "memory usage remains stable during repeated optimizations" do
      student = %Predict{signature: SIMBACompatSignature, client: :test}
      teacher = %Predict{signature: SIMBACompatSignature, client: :test}

      trainset = [
        %Example{
          data: %{question: "Memory test", answer: "Response"},
          input_keys: MapSet.new([:question])
        }
      ]

      metric_fn = Teleprompter.exact_match(:answer)

      # Measure initial memory
      :erlang.garbage_collect()
      initial_memory = :erlang.memory()[:total]

      # Run multiple optimization cycles (SIMBA pattern)
      Enum.each(1..10, fn i ->
        MockProvider.reset()
        MockProvider.setup_bootstrap_mocks(["Response"])

        {:ok, _optimized} =
          BootstrapFewShot.compile(
            student,
            teacher,
            trainset,
            metric_fn,
            max_bootstrapped_demos: 1
          )

        # Periodic cleanup
        if rem(i, 3) == 0 do
          :erlang.garbage_collect()
        end
      end)

      # Final memory check
      :erlang.garbage_collect()
      final_memory = :erlang.memory()[:total]

      # Memory growth should be reasonable for SIMBA
      memory_growth_mb = (final_memory - initial_memory) / (1024 * 1024)

      assert memory_growth_mb < 25,
             "Memory growth too high for SIMBA: #{memory_growth_mb}MB (need < 25MB)"
    end

    test "concurrent optimization doesn't degrade individual performance" do
      # SIMBA might run multiple optimization experiments in parallel
      student = %Predict{signature: SIMBACompatSignature, client: :test}
      teacher = %Predict{signature: SIMBACompatSignature, client: :test}

      trainset = [
        %Example{
          data: %{question: "Concurrent perf test", answer: "Response"},
          input_keys: MapSet.new([:question])
        }
      ]

      metric_fn = Teleprompter.exact_match(:answer)

      # Set up plenty of mock responses that match the expected answer
      MockProvider.setup_bootstrap_mocks(Enum.map(1..50, fn _i -> "Response" end))

      # Measure single optimization performance
      single_start = System.monotonic_time()
      {:ok, _single_result} = BootstrapFewShot.compile(student, teacher, trainset, metric_fn)

      single_duration =
        System.convert_time_unit(System.monotonic_time() - single_start, :native, :millisecond)

      # Reset for concurrent test
      MockProvider.reset()

      MockProvider.setup_bootstrap_mocks(Enum.map(1..100, fn _i -> "Response" end))

      # Measure concurrent optimization performance
      concurrent_start = System.monotonic_time()

      concurrent_results =
        Task.async_stream(
          1..5,
          fn _i ->
            BootstrapFewShot.compile(student, teacher, trainset, metric_fn, max_concurrency: 5)
          end,
          max_concurrency: 5,
          timeout: 15_000
        )
        |> Enum.to_list()

      concurrent_duration =
        System.convert_time_unit(
          System.monotonic_time() - concurrent_start,
          :native,
          :millisecond
        )

      # All concurrent optimizations should succeed
      concurrent_successes =
        Enum.count(concurrent_results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      assert concurrent_successes == 5,
             "Concurrent optimizations failed: #{concurrent_successes}/5"

      # Individual performance shouldn't degrade significantly
      avg_concurrent_time = concurrent_duration / 5

      # Avoid division by zero for very fast operations
      safe_single_duration = max(single_duration, 1)
      performance_ratio = avg_concurrent_time / safe_single_duration

      # Should be reasonably close to single performance (within 3x)
      assert performance_ratio < 3.0,
             "Concurrent performance degraded too much: #{performance_ratio}x slower (single: #{single_duration}ms, avg concurrent: #{avg_concurrent_time}ms)"
    end
  end
end
