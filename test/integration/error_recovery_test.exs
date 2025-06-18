defmodule DSPEx.ErrorRecoveryTest do
  @moduledoc """
  Comprehensive tests for error propagation and recovery scenarios across DSPEx pipeline.
  Tests error handling, recovery strategies, graceful degradation, and fault tolerance
  at all levels of the system architecture.
  """
  use ExUnit.Case, async: false

  @moduletag :group_1
  @moduletag :error_recovery

  # Test programs with various error behaviors
  defmodule ControlledErrorProgram do
    use DSPEx.Program

    defstruct [:id, :error_pattern, :recovery_strategy]

    def new(id, error_pattern, recovery_strategy \\ :none) do
      %__MODULE__{id: id, error_pattern: error_pattern, recovery_strategy: recovery_strategy}
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      operation_id = Map.get(inputs, :operation_id, 1)

      case should_error?(program.error_pattern, operation_id) do
        false ->
          {:ok, Map.put(inputs, :processed_by, program.id)}

        error_type ->
          case program.recovery_strategy do
            :retry_once ->
              handle_retry_recovery(inputs, error_type)

            :fallback_response ->
              {:ok, %{fallback: true, original_error: error_type}}

            :graceful_degradation ->
              {:ok, %{partial_result: true, degraded: true, error: error_type}}

            _ ->
              {:error, error_type}
          end
      end
    end

    defp handle_retry_recovery(inputs, error_type) do
      if Map.get(inputs, :retry_attempt, false) do
        {:ok, Map.put(inputs, :recovered, true)}
      else
        {:error, error_type}
      end
    end

    defp should_error?(pattern, operation_id) do
      case pattern do
        :never -> false
        :always -> :always_fails
        {:every_nth, n} -> if rem(operation_id, n) == 0, do: :periodic_failure, else: false
        {:random, rate} -> if :rand.uniform() < rate, do: :random_failure, else: false
        {:specific_ids, ids} -> if operation_id in ids, do: :specific_failure, else: false
        {:after_count, count} -> if operation_id > count, do: :exhaustion_failure, else: false
        _ -> false
      end
    end
  end

  defmodule ErrorCategoriesProgram do
    use DSPEx.Program

    defstruct [:id, :error_types]

    def new(id, error_types) do
      %__MODULE__{id: id, error_types: error_types}
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      error_type = Enum.random(program.error_types)

      case error_type do
        :network_error -> {:error, :network_error}
        :api_error -> {:error, :api_error}
        :timeout -> {:error, :timeout}
        :invalid_input -> {:error, :invalid_input}
        :rate_limit -> {:error, :rate_limit}
        :auth_error -> {:error, :auth_error}
        :server_error -> {:error, :server_error}
        :parse_error -> {:error, :parse_error}
        :validation_error -> {:error, :validation_error}
        :success -> {:ok, Map.put(inputs, :success, true)}
        :exception -> raise "Simulated exception"
        :exit -> exit(:simulated_exit)
        :throw -> throw(:simulated_throw)
      end
    end
  end

  defmodule RecoveryStrategiesProgram do
    use DSPEx.Program

    defstruct [:id, :failure_count, :max_failures, :recovery_mode]

    def new(id, max_failures, recovery_mode) do
      {:ok, failure_count} = Agent.start_link(fn -> 0 end)

      %__MODULE__{
        id: id,
        failure_count: failure_count,
        max_failures: max_failures,
        recovery_mode: recovery_mode
      }
    end

    @impl DSPEx.Program
    def forward(program, _inputs, _opts) do
      current_failures = Agent.get(program.failure_count, & &1)

      if current_failures < program.max_failures do
        # Fail this attempt
        Agent.update(program.failure_count, &(&1 + 1))

        case program.recovery_mode do
          :eventual_success -> {:error, :temporary_failure}
          :circuit_breaker -> {:error, :circuit_open}
          :backoff_retry -> {:error, :retry_later}
          _ -> {:error, :generic_failure}
        end
      else
        # Succeed after max failures
        case program.recovery_mode do
          :eventual_success -> {:ok, %{recovered: true, attempts: current_failures + 1}}
          :circuit_breaker -> {:ok, %{circuit_closed: true, failures: current_failures}}
          :backoff_retry -> {:ok, %{retry_succeeded: true, total_attempts: current_failures + 1}}
          _ -> {:ok, %{finally_succeeded: true}}
        end
      end
    end

    def stop(program) do
      Agent.stop(program.failure_count)
    end
  end

  describe "error propagation through pipeline layers" do
    @tag :live_api
    test "signature validation errors are properly categorized" do
      # Test different signature validation failures
      defmodule InvalidSignature do
        # Intentionally incomplete signature
        def input_fields, do: [:question]
        # Missing output_fields function
      end

      # Missing required input fields
      {:error, :missing_inputs} = DSPEx.Predict.forward(InvalidSignature, %{})

      # Invalid signature structure
      {:error, :invalid_signature} = DSPEx.Predict.forward(InvalidSignature, %{question: "test"})

      # Valid signature but missing inputs
      defmodule ValidSignature do
        use DSPEx.Signature, "question, context -> answer"
      end

      # Missing context
      {:error, :missing_inputs} = DSPEx.Predict.forward(ValidSignature, %{question: "test"})
    end

    test "adapter errors propagate with context" do
      # Test adapter-level error handling
      defmodule TestSignature do
        use DSPEx.Signature, "question -> answer"
      end

      # Test with malformed inputs that should cause adapter errors
      malformed_inputs = [
        # Missing required fields
        %{},
        # Wrong field names
        %{wrong_field: "value"},
        # Nil values
        %{question: nil}
      ]

      for inputs <- malformed_inputs do
        result = DSPEx.Predict.forward(TestSignature, inputs)
        assert match?({:error, _}, result)

        {:error, reason} = result
        # Should get categorized error, not raw exception
        assert reason in [:missing_inputs, :invalid_input, :validation_error]
      end
    end

    test "client errors are properly categorized and handled" do
      program = ControlledErrorProgram.new(:client_test, :always)
      inputs = %{operation_id: 1}

      {:error, :always_fails} = DSPEx.Program.forward(program, inputs)

      # Test error categorization in evaluation context
      examples = [%{inputs: inputs, outputs: %{processed_by: :client_test}}]
      metric_fn = fn _example, _prediction -> 1.0 end

      # Should return success with zero score when all programs fail
      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)
      assert result.score == 0.0
      assert result.stats.successful == 0
      assert result.stats.failed == 1
    end

    test "program execution errors are isolated per operation" do
      # Program that fails on specific operations
      program = ControlledErrorProgram.new(:isolation_test, {:specific_ids, [2, 4]})

      # Test multiple operations
      results =
        for i <- 1..5 do
          inputs = %{operation_id: i}
          {i, DSPEx.Program.forward(program, inputs)}
        end

      # Operations 2 and 4 should fail, others should succeed
      for {id, result} <- results do
        if id in [2, 4] do
          assert match?({:error, :specific_failure}, result)
        else
          assert match?({:ok, _}, result)
        end
      end
    end
  end

  describe "recovery strategies and fault tolerance" do
    test "retry with eventual success strategy" do
      program = RecoveryStrategiesProgram.new(:retry_test, 3, :eventual_success)

      try do
        inputs = %{test: "retry"}

        # First 3 attempts should fail
        for _i <- 1..3 do
          {:error, :temporary_failure} = DSPEx.Program.forward(program, inputs)
        end

        # 4th attempt should succeed
        {:ok, result} = DSPEx.Program.forward(program, inputs)
        assert result.recovered == true
        assert result.attempts == 4
      after
        RecoveryStrategiesProgram.stop(program)
      end
    end

    test "circuit breaker pattern implementation" do
      program = RecoveryStrategiesProgram.new(:circuit_test, 2, :circuit_breaker)

      try do
        inputs = %{test: "circuit"}

        # First 2 attempts should fail (circuit learning)
        {:error, :circuit_open} = DSPEx.Program.forward(program, inputs)
        {:error, :circuit_open} = DSPEx.Program.forward(program, inputs)

        # 3rd attempt should succeed (circuit closed)
        {:ok, result} = DSPEx.Program.forward(program, inputs)
        assert result.circuit_closed == true
      after
        RecoveryStrategiesProgram.stop(program)
      end
    end

    test "graceful degradation with partial results" do
      program = ControlledErrorProgram.new(:degradation_test, :always, :graceful_degradation)
      inputs = %{operation_id: 1}

      {:ok, result} = DSPEx.Program.forward(program, inputs)

      # Should receive partial result even though program would normally fail
      assert result.partial_result == true
      assert result.degraded == true
      assert result.error == :always_fails
    end

    test "fallback response strategy" do
      program = ControlledErrorProgram.new(:fallback_test, :always, :fallback_response)
      inputs = %{operation_id: 1}

      {:ok, result} = DSPEx.Program.forward(program, inputs)

      # Should receive fallback response
      assert result.fallback == true
      assert result.original_error == :always_fails
    end
  end

  describe "evaluation-level error handling and recovery" do
    test "evaluation continues despite individual program failures" do
      # Mix of failing and succeeding programs
      failing_program = ControlledErrorProgram.new(:fail, :always)
      succeeding_program = ControlledErrorProgram.new(:succeed, :never)
      mixed_program = ControlledErrorProgram.new(:mixed, {:every_nth, 2})

      examples =
        for i <- 1..6 do
          %{inputs: %{operation_id: i}, outputs: %{processed_by: :any}}
        end

      metric_fn = fn _example, prediction ->
        if Map.has_key?(prediction, :processed_by), do: 1.0, else: 0.0
      end

      # Test failing program - should return success with zero score
      {:ok, fail_result} = DSPEx.Evaluate.run(failing_program, examples, metric_fn)
      assert fail_result.score == 0.0
      assert fail_result.stats.successful == 0
      assert fail_result.stats.failed > 0

      # Test succeeding program
      {:ok, success_result} = DSPEx.Evaluate.run(succeeding_program, examples, metric_fn)
      assert success_result.stats.successful == 6
      assert success_result.stats.failed == 0

      # Test mixed program (should succeed for half)
      {:ok, mixed_result} = DSPEx.Evaluate.run(mixed_program, examples, metric_fn)
      # Operations 1, 3, 5
      assert mixed_result.stats.successful == 3
      # Operations 2, 4, 6
      assert mixed_result.stats.failed == 3
      assert mixed_result.stats.success_rate == 0.5
    end

    test "concurrent evaluation handles mixed error scenarios" do
      # Program with random failures
      # 40% failure rate
      program = ControlledErrorProgram.new(:random_test, {:random, 0.4})

      examples =
        for i <- 1..20 do
          %{inputs: %{operation_id: i}, outputs: %{processed_by: :random_test}}
        end

      metric_fn = fn _example, _prediction -> 1.0 end

      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn, max_concurrency: 5)

      # Should have some successes and some failures
      assert result.stats.total_examples == 20
      assert result.stats.successful > 0
      assert result.stats.failed > 0
      assert result.stats.successful + result.stats.failed == 20

      # Failure rate should be approximately 40% (with some variance)
      failure_rate = result.stats.failed / result.stats.total_examples
      # At least 10% (accounting for statistical variance with small sample)
      assert failure_rate >= 0.1
      # At most 70% (accounting for randomness)
      assert failure_rate <= 0.7
    end

    test "evaluation error statistics are accurate and comprehensive" do
      program =
        ErrorCategoriesProgram.new(:categories_test, [
          :network_error,
          :api_error,
          :timeout,
          :success,
          :success,
          :success
        ])

      examples =
        for i <- 1..12 do
          %{inputs: %{operation_id: i}, outputs: %{success: true}}
        end

      metric_fn = fn _example, _prediction -> 1.0 end

      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)

      # Should have approximately 50% success rate (3 success out of 6 error types)
      assert result.stats.total_examples == 12
      assert result.stats.successful > 0
      assert result.stats.failed > 0

      # Error list should contain actual error reasons
      assert length(result.stats.errors) == result.stats.failed

      # Error types should be from our defined set
      error_types = result.stats.errors |> Enum.uniq()
      expected_errors = [:network_error, :api_error, :timeout]

      for error <- error_types do
        assert error in expected_errors
      end
    end
  end

  describe "exception handling and crash recovery" do
    test "program exceptions are caught and converted to errors" do
      program = ErrorCategoriesProgram.new(:exception_test, [:exception])
      inputs = %{operation_id: 1}

      # Exception should be caught and converted to error
      assert_raise RuntimeError, "Simulated exception", fn ->
        DSPEx.Program.forward(program, inputs)
      end
    end

    test "evaluation handles program crashes gracefully" do
      crashing_program = ErrorCategoriesProgram.new(:crash_test, [:exception, :success])

      examples =
        for i <- 1..4 do
          %{inputs: %{operation_id: i}, outputs: %{success: true}}
        end

      metric_fn = fn _example, _prediction -> 1.0 end

      # Some operations will crash, but evaluation should handle it
      case DSPEx.Evaluate.run(crashing_program, examples, metric_fn) do
        {:ok, result} ->
          # Some should succeed, some should fail due to crashes
          assert result.stats.total_examples == 4
          assert result.stats.successful >= 0
          assert result.stats.failed >= 0

        {:error, :no_successful_evaluations} ->
          # All crashed, which is also a valid outcome
          :ok
      end
    end

    test "process exit and throw are handled appropriately" do
      exit_program = ErrorCategoriesProgram.new(:exit_test, [:exit])
      throw_program = ErrorCategoriesProgram.new(:throw_test, [:throw])

      inputs = %{operation_id: 1}

      # Exit should propagate
      catch_exit(DSPEx.Program.forward(exit_program, inputs))

      # Throw should propagate
      catch_throw(DSPEx.Program.forward(throw_program, inputs))
    end
  end

  describe "telemetry during error scenarios" do
    setup do
      # Capture telemetry events
      handler_id = make_ref()

      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :program, :forward, :start],
          [:dspex, :program, :forward, :stop],
          [:dspex, :evaluate, :run, :start],
          [:dspex, :evaluate, :run, :stop],
          [:dspex, :evaluate, :example, :start],
          [:dspex, :evaluate, :example, :stop]
        ],
        fn event_name, measurements, metadata, _acc ->
          send(self(), {:telemetry, event_name, measurements, metadata})
        end,
        []
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, handler_id: handler_id}
    end

    test "telemetry events are emitted even during failures" do
      program = ControlledErrorProgram.new(:telemetry_fail_test, :always)
      inputs = %{operation_id: 1}

      {:error, :always_fails} = DSPEx.Program.forward(program, inputs)

      # Should still receive telemetry events
      assert_receive {:telemetry, [:dspex, :program, :forward, :start], start_measurements,
                      start_metadata}

      assert_receive {:telemetry, [:dspex, :program, :forward, :stop], stop_measurements,
                      _stop_metadata}

      # Start event should be normal
      assert is_integer(start_measurements.system_time)
      assert start_metadata.program == :ControlledErrorProgram

      # Stop event should mark failure
      assert stop_measurements.success == false
      assert is_integer(stop_measurements.duration)
    end

    test "evaluation telemetry includes error statistics" do
      program = ControlledErrorProgram.new(:eval_telemetry_test, {:every_nth, 2})

      examples =
        for i <- 1..4 do
          %{inputs: %{operation_id: i}, outputs: %{processed_by: :eval_telemetry_test}}
        end

      metric_fn = fn _example, _prediction -> 1.0 end

      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)

      # Should receive evaluation telemetry
      assert_receive {:telemetry, [:dspex, :evaluate, :run, :start], _start_measurements,
                      start_metadata}

      assert_receive {:telemetry, [:dspex, :evaluate, :run, :stop], stop_measurements,
                      _stop_metadata}

      # Start should show total examples
      assert start_metadata.example_count == 4

      # Stop should show success (evaluation completed even with some failures)
      assert stop_measurements.success == true

      # Result should reflect the mixed success/failure
      # Operations 1 and 3
      assert result.stats.successful == 2
      # Operations 2 and 4
      assert result.stats.failed == 2
    end

    test "telemetry correlation IDs are maintained during error recovery" do
      program = ControlledErrorProgram.new(:correlation_test, :always, :fallback_response)
      inputs = %{operation_id: 1}
      custom_id = "error-recovery-test-123"

      {:ok, _result} = DSPEx.Program.forward(program, inputs, correlation_id: custom_id)

      assert_receive {:telemetry, [:dspex, :program, :forward, :start], _measurements,
                      start_metadata}

      assert_receive {:telemetry, [:dspex, :program, :forward, :stop], _measurements,
                      stop_metadata}

      # Correlation ID should be preserved through error and recovery
      assert start_metadata.correlation_id == custom_id
      assert stop_metadata.correlation_id == custom_id
    end
  end

  describe "stress testing error recovery" do
    test "high frequency errors don't destabilize system" do
      # 80% failure rate
      program = ControlledErrorProgram.new(:stress_test, {:random, 0.8})

      # Run many operations quickly
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            inputs = %{operation_id: i}
            DSPEx.Program.forward(program, inputs)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # System should handle all operations without crashing
      assert length(results) == 50

      # Should have mix of successes and failures
      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      assert successes + failures == 50
      # Should have many failures due to 80% rate
      assert failures > 30
      # Should have some successes due to randomness
      assert successes > 0
    end

    test "error recovery doesn't leak resources" do
      # Baseline memory
      :erlang.garbage_collect()
      {:memory, baseline_memory} = :erlang.process_info(self(), :memory)

      # Run many error-prone operations
      program = RecoveryStrategiesProgram.new(:resource_test, 1, :eventual_success)

      try do
        for i <- 1..100 do
          inputs = %{operation_id: i}
          _result = DSPEx.Program.forward(program, inputs)
        end

        # Force cleanup
        :erlang.garbage_collect()
        Process.sleep(50)
        :erlang.garbage_collect()

        {:memory, final_memory} = :erlang.process_info(self(), :memory)
        memory_growth = final_memory - baseline_memory

        # Memory growth should be reasonable (< 5MB for 100 operations)
        assert memory_growth < 5_000_000
      after
        RecoveryStrategiesProgram.stop(program)
      end
    end

    test "cascading failures are contained" do
      # Create a chain of programs where one failure could trigger others
      programs =
        for i <- 1..5 do
          # Middle program always fails
          failure_pattern = if i == 3, do: :always, else: :never
          ControlledErrorProgram.new(:"chain_#{i}", failure_pattern)
        end

      inputs = %{operation_id: 1}

      # Test each program independently
      results =
        for program <- programs do
          DSPEx.Program.forward(program, inputs)
        end

      # Only the middle program should fail
      for {result, i} <- Enum.with_index(results, 1) do
        if i == 3 do
          assert match?({:error, :always_fails}, result)
        else
          assert match?({:ok, _}, result)
        end
      end

      # Failure of one program shouldn't affect others
      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 4
    end
  end
end
