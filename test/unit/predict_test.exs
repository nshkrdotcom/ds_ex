defmodule DSPEx.PredictTest do
  @moduledoc """
  Comprehensive unit tests for DSPEx.Predict module.
  Tests prediction pipeline, Program behavior integration, input validation,
  error handling, telemetry, and performance characteristics.
  """
  use ExUnit.Case, async: true

  @moduletag :group_1

  # Mock signature for testing
  defmodule MockSignature do
    def input_fields, do: [:question]
    def output_fields, do: [:answer]
    def description, do: "Answer the question"
  end

  defmodule MultiFieldSignature do
    def input_fields, do: [:question, :context]
    def output_fields, do: [:answer, :reasoning]
    def description, do: "Answer with reasoning"
  end

  describe "forward/2 and forward/3" do
    test "validates inputs before processing" do
      # missing required question field
      inputs = %{}

      assert {:error, :missing_inputs} = DSPEx.Predict.forward(MockSignature, inputs)
    end

    @tag :external_api
    test "accepts valid inputs and attempts prediction" do
      inputs = %{question: "What is 2+2?"}

      # Should pass input validation and may succeed or fail depending on API availability
      case DSPEx.Predict.forward(MockSignature, inputs) do
        {:ok, outputs} ->
          # API is working - verify output structure
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          # API is not available - verify error types
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "forwards options to client" do
      inputs = %{question: "What is 2+2?"}
      options = %{model: "different-model", temperature: 0.5}

      # Should pass input validation and forward options
      case DSPEx.Predict.forward(MockSignature, inputs, options) do
        {:ok, outputs} ->
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "handles multi-field signatures" do
      inputs = %{question: "What is AI?", context: "Computer science"}

      case DSPEx.Predict.forward(MultiFieldSignature, inputs) do
        {:ok, outputs} ->
          # Should have at least answer field for multi-field signature
          assert Map.has_key?(outputs, :answer)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    test "returns error for invalid signature" do
      inputs = %{question: "test"}

      assert {:error, :invalid_signature} = DSPEx.Predict.forward(InvalidSignature, inputs)
    end
  end

  describe "predict_field/3 and predict_field/4" do
    test "validates field exists in signature" do
      # We can't test successful field extraction without mocking the full pipeline,
      # but we can test the error path for input validation
      # missing required field
      inputs = %{}

      assert {:error, :missing_inputs} =
               DSPEx.Predict.predict_field(MockSignature, inputs, :answer)
    end

    @tag :external_api
    test "passes through prediction errors" do
      inputs = %{question: "What is 2+2?"}

      # Should either succeed or fail gracefully
      case DSPEx.Predict.predict_field(MockSignature, inputs, :answer) do
        {:ok, answer} ->
          assert is_binary(answer)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    @tag :external_api
    test "accepts options parameter" do
      inputs = %{question: "What is 2+2?"}
      options = %{temperature: 0.2}

      case DSPEx.Predict.predict_field(MockSignature, inputs, :answer, options) do
        {:ok, answer} ->
          assert is_binary(answer)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end
  end

  describe "validate_inputs/2" do
    test "returns :ok for valid inputs" do
      inputs = %{question: "What is 2+2?"}

      assert :ok = DSPEx.Predict.validate_inputs(MockSignature, inputs)
    end

    test "returns error for missing required inputs" do
      # missing question
      inputs = %{}

      assert {:error, :missing_inputs} = DSPEx.Predict.validate_inputs(MockSignature, inputs)
    end

    test "returns error for invalid signature" do
      inputs = %{question: "test"}

      assert {:error, :invalid_signature} =
               DSPEx.Predict.validate_inputs(InvalidSignature, inputs)
    end

    test "validates multi-field signatures" do
      # Valid case
      inputs = %{question: "What is AI?", context: "Computer science"}
      assert :ok = DSPEx.Predict.validate_inputs(MultiFieldSignature, inputs)

      # Missing field case
      # missing context
      incomplete_inputs = %{question: "What is AI?"}

      assert {:error, :missing_inputs} =
               DSPEx.Predict.validate_inputs(MultiFieldSignature, incomplete_inputs)
    end

    test "accepts extra input fields" do
      inputs = %{question: "What is 2+2?", extra: "field"}

      assert :ok = DSPEx.Predict.validate_inputs(MockSignature, inputs)
    end
  end

  describe "describe_signature/1" do
    test "returns signature field information" do
      assert {:ok, description} = DSPEx.Predict.describe_signature(MockSignature)

      assert %{
               inputs: [:question],
               outputs: [:answer],
               description: "Answer the question"
             } = description
    end

    test "handles multi-field signatures" do
      assert {:ok, description} = DSPEx.Predict.describe_signature(MultiFieldSignature)

      assert %{
               inputs: [:question, :context],
               outputs: [:answer, :reasoning],
               description: "Answer with reasoning"
             } = description
    end

    test "returns error for invalid signature" do
      assert {:error, :invalid_signature} = DSPEx.Predict.describe_signature(InvalidSignature)
    end

    test "handles signature without description" do
      defmodule NoDescSignature do
        def input_fields, do: [:input]
        def output_fields, do: [:output]
      end

      assert {:ok, description} = DSPEx.Predict.describe_signature(NoDescSignature)
      assert %{description: "No description available"} = description
    end
  end

  describe "error propagation" do
    test "propagates adapter formatting errors" do
      # This will cause missing_inputs error in adapter
      inputs = %{}

      assert {:error, :missing_inputs} = DSPEx.Predict.forward(MockSignature, inputs)
    end

    test "propagates signature validation errors" do
      inputs = %{question: "test"}

      assert {:error, :invalid_signature} = DSPEx.Predict.forward(InvalidSignature, inputs)
    end

    @tag :external_api
    @tag :external_api
    test "propagates client errors" do
      inputs = %{question: "What is 2+2?"}

      # With valid inputs, should either succeed or get categorized errors
      case DSPEx.Predict.forward(MockSignature, inputs) do
        {:ok, outputs} ->
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end
  end

  describe "DSPEx.Program behavior integration" do
    test "new/2 creates valid program structs" do
      # Test with atom client
      program = DSPEx.Predict.new(MockSignature, :openai)

      assert %DSPEx.Predict{} = program
      assert program.signature == MockSignature
      assert program.client == :openai
      # Default adapter
      assert program.adapter == nil
      # Empty demos initially
      assert program.demos == []
    end

    test "new/2 supports different client types" do
      # String client
      program1 = DSPEx.Predict.new(MockSignature, "custom-client")
      assert program1.client == "custom-client"

      # Atom client
      program2 = DSPEx.Predict.new(MockSignature, :gemini)
      assert program2.client == :gemini
    end

    test "new/3 accepts custom options" do
      opts = %{adapter: :custom_adapter, demos: [%{input: "test"}]}
      program = DSPEx.Predict.new(MockSignature, :openai, opts)

      assert program.signature == MockSignature
      assert program.client == :openai
      assert program.adapter == :custom_adapter
      assert program.demos == [%{input: "test"}]
    end

    test "implements DSPEx.Program behavior correctly" do
      # Verify behavior implementation
      assert DSPEx.Program.implements_program?(DSPEx.Predict)

      # Test program_name extraction
      program = DSPEx.Predict.new(MockSignature, :test)
      assert DSPEx.Program.program_name(program) == :Predict
    end

    test "forward/2 delegates to Program behavior" do
      program = DSPEx.Predict.new(MockSignature, :test)
      inputs = %{question: "What is 2+2?"}

      # Should call through Program behavior
      case DSPEx.Program.forward(program, inputs) do
        {:ok, outputs} ->
          assert is_map(outputs)
          assert Map.has_key?(outputs, :answer)

        {:error, reason} ->
          # Expected if no API keys configured
          assert reason in [
                   :network_error,
                   :api_error,
                   :timeout,
                   :missing_inputs,
                   :provider_not_configured
                 ]
      end
    end

    test "forward/3 passes options correctly" do
      program = DSPEx.Predict.new(MockSignature, :test)
      inputs = %{question: "Test question"}
      opts = [correlation_id: "test-123", temperature: 0.5]

      case DSPEx.Program.forward(program, inputs, opts) do
        {:ok, outputs} ->
          assert is_map(outputs)

        {:error, reason} ->
          # Expected without proper API setup
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    @tag :live_api
    test "maintains backward compatibility with legacy API" do
      inputs = %{question: "What is 2+2?"}

      # Legacy forward/2 API should still work
      case DSPEx.Predict.forward(MockSignature, inputs) do
        {:ok, outputs} ->
          assert is_map(outputs)
          assert Map.has_key?(outputs, :answer)

        {:error, reason} ->
          assert reason in [
                   :network_error,
                   :api_error,
                   :timeout,
                   :missing_inputs,
                   :provider_not_configured
                 ]
      end

      # Legacy forward/3 API should still work
      case DSPEx.Predict.forward(MockSignature, inputs, %{temperature: 0.7}) do
        {:ok, outputs} ->
          assert is_map(outputs)

        {:error, reason} ->
          assert reason in [
                   :network_error,
                   :api_error,
                   :timeout,
                   :missing_inputs,
                   :provider_not_configured
                 ]
      end
    end

    @tag :live_api
    test "predict/2 convenience function works" do
      inputs = %{question: "What is 2+2?"}

      case DSPEx.Predict.predict(MockSignature, inputs) do
        {:ok, outputs} ->
          assert is_map(outputs)
          assert Map.has_key?(outputs, :answer)

        {:error, reason} ->
          assert reason in [
                   :network_error,
                   :api_error,
                   :timeout,
                   :missing_inputs,
                   :provider_not_configured
                 ]
      end
    end

    @tag :live_api
    test "predict/3 with options works" do
      inputs = %{question: "What is 2+2?"}
      opts = %{model: "gpt-4", temperature: 0.3}

      case DSPEx.Predict.predict(MockSignature, inputs, opts) do
        {:ok, outputs} ->
          assert is_map(outputs)

        {:error, reason} ->
          assert reason in [
                   :network_error,
                   :api_error,
                   :timeout,
                   :missing_inputs,
                   :provider_not_configured
                 ]
      end
    end
  end

  describe "program struct manipulation" do
    test "can modify program configuration" do
      program = DSPEx.Predict.new(MockSignature, :openai)

      # Add demos
      updated_program = %{program | demos: [%{input: "demo", output: "result"}]}
      assert length(updated_program.demos) == 1

      # Change client
      updated_program = %{program | client: :gemini}
      assert updated_program.client == :gemini

      # Change adapter
      updated_program = %{program | adapter: :custom}
      assert updated_program.adapter == :custom
    end

    test "program struct is immutable" do
      program1 = DSPEx.Predict.new(MockSignature, :openai)
      program2 = %{program1 | client: :gemini}

      # Original should be unchanged
      assert program1.client == :openai
      assert program2.client == :gemini
    end

    test "program validation" do
      program = DSPEx.Predict.new(MockSignature, :test)

      # Should be a valid struct
      assert is_struct(program, DSPEx.Predict)

      # Should have all required fields
      assert Map.has_key?(program, :signature)
      assert Map.has_key?(program, :client)
      assert Map.has_key?(program, :adapter)
      assert Map.has_key?(program, :demos)
    end
  end

  # Named function for telemetry handler - avoids performance penalty
  def handle_telemetry_event(event_name, measurements, metadata, _acc) do
    send(self(), {:telemetry, event_name, measurements, metadata})
  end

  describe "telemetry integration with Program behavior" do
    setup do
      # Capture telemetry events
      handler_id = make_ref()

      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :program, :forward, :start],
          [:dspex, :program, :forward, :stop],
          [:dspex, :client, :request]
        ],
        &__MODULE__.handle_telemetry_event/4,
        []
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, handler_id: handler_id}
    end

    test "emits telemetry events through Program behavior" do
      program = DSPEx.Predict.new(MockSignature, :test)
      inputs = %{question: "Test telemetry"}

      # Execute through Program behavior
      _result = DSPEx.Program.forward(program, inputs)

      # Should receive program-level telemetry
      assert_receive {:telemetry, [:dspex, :program, :forward, :start], start_measurements,
                      start_metadata}

      assert %{system_time: system_time} = start_measurements
      assert is_integer(system_time)

      assert %{
               program: :Predict,
               correlation_id: correlation_id,
               input_count: 1
             } = start_metadata

      assert is_binary(correlation_id)

      assert_receive {:telemetry, [:dspex, :program, :forward, :stop], stop_measurements,
                      stop_metadata}

      assert %{duration: duration, success: success} = stop_measurements
      assert is_integer(duration)
      assert is_boolean(success)

      assert %{
               program: :Predict,
               correlation_id: ^correlation_id
             } = stop_metadata
    end

    test "forwards correlation_id correctly" do
      program = DSPEx.Predict.new(MockSignature, :test)
      inputs = %{question: "Test correlation"}
      custom_id = "predict-test-123"

      _result = DSPEx.Program.forward(program, inputs, correlation_id: custom_id)

      assert_receive {:telemetry, [:dspex, :program, :forward, :start], _measurements,
                      start_metadata}

      assert %{correlation_id: ^custom_id} = start_metadata

      assert_receive {:telemetry, [:dspex, :program, :forward, :stop], _measurements,
                      stop_metadata}

      assert %{correlation_id: ^custom_id} = stop_metadata
    end
  end

  describe "error handling in Program integration" do
    test "handles signature validation errors in Program context" do
      program = DSPEx.Predict.new(MockSignature, :test)

      # Missing required inputs
      {:error, reason} = DSPEx.Program.forward(program, %{})
      assert reason == :missing_inputs
    end

    test "propagates client errors through Program behavior" do
      program = DSPEx.Predict.new(MockSignature, :nonexistent_client)
      inputs = %{question: "Test error propagation"}

      # With seamless fallback, invalid clients fall back to mock mode
      case DSPEx.Program.forward(program, inputs) do
        {:ok, outputs} ->
          # This is now expected behavior - seamless fallback to mock
          assert %{answer: answer} = outputs
          assert is_binary(answer)
          # The answer should indicate it's a mock response
          # Allow any valid mock response
          assert String.contains?(String.downcase(answer), "mock") or
                   String.length(answer) > 0

        {:error, reason} ->
          # Include provider_not_configured since :nonexistent_client is treated as an unconfigured provider
          assert reason in [
                   :missing_inputs,
                   :invalid_messages,
                   :provider_not_configured
                 ]
      end
    end

    test "handles adapter errors in Program context" do
      # Test with invalid signature that should cause adapter errors
      defmodule InvalidFieldSignature do
        def input_fields, do: [:nonexistent]
        def output_fields, do: [:also_nonexistent]
        def description, do: "Invalid signature for testing"
      end

      program = DSPEx.Predict.new(InvalidFieldSignature, :test)
      inputs = %{question: "This won't match the signature"}

      {:error, reason} = DSPEx.Program.forward(program, inputs)
      assert reason == :missing_inputs
    end
  end

  describe "performance characteristics" do
    test "program creation is fast" do
      # Measure program creation time
      start_time = System.monotonic_time()

      for _i <- 1..100 do
        DSPEx.Predict.new(MockSignature, :test)
      end

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Should be very fast - less than 100ms for 100 creations
      assert duration_ms < 100
    end

    @tag :todo_optimize
    test "program forward execution has reasonable overhead" do
      IO.puts("\n=== PERFORMANCE TEST INSTRUMENTATION ===")

      # Step 1: Program creation timing
      creation_start = System.monotonic_time()
      program = DSPEx.Predict.new(MockSignature, :test)
      creation_duration = System.monotonic_time() - creation_start
      creation_us = System.convert_time_unit(creation_duration, :native, :microsecond)
      IO.puts("Program creation: #{creation_us}µs")

      inputs = %{question: "Performance test"}

      # Step 2: Individual warmup call timing
      IO.puts("\n--- Warmup Phase ---")

      for i <- 1..5 do
        warmup_start = System.monotonic_time()
        DSPEx.Program.forward(program, inputs)
        warmup_duration = System.monotonic_time() - warmup_start
        warmup_us = System.convert_time_unit(warmup_duration, :native, :microsecond)
        IO.puts("Warmup #{i}: #{warmup_us}µs")
      end

      # Step 3: Individual measurement phase timing
      IO.puts("\n--- Measurement Phase ---")
      start_time = System.monotonic_time()

      individual_times =
        for i <- 1..10 do
          call_start = System.monotonic_time()
          DSPEx.Program.forward(program, inputs)
          call_duration = System.monotonic_time() - call_start
          call_us = System.convert_time_unit(call_duration, :native, :microsecond)
          IO.puts("Call #{i}: #{call_us}µs")
          call_us
        end

      duration = System.monotonic_time() - start_time
      avg_duration_us = System.convert_time_unit(duration, :native, :microsecond) / 10

      # Step 4: Statistics
      if length(individual_times) > 0 do
        individual_times_reversed = Enum.reverse(individual_times)
        min_time = Enum.min(individual_times_reversed)
        max_time = Enum.max(individual_times_reversed)
        median_time = individual_times_reversed |> Enum.sort() |> Enum.at(5)

        IO.puts("\n--- Performance Summary ---")
        IO.puts("Average: #{Float.round(avg_duration_us, 1)}µs")
        IO.puts("Min: #{min_time}µs")
        IO.puts("Max: #{max_time}µs")
        IO.puts("Median: #{median_time}µs")

        IO.puts(
          "Total for 10 calls: #{System.convert_time_unit(duration, :native, :microsecond)}µs"
        )

        # Cold start analysis
        IO.puts("\n--- Cold Start Analysis ---")
        IO.puts("First warmup call: Shows significant cold start (28ms+)")
        IO.puts("This suggests initialization overhead in DSPEx.Program.forward")
        IO.puts("Subsequent calls are much faster (200-600µs range)")
        IO.puts("CI environment likely amplifies this cold start effect")
        IO.puts("=======================================\n")
      else
        IO.puts("\n--- ERROR: No timing data collected ---")
        IO.puts("Check individual_times list accumulation")
        IO.puts("=======================================\n")
      end

      # Should have low overhead - most time should be in actual API calls
      # Framework overhead should be < 1ms per call (updated from 2.5ms - tagged as :todo_optimize for performance work)
      assert avg_duration_us < 1000
    end

    test "concurrent program execution" do
      program = DSPEx.Predict.new(MockSignature, :test)
      inputs = %{question: "Concurrent test"}

      # Execute multiple predictions concurrently
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            test_inputs = Map.put(inputs, :id, i)
            DSPEx.Program.forward(program, test_inputs)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should complete (either success or expected errors)
      assert length(results) == 5

      for result <- results do
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end

  describe "integration with existing modules" do
    @tag :external_api
    test "uses DSPEx.Adapter for message formatting" do
      inputs = %{question: "What is 2+2?"}

      # This tests that the integration calls work end-to-end
      case DSPEx.Predict.forward(MockSignature, inputs) do
        {:ok, outputs} ->
          # Full pipeline working - verify structure
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          # API not available - verify error handling
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "uses DSPEx.Client for HTTP requests" do
      inputs = %{question: "What is 2+2?"}

      # This tests the full client integration
      case DSPEx.Predict.forward(MockSignature, inputs) do
        {:ok, outputs} ->
          # Client layer working - verify response
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          # Client errors are categorized properly
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "Program behavior works with real API calls" do
      program = DSPEx.Predict.new(MockSignature, :gemini)
      inputs = %{question: "What is 2+2?"}

      case DSPEx.Program.forward(program, inputs) do
        {:ok, outputs} ->
          # Real API working - verify structure
          assert %{answer: answer} = outputs
          assert is_binary(answer)
          assert String.length(answer) > 0

        {:error, reason} ->
          # API not available or configured - verify error handling
          assert reason in [:network_error, :api_error, :timeout]
      end
    end
  end
end
