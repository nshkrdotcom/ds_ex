defmodule DSPEx.ProgramTest do
  @moduledoc """
  Comprehensive unit tests for DSPEx.Program behavior module.
  Tests behavior callbacks, telemetry integration, correlation tracking,
  error handling, and Foundation integration patterns.
  """
  use ExUnit.Case, async: true

  @moduletag :group_1

  # Test program implementations for various scenarios
  defmodule ValidProgram do
    use DSPEx.Program

    defstruct [:signature, :client, :demos, :config]

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      case inputs do
        %{success: true} ->
          {:ok, %{result: "success", config: program.config}}

        %{error: reason} ->
          {:error, reason}

        %{delay: ms} ->
          Process.sleep(ms)
          {:ok, %{result: "delayed"}}

        _ ->
          {:ok, %{result: "default", inputs: inputs}}
      end
    end
  end

  defmodule MinimalProgram do
    use DSPEx.Program

    defstruct [:id]

    @impl DSPEx.Program
    def forward(_program, inputs, _opts) do
      {:ok, Map.put(inputs, :processed, true)}
    end
  end

  defmodule ForwardTwoOnlyProgram do
    use DSPEx.Program

    defstruct [:name]

    @impl DSPEx.Program
    def forward(_program, inputs, _opts) do
      {:ok, Map.put(inputs, :forward_two_only, true)}
    end
  end

  defmodule CrashingProgram do
    use DSPEx.Program

    defstruct []

    @impl DSPEx.Program
    def forward(_program, inputs, _opts) do
      case inputs do
        %{crash: :raise} -> raise "Intentional crash"
        %{crash: :throw} -> throw(:intentional_throw)
        %{crash: :exit} -> exit(:intentional_exit)
        _ -> {:ok, %{result: "no_crash"}}
      end
    end
  end

  defmodule NoImplementationProgram do
    use DSPEx.Program

    defstruct []

    # Doesn't implement forward/2 or override forward/3
  end

  # Module that doesn't use DSPEx.Program behavior
  defmodule NotAProgram do
    defstruct [:data]

    def forward(_program, _inputs), do: {:error, :not_a_program}
  end

  describe "behavior implementation" do
    test "implements_program?/1 correctly identifies program modules" do
      assert DSPEx.Program.implements_program?(ValidProgram)
      assert DSPEx.Program.implements_program?(MinimalProgram)
      assert DSPEx.Program.implements_program?(ForwardTwoOnlyProgram)
      assert DSPEx.Program.implements_program?(CrashingProgram)
      assert DSPEx.Program.implements_program?(NoImplementationProgram)

      refute DSPEx.Program.implements_program?(NotAProgram)
      refute DSPEx.Program.implements_program?(NonExistentModule)
      refute DSPEx.Program.implements_program?(nil)
      refute DSPEx.Program.implements_program?("not_a_module")
      refute DSPEx.Program.implements_program?(123)
    end

    test "program_name/1 extracts correct module names" do
      program = %ValidProgram{signature: :test}
      assert DSPEx.Program.program_name(program) == :ValidProgram

      minimal = %MinimalProgram{id: 1}
      assert DSPEx.Program.program_name(minimal) == :MinimalProgram

      # Handle non-struct input
      assert DSPEx.Program.program_name(%{not: :a_struct}) == :unknown
      assert DSPEx.Program.program_name("not a struct") == :unknown
      assert DSPEx.Program.program_name(nil) == :unknown
    end

    test "new/2 creates valid program structs" do
      # Valid program creation
      {:ok, program} = DSPEx.Program.new(ValidProgram, %{signature: :test, config: "config"})
      assert %ValidProgram{signature: :test, config: "config"} = program

      # Empty fields
      {:ok, minimal} = DSPEx.Program.new(MinimalProgram, %{})
      assert %MinimalProgram{id: nil} = minimal

      # With specific fields
      {:ok, with_id} = DSPEx.Program.new(MinimalProgram, %{id: 42})
      assert %MinimalProgram{id: 42} = with_id
    end

    test "new/2 rejects invalid modules" do
      # Module that doesn't implement behavior
      assert {:error, {:invalid_program_module, NotAProgram}} =
               DSPEx.Program.new(NotAProgram, %{})

      # Non-existent module
      assert {:error, {:invalid_program_module, NonExistentModule}} =
               DSPEx.Program.new(NonExistentModule, %{})

      # Invalid arguments
      assert {:error, :invalid_arguments} = DSPEx.Program.new("not_atom", %{})
      assert {:error, :invalid_arguments} = DSPEx.Program.new(ValidProgram, "not_map")
      assert {:error, {:invalid_program_module, nil}} = DSPEx.Program.new(nil, %{})
    end

    test "new/2 handles struct creation failures" do
      # This would cause struct creation to fail due to unknown field
      # Most structs will just ignore unknown fields, but we can test the error path
      # by creating a struct that validates fields
      defmodule StrictProgram do
        use DSPEx.Program

        defstruct [:required_field]

        @impl DSPEx.Program
        def forward(_program, inputs, _opts), do: {:ok, inputs}
      end

      # This should succeed since Elixir structs don't validate by default
      {:ok, program} = DSPEx.Program.new(StrictProgram, %{unknown_field: "test"})
      assert %{__struct__: StrictProgram, required_field: nil} = program
    end
  end

  describe "forward execution" do
    test "forward/2 delegates to forward/3 with empty options" do
      program = %ValidProgram{config: "test"}
      inputs = %{success: true}

      {:ok, result} = DSPEx.Program.forward(program, inputs)

      assert %{result: "success", config: "test"} = result
    end

    test "forward/3 executes program with options" do
      program = %ValidProgram{config: "with_opts"}
      inputs = %{success: true}
      opts = [correlation_id: "test-123", custom_opt: true]

      {:ok, result} = DSPEx.Program.forward(program, inputs, opts)

      assert %{result: "success", config: "with_opts"} = result
    end

    test "forward execution with different input scenarios" do
      program = %ValidProgram{config: "scenario_test"}

      # Success case
      {:ok, result} = DSPEx.Program.forward(program, %{success: true})
      assert result.result == "success"

      # Error case
      {:error, :test_error} = DSPEx.Program.forward(program, %{error: :test_error})

      # Default case
      {:ok, result} = DSPEx.Program.forward(program, %{random: "input"})
      assert result.result == "default"
      assert result.inputs == %{random: "input"}
    end

    test "handles programs with only forward/2 implementation" do
      program = %ForwardTwoOnlyProgram{name: "test"}
      inputs = %{data: "test"}

      {:ok, result} = DSPEx.Program.forward(program, inputs)

      assert %{data: "test", forward_two_only: true} = result
    end

    test "handles programs with no implementation" do
      program = %NoImplementationProgram{}
      inputs = %{test: "data"}

      {:error, {:not_implemented, message}} = DSPEx.Program.forward(program, inputs)

      assert message =~ "NoImplementationProgram"
      assert message =~ "must implement forward/2 or forward/3"
    end

    test "propagates program execution errors" do
      program = %ValidProgram{}

      # Test different error types
      assert {:error, :custom_error} = DSPEx.Program.forward(program, %{error: :custom_error})
      assert {:error, "string error"} = DSPEx.Program.forward(program, %{error: "string error"})

      assert {:error, {:tuple, :error}} =
               DSPEx.Program.forward(program, %{error: {:tuple, :error}})
    end

    test "measures execution time" do
      program = %ValidProgram{}

      # Quick execution
      start_time = System.monotonic_time()
      {:ok, _result} = DSPEx.Program.forward(program, %{success: true})
      quick_duration = System.monotonic_time() - start_time

      # Delayed execution
      delay_ms = 50
      start_time = System.monotonic_time()
      {:ok, result} = DSPEx.Program.forward(program, %{delay: delay_ms})
      delayed_duration = System.monotonic_time() - start_time

      assert result.result == "delayed"
      assert delayed_duration > quick_duration
      # Should be at least the delay time (converted to native time units)
      expected_delay = System.convert_time_unit(delay_ms, :millisecond, :native)
      assert delayed_duration >= expected_delay
    end
  end

  describe "telemetry integration" do
    setup do
      # Capture telemetry events
      events = []
      handler_id = make_ref()

      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :program, :forward, :start],
          [:dspex, :program, :forward, :stop],
          [:dspex, :program, :forward, :exception]
        ],
        fn event_name, measurements, metadata, _acc ->
          send(self(), {:telemetry, event_name, measurements, metadata})
        end,
        events
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, handler_id: handler_id}
    end

    test "emits start and stop events for successful execution" do
      program = %ValidProgram{config: "telemetry_test"}
      inputs = %{success: true}

      {:ok, _result} = DSPEx.Program.forward(program, inputs)

      # Should receive start event
      assert_receive {:telemetry, [:dspex, :program, :forward, :start], start_measurements,
                      start_metadata}

      assert %{system_time: system_time} = start_measurements
      assert is_integer(system_time)

      assert %{
               program: :ValidProgram,
               correlation_id: correlation_id,
               input_count: 1
             } = start_metadata

      assert is_binary(correlation_id)

      # Should receive stop event
      assert_receive {:telemetry, [:dspex, :program, :forward, :stop], stop_measurements,
                      stop_metadata}

      assert %{duration: duration, success: true} = stop_measurements
      assert is_integer(duration)
      assert duration > 0

      assert %{
               program: :ValidProgram,
               correlation_id: ^correlation_id
             } = stop_metadata
    end

    test "emits stop event with success=false for error execution" do
      program = %ValidProgram{}
      inputs = %{error: :test_failure}

      {:error, :test_failure} = DSPEx.Program.forward(program, inputs)

      assert_receive {:telemetry, [:dspex, :program, :forward, :start], _start_measurements,
                      _start_metadata}

      assert_receive {:telemetry, [:dspex, :program, :forward, :stop], stop_measurements,
                      _stop_metadata}

      assert %{success: false} = stop_measurements
    end

    test "uses custom correlation_id when provided" do
      program = %ValidProgram{}
      inputs = %{success: true}
      custom_id = "custom-correlation-123"

      {:ok, _result} = DSPEx.Program.forward(program, inputs, correlation_id: custom_id)

      assert_receive {:telemetry, [:dspex, :program, :forward, :start], _measurements,
                      start_metadata}

      assert %{correlation_id: ^custom_id} = start_metadata

      assert_receive {:telemetry, [:dspex, :program, :forward, :stop], _measurements,
                      stop_metadata}

      assert %{correlation_id: ^custom_id} = stop_metadata
    end

    test "generates correlation_id when not provided" do
      program = %ValidProgram{}
      inputs = %{success: true}

      {:ok, _result} = DSPEx.Program.forward(program, inputs)

      assert_receive {:telemetry, [:dspex, :program, :forward, :start], _measurements,
                      start_metadata}

      assert %{correlation_id: correlation_id} = start_metadata
      assert is_binary(correlation_id)
      assert String.length(correlation_id) > 0
    end

    test "tracks input count correctly" do
      program = %ValidProgram{}

      # Single input
      {:ok, _result} = DSPEx.Program.forward(program, %{single: "input"})
      assert_receive {:telemetry, [:dspex, :program, :forward, :start], _measurements, metadata}
      assert %{input_count: 1} = metadata

      # Multiple inputs
      multi_inputs = %{input1: "a", input2: "b", input3: "c"}
      {:ok, _result} = DSPEx.Program.forward(program, multi_inputs)
      assert_receive {:telemetry, [:dspex, :program, :forward, :start], _measurements, metadata}
      assert %{input_count: 3} = metadata

      # Empty inputs
      {:ok, _result} = DSPEx.Program.forward(program, %{})
      assert_receive {:telemetry, [:dspex, :program, :forward, :start], _measurements, metadata}
      assert %{input_count: 0} = metadata
    end
  end

  describe "error handling and edge cases" do
    test "handles programs that crash with exceptions" do
      program = %CrashingProgram{}

      # Test that crashes are allowed to propagate
      # (DSPEx.Program doesn't catch exceptions, that's left to supervisors)
      assert_raise RuntimeError, "Intentional crash", fn ->
        DSPEx.Program.forward(program, %{crash: :raise})
      end

      catch_throw(DSPEx.Program.forward(program, %{crash: :throw}))

      catch_exit(DSPEx.Program.forward(program, %{crash: :exit}))

      # Normal operation still works
      {:ok, result} = DSPEx.Program.forward(program, %{normal: true})
      assert %{result: "no_crash"} = result
    end

    test "handles programs with malformed struct" do
      # Create a program with invalid struct data
      program = %ValidProgram{signature: nil, client: nil, config: nil}

      # Should still work since the program implementation doesn't require these fields
      {:ok, result} = DSPEx.Program.forward(program, %{success: true})
      assert %{result: "success", config: nil} = result
    end

    test "handles empty and nil inputs gracefully" do
      program = %ValidProgram{config: "empty_test"}

      # Empty map
      {:ok, result} = DSPEx.Program.forward(program, %{})
      assert %{result: "default", inputs: %{}} = result

      # The actual DSPEx.Program.forward/3 function expects a map for inputs
      # Passing nil should return an error tuple
      assert {:error, {:invalid_inputs, "inputs must be a map"}} =
               DSPEx.Program.forward(program, nil)
    end

    test "handles very large input maps" do
      program = %MinimalProgram{id: 1}

      # Create a large input map
      large_inputs = for i <- 1..1000, into: %{}, do: {:"input_#{i}", "value_#{i}"}

      {:ok, result} = DSPEx.Program.forward(program, large_inputs)

      # Should process successfully
      assert result.processed == true
      # +1 for the :processed field
      assert map_size(result) == map_size(large_inputs) + 1
    end

    test "handles concurrent execution" do
      program = %ValidProgram{config: "concurrent_test"}

      # Run multiple forwards concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            DSPEx.Program.forward(program, %{id: i, success: true})
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed
      for {:ok, result} <- results do
        assert result.result == "success"
        assert result.config == "concurrent_test"
      end

      assert length(results) == 10
    end
  end

  describe "Foundation integration" do
    setup do
      # Capture telemetry events for Foundation tests
      handler_id = make_ref()

      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :program, :forward, :start],
          [:dspex, :program, :forward, :stop],
          [:dspex, :program, :forward, :exception]
        ],
        fn event_name, measurements, metadata, _acc ->
          send(self(), {:telemetry, event_name, measurements, metadata})
        end,
        []
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, handler_id: handler_id}
    end

    test "correlation_id generation follows expected patterns" do
      program = %ValidProgram{}
      inputs = %{test: "correlation"}

      # Execute multiple times and collect correlation IDs
      correlation_ids =
        for _i <- 1..5 do
          {:ok, _result} = DSPEx.Program.forward(program, inputs)

          receive do
            {:telemetry, [:dspex, :program, :forward, :start], _measurements, metadata} ->
              metadata.correlation_id
          after
            100 -> nil
          end
        end

      # All should be unique
      unique_ids = Enum.uniq(correlation_ids)
      assert length(unique_ids) == 5

      # All should be strings
      for id <- correlation_ids do
        assert is_binary(id)
        # Should be reasonably long
        assert String.length(id) > 10
      end
    end

    test "telemetry metadata includes all expected fields" do
      program = %ValidProgram{signature: :test_signature, config: "meta_test"}
      inputs = %{field1: "value1", field2: "value2"}
      opts = [correlation_id: "meta-test-123", extra_opt: "ignored"]

      {:ok, _result} = DSPEx.Program.forward(program, inputs, opts)

      assert_receive {:telemetry, [:dspex, :program, :forward, :start], start_measurements,
                      start_metadata}

      # Start measurements
      assert %{system_time: system_time} = start_measurements
      assert is_integer(system_time)
      assert system_time > 0

      # Start metadata
      assert %{
               program: :ValidProgram,
               correlation_id: "meta-test-123",
               input_count: 2
             } = start_metadata

      assert_receive {:telemetry, [:dspex, :program, :forward, :stop], stop_measurements,
                      stop_metadata}

      # Stop measurements
      assert %{duration: duration, success: true} = stop_measurements
      assert is_integer(duration)
      assert duration > 0

      # Stop metadata
      assert %{
               program: :ValidProgram,
               correlation_id: "meta-test-123"
             } = stop_metadata
    end
  end

  describe "performance characteristics" do
    setup do
      # Capture telemetry events for performance tests
      handler_id = make_ref()

      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :program, :forward, :start],
          [:dspex, :program, :forward, :stop],
          [:dspex, :program, :forward, :exception]
        ],
        fn event_name, measurements, metadata, _acc ->
          send(self(), {:telemetry, event_name, measurements, metadata})
        end,
        []
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, handler_id: handler_id}
    end

    test "execution time tracking is accurate" do
      program = %ValidProgram{}

      # Test with different delay times
      delay_times = [10, 25, 50]

      for delay_ms <- delay_times do
        start_time = System.monotonic_time()
        {:ok, _result} = DSPEx.Program.forward(program, %{delay: delay_ms})
        actual_duration = System.monotonic_time() - start_time

        # Get telemetry duration
        assert_receive {:telemetry, [:dspex, :program, :forward, :start], _start_measurements,
                        _start_metadata}

        assert_receive {:telemetry, [:dspex, :program, :forward, :stop], stop_measurements,
                        _stop_metadata}

        telemetry_duration = stop_measurements.duration

        # Telemetry duration should be close to actual duration
        # Allow some tolerance for system variance
        tolerance = System.convert_time_unit(5, :millisecond, :native)
        assert abs(telemetry_duration - actual_duration) < tolerance

        # Both should be at least the delay time
        expected_delay = System.convert_time_unit(delay_ms, :millisecond, :native)
        assert telemetry_duration >= expected_delay - tolerance
        assert actual_duration >= expected_delay - tolerance
      end
    end

    test "low overhead for simple programs" do
      program = %MinimalProgram{id: 1}
      inputs = %{simple: "test"}

      # Warm up
      for _i <- 1..10, do: DSPEx.Program.forward(program, inputs)

      # Measure execution time
      start_time = System.monotonic_time()

      for _i <- 1..100 do
        {:ok, _result} = DSPEx.Program.forward(program, inputs)
      end

      total_duration = System.monotonic_time() - start_time
      avg_duration_us = System.convert_time_unit(total_duration, :native, :microsecond) / 100

      # Should be fast - less than 2ms per execution on average
      # Increased threshold from 1000us to 2000us to accommodate CI environment performance variations
      assert avg_duration_us < 2000
    end
  end
end
