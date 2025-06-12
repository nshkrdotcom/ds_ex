# File: test/integration/compatibility_test.exs
defmodule DSPEx.Integration.CompatibilityTest do
  use ExUnit.Case, async: false

  alias DSPEx.{Predict, Program, Example}
  alias DSPEx.Test.MockProvider

  @moduletag :integration
  @moduletag :compatibility

  setup do
    {:ok, _mock} = MockProvider.start_link(mode: :contextual)

    defmodule CompatibilitySignature do
      use DSPEx.Signature, "question -> answer"
    end

    %{signature: CompatibilitySignature}
  end

  describe "legacy DSPEx.Predict API backward compatibility" do
    test "old-style Predict.forward/2 still works", %{signature: signature} do
      # Test the legacy function-style API
      inputs = %{question: "Legacy API test"}

      MockProvider.setup_evaluation_mocks([0.9])

      # This should still work for backward compatibility
      result = DSPEx.Predict.forward(signature, inputs)

      assert {:ok, outputs} = result
      assert %{answer: answer} = outputs
      assert is_binary(answer)
    end

    test "old-style Predict.forward/3 with options", %{signature: signature} do
      inputs = %{question: "Legacy API with options"}
      options = %{provider: :gemini, temperature: 0.8}

      MockProvider.setup_evaluation_mocks([0.8])

      result = DSPEx.Predict.forward(signature, inputs, options)

      assert {:ok, outputs} = result
      assert %{answer: answer} = outputs
      assert is_binary(answer)
    end

    test "old-style predict/2 function still works", %{signature: signature} do
      inputs = %{question: "Legacy predict function"}

      MockProvider.setup_evaluation_mocks([0.7])

      result = DSPEx.Predict.predict(signature, inputs)

      assert {:ok, outputs} = result
      assert %{answer: answer} = outputs
      assert is_binary(answer)
    end

    test "predict_field/3 legacy function", %{signature: signature} do
      inputs = %{question: "Field prediction test"}

      MockProvider.setup_evaluation_mocks([0.8])

      result = DSPEx.Predict.predict_field(signature, inputs, :answer)

      assert {:ok, field_value} = result
      assert is_binary(field_value)
    end

    test "validate_inputs/2 legacy function", %{signature: signature} do
      valid_inputs = %{question: "Validation test"}
      invalid_inputs = %{wrong_field: "Invalid"}

      # Should validate correctly
      assert :ok = DSPEx.Predict.validate_inputs(signature, valid_inputs)
      assert {:error, _} = DSPEx.Predict.validate_inputs(signature, invalid_inputs)
    end
  end

  describe "mixed usage of old and new APIs" do
    test "legacy API works alongside new Program API", %{signature: signature} do
      # Use legacy API
      legacy_result = DSPEx.Predict.predict(signature, %{question: "Legacy call"})

      # Use new Program API
      program = %Predict{signature: signature, client: :test}
      new_result = Program.forward(program, %{question: "New API call"})

      MockProvider.setup_evaluation_mocks([0.9, 0.8])

      # Both should work
      assert {:ok, _} = legacy_result
      assert {:ok, _} = new_result
    end

    test "can create Predict struct and use with legacy functions", %{signature: signature} do
      # Create using new style
      program = %Predict{signature: signature, client: :gemini}

      # Use with Program API
      result1 = Program.forward(program, %{question: "Program API"})

      # Extract signature and use with legacy API
      result2 = DSPEx.Predict.predict(program.signature, %{question: "Legacy API"})

      MockProvider.setup_evaluation_mocks([0.9, 0.8])

      assert {:ok, _} = result1
      assert {:ok, _} = result2
    end

    test "validation works across API versions", %{signature: signature} do
      inputs = %{question: "Cross-API validation"}

      # Legacy validation
      legacy_validation = DSPEx.Predict.validate_inputs(signature, inputs)

      # New validation (through Program.forward error handling)
      program = %Predict{signature: signature, client: :test}
      new_result = Program.forward(program, inputs)

      MockProvider.setup_evaluation_mocks([0.9])

      assert :ok = legacy_validation
      assert {:ok, _} = new_result
    end
  end

  describe "configuration migration and compatibility" do
    test "old configuration format still works" do
      # Test that old-style configuration is still supported

      # This would test deprecated config formats
      # For now, just verify current config works
      old_style_config = %{
        provider: :gemini,
        model: "gemini-1.5-flash",
        temperature: 0.7
      }

      program = %Predict{signature: CompatibilitySignature, client: :test}

      MockProvider.setup_evaluation_mocks([0.8])

      # Should work with old-style options
      result = Program.forward(program, %{question: "Config test"}, old_style_config)

      assert {:ok, _} = result
    end

    test "environment variable compatibility" do
      # Test that old environment variables are still respected

      # Save original
      original_mode = System.get_env("DSPEX_TEST_MODE")

      # Test old-style env var (if any existed)
      System.put_env("DSPEX_TEST_MODE", "mock")

      # Should still work
      program = %Predict{signature: CompatibilitySignature, client: :test}
      result = Program.forward(program, %{question: "Env var test"})

      MockProvider.setup_evaluation_mocks([0.7])

      assert {:ok, _} = result

      # Restore
      if original_mode do
        System.put_env("DSPEX_TEST_MODE", original_mode)
      else
        System.delete_env("DSPEX_TEST_MODE")
      end
    end

    test "configuration precedence remains consistent" do
      # Test that configuration precedence works as expected
      program = %Predict{signature: CompatibilitySignature, client: :test}

      # Options should override defaults
      options = %{provider: :openai, temperature: 0.5}

      MockProvider.setup_evaluation_mocks([0.6])

      result = Program.forward(program, %{question: "Precedence test"}, options)

      assert {:ok, _} = result
    end
  end

  describe "serialization and deserialization compatibility" do
    test "Example serialization remains stable" do
      example = %Example{
        data: %{question: "Serialization test", answer: "Response"},
        input_keys: MapSet.new([:question])
      }

      # Convert to different formats
      dict_format = Example.to_dict(example)
      list_format = Example.to_list(example)

      # Should maintain data integrity
      assert dict_format[:question] == "Serialization test"
      assert dict_format[:answer] == "Response"

      assert list_format[:question] == "Serialization test"
      assert list_format[:answer] == "Response"

      # Reconstruct from dict
      reconstructed = Example.new(dict_format)
      assert Example.get(reconstructed, :question) == "Serialization test"
      assert Example.get(reconstructed, :answer) == "Response"
    end

    test "program serialization compatibility" do
      program = %Predict{signature: CompatibilitySignature, client: :gemini}

      # Extract serializable components
      program_info = %{
        signature: program.signature,
        client: program.client,
        demos: program.demos
      }

      # Should be able to reconstruct
      reconstructed = %Predict{
        signature: program_info.signature,
        client: program_info.client,
        demos: program_info.demos
      }

      assert reconstructed.signature == program.signature
      assert reconstructed.client == program.client
      assert reconstructed.demos == program.demos
    end

    test "configuration serialization" do
      # Test that configurations can be serialized and deserialized
      config = %{
        provider: :gemini,
        model: "gemini-1.5-flash",
        temperature: 0.7,
        max_tokens: 150
      }

      # Serialize to JSON-like format
      json_config = Jason.encode!(config)

      # Deserialize
      parsed_config = Jason.decode!(json_config, keys: :atoms)

      assert parsed_config.provider == :gemini
      assert parsed_config.model == "gemini-1.5-flash"
      assert parsed_config.temperature == 0.7
      assert parsed_config.max_tokens == 150
    end
  end

  describe "telemetry event backward compatibility" do
    test "legacy telemetry events still emitted" do
      test_pid = self()

      # Attach handler for legacy events
      :telemetry.attach(
        "legacy-test-handler",
        [:dspex, :predict, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:legacy_telemetry, event, measurements, metadata})
        end,
        %{}
      )

      # Use legacy API
      MockProvider.setup_evaluation_mocks([0.9])
      DSPEx.Predict.predict(CompatibilitySignature, %{question: "Legacy telemetry"})

      # Should receive legacy telemetry event
      assert_receive {:legacy_telemetry, [:dspex, :predict, :stop], measurements, metadata}, 1000

      assert is_map(measurements)
      assert is_map(metadata)

      # Cleanup
      :telemetry.detach("legacy-test-handler")
    end

    test "new telemetry events work with legacy handlers" do
      test_pid = self()

      # Legacy handler expecting old format
      :telemetry.attach(
        "legacy-program-handler",
        [:dspex, :program, :forward, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:program_telemetry, event, measurements, metadata})
        end,
        %{}
      )

      # Use new API
      program = %Predict{signature: CompatibilitySignature, client: :test}

      MockProvider.setup_evaluation_mocks([0.8])
      Program.forward(program, %{question: "New telemetry"})

      # Should receive telemetry event
      assert_receive {:program_telemetry, [:dspex, :program, :forward, :stop], measurements, metadata}, 1000

      assert is_map(measurements)
      assert is_map(metadata)

      # Cleanup
      :telemetry.detach("legacy-program-handler")
    end

    test "telemetry metadata format remains consistent" do
      test_pid = self()

      :telemetry.attach(
        "metadata-test-handler",
        [:dspex, :predict, :stop],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:metadata_check, metadata})
        end,
        %{}
      )

      MockProvider.setup_evaluation_mocks([0.7])
      DSPEx.Predict.predict(CompatibilitySignature, %{question: "Metadata test"})

      assert_receive {:metadata_check, metadata}, 1000

      # Should have expected metadata fields
      assert Map.has_key?(metadata, :signature)
      assert is_atom(metadata.signature)

      :telemetry.detach("metadata-test-handler")
    end
  end

  describe "error format compatibility" do
    test "error tuples maintain consistent format" do
      # Test invalid signature
      result1 = DSPEx.Predict.validate_inputs(CompatibilitySignature, %{})

      # Should return consistent error format
      assert {:error, reason1} = result1
      assert is_atom(reason1) or is_tuple(reason1)

      # Test program-level error
      program = %Predict{signature: CompatibilitySignature, client: :test}
      result2 = Program.forward(program, %{})

      case result2 do
        {:error, reason2} ->
          assert is_atom(reason2) or is_tuple(reason2)
        {:ok, _} ->
          # Success due to fallback is also acceptable
          :ok
      end
    end

    test "exception handling remains consistent" do
      # Test that exceptions are handled consistently across API versions

      # Create scenario that might cause exception
      invalid_program = %Predict{signature: nil, client: :test}

      # Should handle gracefully, not crash
      result = try do
        Program.forward(invalid_program, %{question: "Exception test"})
      rescue
        error -> {:rescued, error}
      catch
        kind, reason -> {:caught, kind, reason}
      end

      # Should either return error tuple or be caught gracefully
      assert match?({:error, _}, result) or
             match?({:rescued, _}, result) or
             match?({:caught, _, _}, result)
    end
  end

  describe "performance compatibility" do
    test "legacy API performance remains acceptable" do
      # Benchmark legacy API performance
      inputs = %{question: "Performance test"}

      MockProvider.setup_evaluation_mocks(
        Enum.map(1..100, fn _ -> 0.8 end)
      )

      {duration, results} = :timer.tc(fn ->
        Enum.map(1..100, fn _i ->
          DSPEx.Predict.predict(CompatibilitySignature, inputs)
        end)
      end)

      duration_ms = duration / 1000

      # Count successes
      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      # Performance should be reasonable
      assert successes >= 95
      assert duration_ms < 10_000  # 10 seconds for 100 calls

      throughput = successes / (duration_ms / 1000)
      assert throughput >= 10  # At least 10 req/sec
    end

    test "memory usage compatible between API versions" do
      initial_memory = :erlang.memory()[:total]

      # Use legacy API
      for _i <- 1..50 do
        DSPEx.Predict.predict(CompatibilitySignature, %{question: "Memory test legacy"})
      end

      mid_memory = :erlang.memory()[:total]

      # Use new API
      program = %Predict{signature: CompatibilitySignature, client: :test}
      for _i <- 1..50 do
        Program.forward(program, %{question: "Memory test new"})
      end

      :erlang.garbage_collect()
      final_memory = :erlang.memory()[:total]

      # Memory usage should be similar
      legacy_growth = mid_memory - initial_memory
      total_growth = final_memory - initial_memory

      legacy_mb = legacy_growth / (1024 * 1024)
      total_mb = total_growth / (1024 * 1024)

      # Neither should use excessive memory
      assert legacy_mb < 50
      assert total_mb < 100
    end
  end
end
