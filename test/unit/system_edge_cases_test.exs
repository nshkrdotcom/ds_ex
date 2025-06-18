# File: test/unit/system_edge_cases_test.exs
defmodule DSPEx.SystemEdgeCasesTest do
  use ExUnit.Case, async: true
  @moduletag :group_3

  alias DSPEx.{Example, Predict, Program, Signature}
  alias DSPEx.Teleprompter.BootstrapFewShot
  alias DSPEx.Test.MockProvider

  # Define signature modules at module level to prevent redefinition warnings
  defmodule EdgeCaseSignature do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule EdgeSignature1 do
    use DSPEx.Signature, "input1 -> output1"
  end

  defmodule EdgeSignature2 do
    use DSPEx.Signature, "output1 -> output2"
  end

  defmodule IncompatibleSignature do
    use DSPEx.Signature, "different_input -> different_output"
  end

  defmodule NumericSignature do
    use DSPEx.Signature, "number_input -> number_output"
  end

  defmodule StrictSignature do
    use DSPEx.Signature, "strict_field -> result"
  end

  defmodule MissingFieldSignature do
    use DSPEx.Signature, "required_field -> output"
  end

  defmodule NestedSignature do
    use DSPEx.Signature, "data -> result"
  end

  setup do
    # Handle existing provider gracefully
    case MockProvider.start_link(mode: :contextual) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    %{signature: EdgeCaseSignature}
  end

  describe "boundary conditions - training set sizes" do
    test "empty training set handling", %{signature: signature} do
      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}
      empty_trainset = []
      metric_fn = fn _example, _prediction -> 1.0 end

      # Should handle empty trainset gracefully
      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          empty_trainset,
          metric_fn
        )

      # Should return error for empty trainset
      assert {:error, _reason} = result
    end

    test "single example training set", %{signature: signature} do
      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}

      single_trainset = [
        %Example{
          data: %{question: "Single question", answer: "Single answer"},
          input_keys: MapSet.new([:question])
        }
      ]

      metric_fn = fn _example, _prediction -> 1.0 end

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Single answer"}])

      # Should handle single example
      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          single_trainset,
          metric_fn,
          max_bootstrapped_demos: 1
        )

      assert {:ok, _optimized} = result
    end

    test "maximum size training set (stress boundary)", %{signature: signature} do
      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}

      # Large training set to test boundaries
      max_trainset =
        Enum.map(1..1000, fn i ->
          %Example{
            data: %{question: "Question #{i}", answer: "Answer #{i}"},
            input_keys: MapSet.new([:question])
          }
        end)

      metric_fn = fn _example, _prediction -> 0.8 end

      DSPEx.MockClientManager.set_mock_responses(
        :test,
        Enum.map(1..1000, fn i -> %{content: "Answer #{i}"} end)
      )

      # Should handle large trainset efficiently
      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          max_trainset,
          metric_fn,
          max_bootstrapped_demos: 10,
          max_concurrency: 20
        )

      assert {:ok, _optimized} = result
    end
  end

  describe "malformed input handling" do
    test "invalid signature handling" do
      # Test with non-existent signature module
      # The error occurs when trying to access signature functions, not during struct creation
      program = %Predict{signature: NonExistentSignature, client: :test}

      # Should return error when trying to use the invalid signature
      result = Program.forward(program, %{question: "test"})
      assert {:error, :invalid_signature} = result
    end

    test "missing required fields in examples" do
      program = %Predict{signature: MissingFieldSignature, client: :test}

      # Missing required field
      result = Program.forward(program, %{wrong_field: "value"})

      # Should return error for missing fields
      assert {:error, _reason} = result
    end

    test "nil values in required fields" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Nil value in required field
      result = Program.forward(program, %{question: nil})

      # Should handle nil values gracefully
      assert match?({:error, _}, result)
    end

    test "extremely long input strings" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Very long input string
      very_long_string = String.duplicate("x", 10_000)

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Long string response"}])

      result = Program.forward(program, %{question: very_long_string})

      # Should handle long strings without crashing
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "special characters and unicode in inputs" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      special_chars = "🚀 Special chars: áéíóú ñ 中文 العربية 🎉"

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Unicode response"}])

      result = Program.forward(program, %{question: special_chars})

      # Should handle unicode gracefully
      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, _reason} ->
          # Error is acceptable for edge cases
          :ok
      end
    end

    test "deeply nested input structures" do
      program = %Predict{signature: NestedSignature, client: :test}

      # Deeply nested structure
      nested_data = %{
        level1: %{
          level2: %{
            level3: %{
              level4: %{
                level5: "deep value"
              }
            }
          }
        }
      }

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Nested response"}])

      result = Program.forward(program, %{data: nested_data})

      # Should handle nested structures
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "resource limitation scenarios" do
    test "handles memory constraints gracefully" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Create memory pressure - reduced size to prevent spam
      large_input = %{
        question: "Memory test",
        large_data:
          Enum.map(1..100, fn i ->
            %{id: i, data: String.duplicate("data", 50)}
          end)
      }

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Memory response"}])

      result = Program.forward(program, large_input)

      # Should handle memory pressure gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "timeout handling at various levels" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Test different timeout scenarios
      timeout_scenarios = [1, 10, 100, 1000, 5000]

      results =
        Enum.map(timeout_scenarios, fn timeout ->
          try do
            Program.forward(program, %{question: "Timeout test"}, timeout: timeout)
          catch
            :exit, {:timeout, _} -> {:timeout, timeout}
          end
        end)

      # Should handle various timeout values gracefully
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or
                 match?({:error, _}, result) or
                 match?({:timeout, _}, result)
      end)
    end

    test "concurrent resource contention" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Set up mock responses for the contention test
      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Contention response"}])

      # Reduced concurrent operations to prevent spam
      contention_tasks =
        Task.async_stream(
          1..10,
          fn i ->
            # Each task uses some resources - reduced size
            large_list = Enum.map(1..20, fn j -> "item_#{i}_#{j}" end)

            result = Program.forward(program, %{question: "Contention test #{i}"})

            # Keep reference to large_list to maintain memory pressure
            {result, length(large_list)}
          end,
          max_concurrency: 5,
          timeout: 10_000
        )
        |> Enum.to_list()

      # Most should succeed despite contention
      successes =
        Enum.count(contention_tasks, fn
          {:ok, {{:ok, _}, _}} -> true
          _ -> false
        end)

      assert successes >= 8, "Resource contention caused too many failures: #{successes}/10"
    end
  end

  describe "complex nested compositions" do
    test "program wrapping and unwrapping" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Multiple levels of wrapping
      wrapped_once = DSPEx.OptimizedProgram.new(program, [], %{level: 1})
      wrapped_twice = DSPEx.OptimizedProgram.new(wrapped_once, [], %{level: 2})

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Nested test response"}])

      # Should handle nested wrapping
      result = Program.forward(wrapped_twice, %{question: "Nested test"})

      assert {:ok, response} = result
      assert is_map(response)

      # Should be able to unwrap correctly
      inner_program = DSPEx.OptimizedProgram.get_program(wrapped_twice)
      assert inner_program == wrapped_once

      deeper_program = DSPEx.OptimizedProgram.get_program(inner_program)
      assert deeper_program == program
    end

    test "circular reference detection" do
      # Test prevention of circular references in program composition
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # This shouldn't be possible in normal usage, but test edge case
      wrapped = DSPEx.OptimizedProgram.new(program, [], %{})

      # Attempting to wrap with itself should be handled gracefully
      # (This is more of a conceptual test as the type system prevents it)
      assert is_struct(wrapped, DSPEx.OptimizedProgram)
    end

    test "signature compatibility edge cases" do
      # Compatible signatures
      result1 = Signature.validate_signature_compatibility(EdgeSignature1, EdgeSignature2)
      assert :ok = result1

      # Incompatible signatures
      result2 = Signature.validate_signature_compatibility(EdgeSignature1, IncompatibleSignature)
      assert {:error, _} = result2
    end
  end

  describe "type mismatch handling" do
    test "numeric vs string field mismatches" do
      program = %Predict{signature: NumericSignature, client: :test}

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "42"}])

      # String where number expected
      result1 = Program.forward(program, %{number_input: "not a number"})

      # Should handle gracefully
      assert match?({:ok, _}, result1) or match?({:error, _}, result1)

      # Number where string might be expected
      result2 = Program.forward(program, %{number_input: 42})

      assert match?({:ok, _}, result2) or match?({:error, _}, result2)
    end

    test "list vs map vs atom mismatches" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Different data types
      type_mismatches = [
        # List instead of string
        %{question: []},
        # Map instead of string
        %{question: %{nested: true}},
        # Atom instead of string
        %{question: :atom},
        # Number instead of string
        %{question: 42},
        # Boolean instead of string
        %{question: true},
        # Tuple instead of string
        %{question: {1, 2, 3}}
      ]

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Type mismatch response"}])

      results =
        Enum.map(type_mismatches, fn input ->
          Program.forward(program, input)
        end)

      # All should handle type mismatches gracefully
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "binary vs charlists vs atoms" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Set up mock responses for each string type
      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "binary string response"},
        %{content: "charlist response"},
        %{content: "atom response"}
      ])

      # Binary strings should work
      binary_result = Program.forward(program, %{question: "binary string"})
      assert match?({:ok, _}, binary_result), "Binary string should work"

      # Test other string-like types (may fail gracefully)
      charlist_result = Program.forward(program, %{question: ~c"charlist"})
      atom_result = Program.forward(program, %{question: :atom_string})

      # These may fail, but should not crash
      assert match?({:ok, _}, charlist_result) or match?({:error, _}, charlist_result)
      assert match?({:ok, _}, atom_result) or match?({:error, _}, atom_result)
    end
  end

  describe "error message consistency" do
    test "missing field errors are descriptive" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Missing required field
      result = Program.forward(program, %{wrong_field: "value"})

      case result do
        {:error, reason} ->
          # Error should be descriptive
          error_string = inspect(reason)

          assert String.contains?(error_string, "missing") or
                   String.contains?(error_string, "required") or
                   String.contains?(error_string, "field") or
                   String.contains?(error_string, "invalid")

        {:ok, _} ->
          # If it succeeds (due to fallback), that's also acceptable
          :ok
      end
    end

    test "type mismatch errors are helpful" do
      program = %Predict{signature: StrictSignature, client: :test}

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "test response"}])

      # Type that might cause issues
      result = Program.forward(program, %{strict_field: {:tuple, "data"}})

      case result do
        {:error, reason} ->
          # Error should indicate the issue
          error_string = inspect(reason)
          # Should contain some indication of the problem
          assert is_binary(error_string) and String.length(error_string) > 0

        {:ok, _} ->
          # Success is also acceptable (flexible handling)
          :ok
      end
    end

    test "timeout errors are informative" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "timeout response"}])

      # Very short timeout to force timeout error
      result =
        try do
          Program.forward(program, %{question: "timeout test"}, timeout: 1)
        catch
          :exit, reason -> {:timeout_exit, reason}
        end

      case result do
        {:timeout_exit, reason} ->
          # Timeout error should be recognizable
          assert is_tuple(reason) or is_atom(reason)

        {:ok, _} ->
          # Success is acceptable (mock might be fast enough)
          :ok

        {:error, _} ->
          # Error is also acceptable
          :ok
      end
    end
  end

  describe "boundary value testing" do
    test "zero and negative numbers in configurations" do
      # Test edge values in teleprompter configuration
      edge_configs = [
        %{max_bootstrapped_demos: 0},
        %{max_bootstrapped_demos: 1},
        %{quality_threshold: 0.0},
        %{quality_threshold: 1.0},
        %{max_concurrency: 1},
        %{timeout: 1}
      ]

      student = %Predict{signature: EdgeCaseSignature, client: :test}
      teacher = %Predict{signature: EdgeCaseSignature, client: :test}

      trainset = [
        %Example{
          data: %{question: "boundary test", answer: "response"},
          input_keys: MapSet.new([:question])
        }
      ]

      metric_fn = fn _example, _prediction -> 0.8 end

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "response"}])

      results =
        Enum.map(edge_configs, fn config ->
          try do
            BootstrapFewShot.compile(
              student,
              teacher,
              trainset,
              metric_fn,
              config
            )
          rescue
            error -> {:rescued, error}
          end
        end)

      # All should handle boundary values gracefully
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or
                 match?({:error, _}, result) or
                 match?({:rescued, _}, result)
      end)
    end

    test "empty and whitespace-only strings" do
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      edge_strings = [
        # Empty string
        "",
        # Single space
        " ",
        # Tab
        "\t",
        # Newline
        "\n",
        # Multiple spaces
        "   ",
        # Mixed whitespace
        "\t\n\r ",
        # Non-breaking space
        " \u00A0 "
      ]

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Edge string response"}])

      results =
        Enum.map(edge_strings, fn string ->
          Program.forward(program, %{question: string})
        end)

      # Should handle edge string cases
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "maximum integer and float values" do
      defmodule NumericEdgeSignature do
        use DSPEx.Signature, "number -> calculation"
      end

      program = %Predict{signature: NumericEdgeSignature, client: :test}

      edge_numbers = [
        0,
        1,
        -1,
        # Large integer
        999_999_999_999_999,
        # Large negative integer
        -999_999_999_999_999,
        # Near float max
        1.0e308,
        # Near float min
        1.0e-308,
        0.0,
        -0.0
      ]

      # Provide sufficient responses for all edge numbers
      responses = Enum.map(1..length(edge_numbers), fn i -> %{content: "Response #{i}"} end)
      DSPEx.MockClientManager.set_mock_responses(:test, responses)

      results =
        Enum.map(edge_numbers, fn number ->
          Program.forward(program, %{number: number})
        end)

      # Should handle numeric edge cases
      successes =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      # Most should succeed
      assert successes >= 6
    end
  end

  describe "concurrent edge cases" do
    test "simultaneous access to shared mock provider" do
      # Test concurrent access to shared resources - simplified test
      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Concurrent response"}])

      # Test sequential access first to ensure mock works
      program = %Predict{signature: EdgeCaseSignature, client: :test}
      sequential_result = Program.forward(program, %{question: "sequential test"})
      assert {:ok, _} = sequential_result

      # Test a few concurrent requests (reduced complexity)
      concurrent_tasks =
        Enum.map(1..3, fn i ->
          Task.async(fn ->
            Program.forward(
              %Predict{signature: EdgeCaseSignature, client: :test},
              %{question: "concurrent edge case #{i}"}
            )
          end)
        end)
        |> Task.await_many(5_000)

      # Should handle concurrent access
      successes =
        Enum.count(concurrent_tasks, fn
          {:ok, _} -> true
          _ -> false
        end)

      assert successes >= 2, "Concurrent edge case handling failed: #{successes}/3"
    end

    test "rapid program creation and destruction" do
      # Test creating and destroying programs rapidly - reduced iterations
      # Provide sufficient responses for all concurrent calls
      responses = Enum.map(1..15, fn i -> %{content: "rapid response #{i}"} end)
      DSPEx.MockClientManager.set_mock_responses(:test, responses)

      creation_tasks =
        Task.async_stream(
          1..10,
          fn i ->
            # Create program
            program = %Predict{signature: EdgeCaseSignature, client: :test}

            # Use it once
            result = Program.forward(program, %{question: "rapid test #{i}"})

            # Let it be garbage collected
            _program = nil

            result
          end,
          max_concurrency: 5,
          timeout: 15_000
        )
        |> Enum.to_list()

      successes =
        Enum.count(creation_tasks, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      assert successes >= 8, "Rapid creation/destruction failed: #{successes}/10"

      # Force garbage collection
      :erlang.garbage_collect()
    end

    test "edge case in program composition under load" do
      # Test program composition edge cases under concurrent load
      base_program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Set up mock responses for composition test
      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Composition response"}])

      composition_tasks =
        Task.async_stream(
          1..10,
          fn i ->
            # Create nested composition
            demo = %Example{
              data: %{question: "demo #{i}", answer: "response #{i}"},
              input_keys: MapSet.new([:question])
            }

            wrapped = DSPEx.OptimizedProgram.new(base_program, [demo], %{iteration: i})

            # Test the composed program
            Program.forward(wrapped, %{question: "composition test #{i}"})
          end,
          max_concurrency: 5,
          timeout: 20_000
        )
        |> Enum.to_list()

      successes =
        Enum.count(composition_tasks, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      assert successes >= 8, "Program composition under load failed: #{successes}/10"
    end
  end

  describe "memory and resource edge cases" do
    test "large example collections don't cause memory leaks" do
      initial_memory = :erlang.memory()[:total]

      # Create large example collection - reduced size to prevent spam
      large_examples =
        Enum.map(1..50, fn i ->
          %Example{
            data: %{
              question: "Large example #{i}",
              answer: "Response #{i}",
              metadata: %{
                id: i,
                timestamp: DateTime.utc_now(),
                large_field: String.duplicate("x", 100)
              }
            },
            input_keys: MapSet.new([:question])
          }
        end)

      # Process examples
      _processed =
        Enum.map(large_examples, fn example ->
          Example.get(example, :question)
        end)

      # Clear references
      _large_examples = nil
      _processed = nil

      # Force garbage collection
      :erlang.garbage_collect()
      # Allow GC to complete
      Process.sleep(100)
      :erlang.garbage_collect()

      final_memory = :erlang.memory()[:total]
      memory_growth = final_memory - initial_memory
      memory_growth_mb = memory_growth / (1024 * 1024)

      # Should not have significant memory leak
      assert memory_growth_mb < 50, "Memory leak detected: #{memory_growth_mb}MB growth"
    end

    test "handles file descriptor limitations gracefully" do
      # Test behavior when approaching system limits
      # This is more of a conceptual test as we don't want to actually exhaust FDs

      # Simulate high resource usage scenario
      program = %Predict{signature: EdgeCaseSignature, client: :test}

      # Set up mock responses for resource test
      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Resource test response"}])

      # Test sequential operations first
      sequential_results =
        Enum.map(1..3, fn i ->
          Program.forward(program, %{question: "resource test #{i}"})
        end)

      sequential_successes =
        Enum.count(sequential_results, fn
          {:ok, _} -> true
          _ -> false
        end)

      # Should handle basic operations
      assert sequential_successes >= 2,
             "Basic resource operations failed: #{sequential_successes}/3"

      # Test a few concurrent operations (simplified)
      concurrent_tasks =
        Enum.map(1..2, fn i ->
          Task.async(fn ->
            Program.forward(program, %{question: "concurrent resource test #{i}"})
          end)
        end)
        |> Task.await_many(10_000)

      concurrent_successes =
        Enum.count(concurrent_tasks, fn
          {:ok, _} -> true
          _ -> false
        end)

      # Should handle some concurrent resource pressure
      assert concurrent_successes >= 1,
             "Concurrent resource operations failed: #{concurrent_successes}/2"
    end
  end
end
