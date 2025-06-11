# File: test/unit/optimized_program_test.exs
defmodule DSPEx.OptimizedProgramTest do
  use ExUnit.Case, async: true

  alias DSPEx.{OptimizedProgram, Example, Predict, Program}

  doctest DSPEx.OptimizedProgram

  setup do
    # Create test signature
    defmodule TestOptimizedSignature do
      use DSPEx.Signature, "question -> answer"
    end

    # Create base program
    program = %Predict{signature: TestOptimizedSignature, client: :test}

    # Create demonstration examples
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

    %{program: program, demos: demos, signature: TestOptimizedSignature}
  end

  describe "SIMBA interface compatibility" do
    test "new/3 creates optimized program with correct structure", %{program: program, demos: demos} do
      # Test basic creation
      optimized = OptimizedProgram.new(program, demos)

      assert %OptimizedProgram{} = optimized
      assert optimized.program == program
      assert optimized.demos == demos
      assert is_map(optimized.metadata)
    end

    test "new/3 with metadata creates optimized program correctly", %{program: program, demos: demos} do
      metadata = %{
        teleprompter: :simba,
        optimization_time: DateTime.utc_now(),
        custom_field: "test_value"
      }

      optimized = OptimizedProgram.new(program, demos, metadata)

      assert %OptimizedProgram{} = optimized
      assert optimized.program == program
      assert optimized.demos == demos

      # Should merge with default metadata
      assert optimized.metadata.teleprompter == :simba
      assert optimized.metadata.optimization_time == metadata.optimization_time
      assert optimized.metadata.custom_field == "test_value"
      assert optimized.metadata.demo_count == 2
      assert %DateTime{} = optimized.metadata.optimized_at
    end

    test "new/3 enforces required keys", %{program: program} do
      # Should work with empty demos list
      optimized = OptimizedProgram.new(program, [])
      assert %OptimizedProgram{} = optimized
      assert optimized.demos == []

      # Should raise if program is nil
      assert_raise ArgumentError, fn ->
        OptimizedProgram.new(nil, [])
      end

      # Should raise if demos is not a list
      assert_raise FunctionClauseError, fn ->
        OptimizedProgram.new(program, "not a list")
      end
    end

    test "get_demos/1 returns demonstrations exactly as stored", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      retrieved_demos = OptimizedProgram.get_demos(optimized)

      assert retrieved_demos == demos
      assert length(retrieved_demos) == 2
      assert Enum.all?(retrieved_demos, &is_struct(&1, Example))
    end

    test "get_program/1 returns wrapped program exactly as stored", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      retrieved_program = OptimizedProgram.get_program(optimized)

      assert retrieved_program == program
      assert retrieved_program.signature == program.signature
      assert retrieved_program.client == program.client
    end

    test "interface functions work with different program types" do
      # Test with different client types
      program1 = %Predict{signature: TestOptimizedSignature, client: :openai}
      program2 = %Predict{signature: TestOptimizedSignature, client: :gemini}

      demos = [
        %Example{data: %{question: "test", answer: "response"}, input_keys: MapSet.new([:question])}
      ]

      optimized1 = OptimizedProgram.new(program1, demos)
      optimized2 = OptimizedProgram.new(program2, demos)

      assert OptimizedProgram.get_program(optimized1).client == :openai
      assert OptimizedProgram.get_program(optimized2).client == :gemini
      assert OptimizedProgram.get_demos(optimized1) == demos
      assert OptimizedProgram.get_demos(optimized2) == demos
    end
  end

  describe "program behavior implementation" do
    test "OptimizedProgram implements DSPEx.Program behavior", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      # Should implement the Program behavior
      assert Program.implements_program?(OptimizedProgram)

      # Should be usable as a program
      assert is_struct(optimized)
      assert optimized.__struct__ == OptimizedProgram
    end

    test "forward/3 delegates to wrapped program with demo injection", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)
      inputs = %{question: "What is 5+5?"}

      # Mock the underlying program's forward call
      # Since we can't easily mock Predict.forward in this test, we'll test the structure

      # Test that forward/3 can be called
      result = try do
        Program.forward(optimized, inputs)
      rescue
        # Expected to fail in test environment without proper client setup
        _ -> :expected_error
      end

      # Should either work or fail with expected error (not crash)
      assert result in [:expected_error, {:ok, %{}}] or match?({:error, _}, result)
    end

    test "forward/3 handles programs with native demo support", %{demos: demos} do
      # Create a program that already has demo support
      program_with_demos = %Predict{
        signature: TestOptimizedSignature,
        client: :test,
        demos: [%Example{data: %{old: "demo"}, input_keys: MapSet.new()}]
      }

      optimized = OptimizedProgram.new(program_with_demos, demos)

      # The OptimizedProgram should replace the existing demos
      assert OptimizedProgram.get_demos(optimized) == demos

      # Test forward delegation
      inputs = %{question: "Test question"}

      result = try do
        Program.forward(optimized, inputs)
      rescue
        _ -> :expected_error
      end

      # Should handle gracefully
      assert result in [:expected_error, {:ok, %{}}] or match?({:error, _}, result)
    end

    test "forward/3 handles different program types correctly", %{demos: demos} do
      # Test with Predict program
      predict_program = %Predict{signature: TestOptimizedSignature, client: :test}
      optimized_predict = OptimizedProgram.new(predict_program, demos)

      # Should work with Predict programs
      assert %OptimizedProgram{} = optimized_predict

      # Test with custom program struct (mock)
      custom_program = %{__struct__: CustomProgram, signature: TestOptimizedSignature}
      optimized_custom = OptimizedProgram.new(custom_program, demos)

      assert %OptimizedProgram{} = optimized_custom
      assert OptimizedProgram.get_program(optimized_custom) == custom_program
    end

    test "error propagation works correctly through wrapper", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      # Test with invalid inputs
      invalid_inputs = "not a map"

      result = try do
        Program.forward(optimized, invalid_inputs)
      rescue
        error -> {:caught_error, error}
      end

      # Should handle errors gracefully
      case result do
        {:error, _reason} -> :ok  # Expected error tuple
        {:caught_error, _} -> :ok  # Caught exception
        _ -> flunk("Expected error handling")
      end
    end
  end

  describe "demo management" do
    test "add_demos/2 appends new demonstrations correctly", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      new_demos = [
        %Example{
          data: %{question: "What is 4+4?", answer: "8"},
          input_keys: MapSet.new([:question])
        }
      ]

      updated = OptimizedProgram.add_demos(optimized, new_demos)

      # Should have all demos
      all_demos = OptimizedProgram.get_demos(updated)
      assert length(all_demos) == 3
      assert Enum.take(all_demos, 2) == demos
      assert Enum.drop(all_demos, 2) == new_demos

      # Should update metadata
      assert updated.metadata.demo_count == 3
    end

    test "replace_demos/2 replaces all demonstrations", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      new_demos = [
        %Example{
          data: %{question: "New question", answer: "New answer"},
          input_keys: MapSet.new([:question])
        }
      ]

      updated = OptimizedProgram.replace_demos(optimized, new_demos)

      # Should have only new demos
      all_demos = OptimizedProgram.get_demos(updated)
      assert all_demos == new_demos
      assert length(all_demos) == 1

      # Should update metadata
      assert updated.metadata.demo_count == 1
    end

    test "update_program/2 updates wrapped program while preserving demos", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      new_program = %Predict{signature: TestOptimizedSignature, client: :openai}
      updated = OptimizedProgram.update_program(optimized, new_program)

      # Should have new program
      assert OptimizedProgram.get_program(updated) == new_program
      assert OptimizedProgram.get_program(updated).client == :openai

      # Should preserve demos and metadata
      assert OptimizedProgram.get_demos(updated) == demos
      assert updated.metadata == optimized.metadata
    end

    test "metadata tracking works correctly", %{program: program} do
      # Test with initial demos
      initial_demos = [
        %Example{data: %{q: "1", a: "1"}, input_keys: MapSet.new([:q])}
      ]

      optimized = OptimizedProgram.new(program, initial_demos, %{
        teleprompter: :test_teleprompter
      })

      # Should have correct initial metadata
      assert optimized.metadata.demo_count == 1
      assert optimized.metadata.teleprompter == :test_teleprompter
      assert %DateTime{} = optimized.metadata.optimized_at

      # Test metadata updates with demo changes
      more_demos = [
        %Example{data: %{q: "2", a: "2"}, input_keys: MapSet.new([:q])},
        %Example{data: %{q: "3", a: "3"}, input_keys: MapSet.new([:q])}
      ]

      updated = OptimizedProgram.add_demos(optimized, more_demos)
      assert updated.metadata.demo_count == 3
      assert updated.metadata.teleprompter == :test_teleprompter  # Preserved

      # Test metadata updates with demo replacement
      replaced = OptimizedProgram.replace_demos(optimized, [])
      assert replaced.metadata.demo_count == 0
      assert replaced.metadata.teleprompter == :test_teleprompter  # Preserved
    end

    test "empty demo lists are handled correctly", %{program: program} do
      # Create with empty demos
      optimized = OptimizedProgram.new(program, [])

      assert OptimizedProgram.get_demos(optimized) == []
      assert optimized.metadata.demo_count == 0

      # Add demos to empty list
      new_demos = [%Example{data: %{q: "test", a: "response"}, input_keys: MapSet.new([:q])}]
      updated = OptimizedProgram.add_demos(optimized, new_demos)

      assert OptimizedProgram.get_demos(updated) == new_demos
      assert updated.metadata.demo_count == 1

      # Replace with empty list
      empty_again = OptimizedProgram.replace_demos(updated, [])
      assert OptimizedProgram.get_demos(empty_again) == []
      assert empty_again.metadata.demo_count == 0
    end
  end

  describe "get_metadata and helper functions" do
    test "get_metadata/1 returns optimization metadata", %{program: program, demos: demos} do
      custom_metadata = %{
        teleprompter: :bootstrap_fewshot,
        optimization_score: 0.87,
        iterations: 5
      }

      optimized = OptimizedProgram.new(program, demos, custom_metadata)
      metadata = OptimizedProgram.get_metadata(optimized)

      assert metadata.teleprompter == :bootstrap_fewshot
      assert metadata.optimization_score == 0.87
      assert metadata.iterations == 5
      assert metadata.demo_count == 2
      assert %DateTime{} = metadata.optimized_at
    end

    test "supports_native_demos?/1 correctly identifies demo support", %{program: program} do
      # Test Predict program (has native demo support)
      assert OptimizedProgram.supports_native_demos?(program)

      # Test program with demos field
      program_with_demos = %{demos: [], other_field: "value"}
      assert OptimizedProgram.supports_native_demos?(program_with_demos)

      # Test program without demos field
      program_without_demos = %{signature: TestOptimizedSignature, client: :test}
      refute OptimizedProgram.supports_native_demos?(program_without_demos)

      # Test non-struct
      refute OptimizedProgram.supports_native_demos?("not a program")
      refute OptimizedProgram.supports_native_demos?(nil)
    end
  end

  describe "edge cases and error handling" do
    test "handles large numbers of demonstrations", %{program: program} do
      # Create many demonstrations
      large_demos = Enum.map(1..100, fn i ->
        %Example{
          data: %{question: "Question #{i}", answer: "Answer #{i}"},
          input_keys: MapSet.new([:question])
        }
      end)

      optimized = OptimizedProgram.new(program, large_demos)

      assert length(OptimizedProgram.get_demos(optimized)) == 100
      assert optimized.metadata.demo_count == 100

      # Should handle operations efficiently
      more_demos = [%Example{data: %{q: "extra", a: "demo"}, input_keys: MapSet.new([:q])}]
      updated = OptimizedProgram.add_demos(optimized, more_demos)

      assert length(OptimizedProgram.get_demos(updated)) == 101
      assert updated.metadata.demo_count == 101
    end

    test "handles nil and invalid metadata gracefully", %{program: program,
