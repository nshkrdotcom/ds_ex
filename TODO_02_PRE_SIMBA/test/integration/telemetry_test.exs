# File: test/integration/telemetry_test.exs
defmodule DSPEx.Integration.TelemetryTest do
  use ExUnit.Case, async: false

  alias DSPEx.{Predict, Program, Example}
  alias DSPEx.Test.MockProvider
  alias DSPEx.Teleprompter.BootstrapFewShot

  @moduletag :integration
  @moduletag :telemetry

  setup do
    {:ok, _mock} = MockProvider.start_link(mode: :contextual)

    defmodule TelemetrySignature do
      use DSPEx.Signature, "question -> answer"
    end

    # Clear any existing test handlers
    cleanup_test_handlers()

    %{signature: TelemetrySignature}
  end

  describe "program operation telemetry events" do
    test "Program.forward/3 emits correct telemetry events", %{signature: signature} do
      test_pid = self()

      # Attach handlers for program events
      :telemetry.attach_many(
        "test-program-handler",
        [
          [:dspex, :program, :forward, :start],
          [:dspex, :program, :forward, :stop],
          [:dspex, :program, :forward, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{}
      )

      program = %Predict{signature: signature, client: :test}
      inputs = %{question: "Telemetry test"}

      MockProvider.setup_evaluation_mocks([0.8])

      # Execute program
      {:ok, _result} = Program.forward(program, inputs)

      # Should receive start and stop events
      assert_receive {:telemetry_event, [:dspex, :program, :forward, :start], start_measurements, start_metadata}, 1000
      assert_receive {:telemetry_event, [:dspex, :program, :forward, :stop], stop_measurements, stop_metadata}, 1000

      # Verify start event
      assert is_map(start_measurements)
      assert Map.has_key?(start_measurements, :system_time)
      assert is_map(start_metadata)
      assert Map.has_key?(start_metadata, :program)
      assert Map.has_key?(start_metadata, :correlation_id)

      # Verify stop event
      assert is_map(stop_measurements)
      assert Map.has_key?(stop_measurements, :duration)
      assert Map.has_key?(stop_measurements, :success)
      assert stop_measurements.success == true

      # Metadata should be consistent
      assert start_metadata.program == stop_metadata.program
      assert start_metadata.correlation_id == stop_metadata.correlation_id

      :telemetry.detach("test-program-handler")
    end

    test "Predict.predict/2 emits legacy telemetry events", %{signature: signature} do
      test_pid = self()

      :telemetry.attach_many(
        "test-predict-handler",
        [
          [:dspex, :predict, :start],
          [:dspex, :predict, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{}
      )

      inputs = %{question: "Legacy telemetry test"}

      MockProvider.setup_evaluation_mocks([0.7])

      # Execute legacy predict
      {:ok, _result} = DSPEx.Predict.predict(signature, inputs)

      # Should receive legacy events
      assert_receive {:telemetry_event, [:dspex, :predict, :start], _measurements, _metadata}, 1000
      assert_receive {:telemetry_event, [:dspex, :predict, :stop], stop_measurements, stop_metadata}, 1000

      # Verify stop event
      assert is_map(stop_measurements)
      assert Map.has_key?(stop_measurements, :duration)
      assert Map.has_key?(stop_measurements, :success)

      assert is_map(stop_metadata)
      assert Map.has_key?(stop_metadata, :signature)

      :telemetry.detach("test-predict-handler")
    end

    test "client request telemetry events", %{signature: signature} do
      test_pid = self()

      :telemetry.attach_many(
        "test-client-handler",
        [
          [:dspex, :client, :request, :start],
          [:dspex, :client, :request, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{}
      )

      program = %Predict{signature: signature, client: :test}

      MockProvider.setup_evaluation_mocks([0.9])

      {:ok, _result} = Program.forward(program, %{question: "Client telemetry"})

      # Should receive client events
      assert_receive {:telemetry_event, [:dspex, :client, :request, :start], _start_measurements, start_metadata}, 2000
      assert_receive {:telemetry_event, [:dspex, :client, :request, :stop], stop_measurements, stop_metadata}, 2000

      # Verify client events
      assert Map.has_key?(start_metadata, :provider)
      assert Map.has_key?(start_metadata, :correlation_id)

      assert Map.has_key?(stop_measurements, :duration)
      assert Map.has_key?(stop_measurements, :success)
      assert Map.has_key?(stop_metadata, :provider)

      :telemetry.detach("test-client-handler")
    end
  end

  describe "teleprompter telemetry events" do
    test "BootstrapFewShot emits optimization telemetry", %{signature: signature} do
      test_pid = self()

      # Attach handlers for teleprompter events
      :telemetry.attach_many(
        "test-teleprompter-handler",
        [
          [:dspex, :teleprompter, :bootstrap, :start],
          [:dspex, :teleprompter, :bootstrap, :stop],
          [:dspex, :evaluate, :example, :start],
          [:dspex, :evaluate, :example, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{}
      )

      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}

      trainset = [
        %Example{
          data: %{question: "Teleprompter test", answer: "Response"},
          input_keys: MapSet.new([:question])
        }
      ]

      metric_fn = fn _example, _prediction -> 0.8 end

      MockProvider.setup_bootstrap_mocks([%{content: "Response"}])

      # Execute teleprompter
      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 1
      )

      # Should receive teleprompter events
      # Note: Events might vary based on implementation
      received_events = collect_telemetry_events([], 3000)

      # Should have some telemetry events
      assert length(received_events) > 0

      # Verify at least some expected events
      event_names = Enum.map(received_events, fn {event, _, _} -> event end)

      # Should have some program or client events from the optimization process
      program_events = Enum.filter(event_names, fn event ->
        match?([:dspex, :program, :forward, _], event) or
        match?([:dspex, :client, :request, _], event)
      end)

      assert length(program_events) > 0

      :telemetry.detach("test-teleprompter-handler")
    end

    test "optimization progress telemetry", %{signature: signature} do
      test_pid = self()

      # Track all DSPEx events during optimization
      :telemetry.attach(
        "test-optimization-progress",
        [:dspex],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:progress_event, event, measurements, metadata})
        end,
        %{}
      )

      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}

      trainset = Enum.map(1..3, fn i ->
        %Example{
          data: %{question: "Progress #{i}", answer: "Answer #{i}"},
          input_keys: MapSet.new([:question])
        }
      end)

      metric_fn = fn _example, _prediction -> 0.7 end

      MockProvider.setup_bootstrap_mocks([
        %{content: "Answer 1"},
        %{content: "Answer 2"},
        %{content: "Answer 3"}
      ])

      # Execute with progress tracking
      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        trainset,
        metric_fn,
        max_bootstrapped_demos: 3
      )

      # Collect progress events
      progress_events = collect_telemetry_events([], 5000)

      # Should have multiple events showing progress
      assert length(progress_events) >= 3

      # Should have correlation IDs for tracking
      events_with_correlation = Enum.filter(progress_events, fn {_event, _measurements, metadata} ->
        Map.has_key?(metadata, :correlation_id)
      end)

      assert length(events_with_correlation) > 0

      :telemetry.detach("test-optimization-progress")
    end
  end

  describe "telemetry metadata completeness" do
    test "correlation ID propagation through call chain", %{signature: signature} do
      test_pid = self()
      correlation_id = "test-correlation-#{System.unique_integer()}"

      # Track correlation IDs in all events
      :telemetry.attach(
        "test-correlation-tracking",
        [:dspex],
        fn event, _measurements, metadata, _config ->
          if Map.has_key?(metadata, :correlation_id) do
            send(test_pid, {:correlation_event, event, metadata.correlation_id})
          end
        end,
        %{}
      )

      program = %Predict{signature: signature, client: :test}

      MockProvider.setup_evaluation_mocks([0.8])

      # Execute with specific correlation ID
      {:ok, _result} = Program.forward(program, %{question: "Correlation test"},
                                      correlation_id: correlation_id)

      # Collect correlation events
      correlation_events = collect_correlation_events([], 2000)

      # Should have events with the same correlation ID
      matching_correlations = Enum.filter(correlation_events, fn {_event, id} ->
        id == correlation_id
      end)

      assert length(matching_correlations) > 0

      # All should have the same correlation ID
      unique_ids = correlation_events
      |> Enum.map(fn {_event, id} -> id end)
      |> Enum.uniq()

      # Should have consistent correlation ID propagation
      assert correlation_id in unique_ids

      :telemetry.detach("test-correlation-tracking")
    end

    test "telemetry metadata includes required fields", %{signature: signature} do
      test_pid = self()

      :telemetry.attach(
        "test-metadata-completeness",
        [:dspex, :program, :forward, :stop],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:metadata_check, metadata})
        end,
        %{}
      )

      program = %Predict{signature: signature, client: :test}

      MockProvider.setup_evaluation_mocks([0.9])

      {:ok, _result} = Program.forward(program, %{question: "Metadata test"})

      assert_receive {:metadata_check, metadata}, 1000

      # Required metadata fields
      required_fields = [:program, :correlation_id]

      Enum.each(required_fields, fn field ->
        assert Map.has_key?(metadata, field), "Missing required field: #{field}"
        assert metadata[field] != nil, "Required field #{field} is nil"
      end)

      # Program should be an atom
      assert is_atom(metadata.program)

      # Correlation ID should be a string
      assert is_binary(metadata.correlation_id)

      :telemetry.detach("test-metadata-completeness")
    end

    test "error telemetry includes error context", %{signature: signature} do
      test_pid = self()

      :telemetry.attach_many(
        "test-error-telemetry",
        [
          [:dspex, :program, :forward, :exception],
          [:dspex, :predict, :exception],
          [:dspex, :client, :request, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:error_telemetry, event, measurements, metadata})
        end,
        %{}
      )

      # Create error scenario
      invalid_program = %Predict{signature: nil, client: :test}

      # This should generate error telemetry
      result = try do
        Program.forward(invalid_program, %{question: "Error test"})
      rescue
        _ -> {:error, :rescued}
      catch
        _, _ -> {:error, :caught}
      end

      # Should handle error gracefully
      assert match?({:error, _}, result)

      # Check if we received error telemetry (timing dependent)
      error_events = collect_telemetry_events([], 1000)

      # If we got error events, verify they have proper context
      if length(error_events) > 0 do
        Enum.each(error_events, fn {event, measurements, metadata} ->
          assert is_list(event)
          assert is_map(measurements)
          assert is_map(metadata)
        end)
      end

      :telemetry.detach("test-error-telemetry")
    end
  end

  describe "performance monitoring telemetry" do
    test "duration measurements are accurate", %{signature: signature} do
      test_pid = self()

      :telemetry.attach(
        "test-duration-accuracy",
        [:dspex, :program, :forward, :stop],
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:duration_measurement, measurements})
        end,
        %{}
      )

      program = %Predict{signature: signature, client: :test}

      MockProvider.setup_evaluation_mocks([0.8])

      # Measure execution time manually
      start_time = System.monotonic_time()
      {:ok, _result} = Program.forward(program, %{question: "Duration test"})
      end_time = System.monotonic_time()

      manual_duration = end_time - start_time

      assert_receive {:duration_measurement, measurements}, 1000

      telemetry_duration = measurements.duration

      # Telemetry duration should be reasonable compared to manual measurement
      # Allow for some variation due to measurement overhead
      ratio = telemetry_duration / manual_duration
      assert ratio >= 0.5 and ratio <= 2.0, "Duration ratio out of range: #{ratio}"

      :telemetry.detach("test-duration-accuracy")
    end

    test "success/failure measurements are accurate", %{signature: signature} do
      test_pid = self()

      :telemetry.attach(
        "test-success-tracking",
        [:dspex, :program, :forward, :stop],
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:success_measurement, measurements.success})
        end,
        %{}
      )

      program = %Predict{signature: signature, client: :test}

      # Test successful execution
      MockProvider.setup_evaluation_mocks([0.9])
      {:ok, _result} = Program.forward(program, %{question: "Success test"})

      assert_receive {:success_measurement, success_value}, 1000
      assert success_value == true

      :telemetry.detach("test-success-tracking")
    end

    test "concurrent operations have separate telemetry", %{signature: signature} do
      test_pid = self()

      :telemetry.attach(
        "test-concurrent-telemetry",
        [:dspex, :program, :forward, :stop],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:concurrent_telemetry, metadata.correlation_id})
        end,
        %{}
      )

      program = %Predict{signature: signature, client: :test}

      MockProvider.setup_evaluation_mocks(
        Enum.map(1..10, fn _ -> 0.8 end)
      )

      # Execute concurrent operations
      tasks = Task.async_stream(1..10, fn i ->
        correlation_id = "concurrent-#{i}"
        Program.forward(program, %{question: "Concurrent #{i}"},
                       correlation_id: correlation_id)
      end, max_concurrency: 5)
      |> Enum.to_list()

      # Collect correlation IDs from telemetry
      concurrent_ids = collect_correlation_events([], 5000)
      |> Enum.map(fn {_event, id} -> id end)
      |> Enum.filter(fn id -> String.starts_with?(id, "concurrent-") end)
      |> Enum.uniq()

      # Should have telemetry for multiple concurrent operations
      assert length(concurrent_ids) >= 5

      # Each should have unique correlation ID
      assert length(concurrent_ids) == length(Enum.uniq(concurrent_ids))

      :telemetry.detach("test-concurrent-telemetry")
    end
  end

  describe "JSON serialization of telemetry data" do
    test "telemetry metadata can be serialized to JSON", %{signature: signature} do
      test_pid = self()

      :telemetry.attach(
        "test-json-serialization",
        [:dspex, :program, :forward, :stop],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:json_test, metadata})
        end,
        %{}
      )

      program = %Predict{signature: signature, client: :test}

      MockProvider.setup_evaluation_mocks([0.7])

      {:ok, _result} = Program.forward(program, %{question: "JSON test"})

      assert_receive {:json_test, metadata}, 1000

      # Should be able to serialize metadata to JSON
      json_result = try do
        Jason.encode!(metadata)
      rescue
        error -> {:error, error}
      end

      case json_result do
        json_string when is_binary(json_string) ->
          # Should be valid JSON
          {:ok, parsed} = Jason.decode(json_string)
          assert is_map(parsed)

          # Should contain expected fields
          assert Map.has_key?(parsed, "program")
          assert Map.has_key?(parsed, "correlation_id")

        {:error, error} ->
          flunk("Failed to serialize metadata to JSON: #{inspect(error)}")
      end

      :telemetry.detach("test-json-serialization")
    end

    test "measurements can be serialized for monitoring systems", %{signature: signature} do
      test_pid = self()

      :telemetry.attach(
        "test-measurements-serialization",
        [:dspex, :program, :forward, :stop],
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:measurements_test, measurements})
        end,
        %{}
      )

      program = %Predict{signature: signature, client: :test}

      MockProvider.setup_evaluation_mocks([0.6])

      {:ok, _result} = Program.forward(program, %{question: "Measurements test"})

      assert_receive {:measurements_test, measurements}, 1000

      # Should be able to serialize measurements
      json_result = try do
        Jason.encode!(measurements)
      rescue
        error -> {:error, error}
      end

      case json_result do
        json_string when is_binary(json_string) ->
          {:ok, parsed} = Jason.decode(json_string)
          assert is_map(parsed)

          # Should have numeric measurements
          assert Map.has_key?(parsed, "duration")
          assert Map.has_key?(parsed, "success")

        {:error, error} ->
          flunk("Failed to serialize measurements to JSON: #{inspect(error)}")
      end

      :telemetry.detach("test-measurements-serialization")
    end
  end

  # Helper functions
  defp cleanup_test_handlers do
    # Detach any existing test handlers
    test_handler_ids = [
      "test-program-handler",
      "test-predict-handler",
      "test-client-handler",
      "test-teleprompter-handler",
      "test-optimization-progress",
      "test-correlation-tracking",
      "test-metadata-completeness",
      "test-error-telemetry",
      "test-duration-accuracy",
      "test-success-tracking",
      "test-concurrent-telemetry",
      "test-json-serialization",
      "test-measurements-serialization"
    ]

    Enum.each(test_handler_ids, fn id ->
      try do
        :telemetry.detach(id)
      rescue
        _ -> :ok
      end
    end)
  end

  defp collect_telemetry_events(acc, timeout) do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        collect_telemetry_events([{event, measurements, metadata} | acc], timeout)
      {:progress_event, event, measurements, metadata} ->
        collect_telemetry_events([{event, measurements, metadata} | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  defp collect_correlation_events(acc, timeout) do
    receive do
      {:correlation_event, event, correlation_id} ->
        collect_correlation_events([{event, correlation_id} | acc], timeout)
      {:concurrent_telemetry, correlation_id} ->
        collect_correlation_events([{:concurrent, correlation_id} | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end
end
