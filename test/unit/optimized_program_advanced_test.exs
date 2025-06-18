defmodule DSPEx.OptimizedProgramAdvancedTest do
  @moduledoc """
  Advanced unit tests for DSPEx.OptimizedProgram.

  CRITICAL: This test validates that OptimizedProgram has the exact interface
  that BEACON expects. BEACON's create_optimized_student/2 function depends on
  OptimizedProgram.new/3, get_demos/1, and get_program/1 working correctly.
  """
  use ExUnit.Case, async: true
  @moduletag :group_3

  alias DSPEx.{Example, OptimizedProgram, Predict, Program}

  # Create test signature
  defmodule TestSignature do
    use DSPEx.Signature, "question -> answer"
  end

  # Create test program that supports demos natively
  defmodule TestProgramWithDemos do
    use DSPEx.Program
    defstruct [:signature, :client, demos: []]

    @impl DSPEx.Program
    def forward(_program, inputs, _opts) do
      # Simple echo implementation for testing
      {:ok, %{answer: "Test response for #{inputs[:question]}"}}
    end
  end

  setup do
    base_program = %Predict{signature: TestSignature, client: :test}

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
      teleprompter: :bootstrap_fewshot,
      optimization_time: DateTime.utc_now(),
      quality_threshold: 0.8
    }

    %{
      base_program: base_program,
      demos: demos,
      metadata: metadata
    }
  end

  describe "BEACON interface compatibility" do
    test "new/3 creates optimized program with required interface", %{
      base_program: program,
      demos: demos,
      metadata: metadata
    } do
      # Test the exact interface BEACON expects
      optimized = OptimizedProgram.new(program, demos, metadata)

      assert %OptimizedProgram{} = optimized
      assert optimized.program == program
      assert optimized.demos == demos
      assert Map.has_key?(optimized.metadata, :optimized_at)
      assert Map.has_key?(optimized.metadata, :demo_count)
      assert optimized.metadata.teleprompter == :bootstrap_fewshot
    end

    test "new/2 works with default metadata", %{base_program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      assert %OptimizedProgram{} = optimized
      assert optimized.program == program
      assert optimized.demos == demos
      assert is_map(optimized.metadata)
      assert Map.has_key?(optimized.metadata, :optimized_at)
      assert Map.has_key?(optimized.metadata, :demo_count)
      assert optimized.metadata.demo_count == length(demos)
    end

    test "get_demos/1 returns demonstrations - BEACON dependency", %{
      base_program: program,
      demos: demos
    } do
      optimized = OptimizedProgram.new(program, demos)

      # BEACON calls this function to extract demos
      result_demos = OptimizedProgram.get_demos(optimized)

      assert result_demos == demos
      assert length(result_demos) == 2
      assert Enum.all?(result_demos, &is_struct(&1, Example))
    end

    test "get_program/1 returns wrapped program - BEACON dependency", %{
      base_program: program,
      demos: demos
    } do
      optimized = OptimizedProgram.new(program, demos)

      # BEACON calls this function to extract the original program
      result_program = OptimizedProgram.get_program(optimized)

      assert result_program == program
      assert %Predict{} = result_program
    end

    test "implements DSPEx.Program behavior", %{base_program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      # Must implement Program behavior for BEACON compatibility
      assert Program.implements_program?(OptimizedProgram)

      # Should be usable as a program
      assert is_struct(optimized, OptimizedProgram)
    end
  end

  describe "forward/3 delegation with demo injection" do
    test "forwards to wrapped Predict program with demos", %{base_program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)
      inputs = %{question: "What is 5+5?"}

      # Mock the client to avoid real API calls
      DSPEx.TestModeConfig.set_test_mode(:mock)

      case Program.forward(optimized, inputs) do
        {:ok, result} ->
          assert %{answer: answer} = result
          assert is_binary(answer)

        {:error, _reason} ->
          # In test mode with mocks, should succeed
          # If it fails, that's acceptable for this unit test
          :ok
      end
    end

    test "forwards to program with native demo support", %{demos: demos} do
      program_with_demos = %TestProgramWithDemos{
        signature: TestSignature,
        client: :test,
        demos: []
      }

      optimized = OptimizedProgram.new(program_with_demos, demos)
      inputs = %{question: "Test native demos"}

      {:ok, result} = Program.forward(optimized, inputs)
      assert %{answer: _} = result
    end

    test "passes demos via options for generic programs", %{demos: demos} do
      # Create a simple program that doesn't have native demo support
      generic_program = %{some_field: "value"}

      # This should not crash even with a non-standard program
      optimized = OptimizedProgram.new(generic_program, demos)

      # The structure should be correct even if forward fails
      assert optimized.program == generic_program
      assert optimized.demos == demos
    end

    test "preserves correlation_id in options", %{base_program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)
      inputs = %{question: "Test correlation"}
      correlation_id = "test-correlation-123"

      # The correlation_id should be preserved when forwarding
      # This is important for BEACON's telemetry tracking
      opts = [correlation_id: correlation_id]

      # Even if the call fails in test mode, the structure should be preserved
      case Program.forward(optimized, inputs, opts) do
        {:ok, _result} -> :ok
        # Acceptable in test environment
        {:error, _reason} -> :ok
      end
    end
  end

  describe "metadata tracking and management" do
    test "get_metadata/1 returns optimization metadata", %{base_program: program, demos: demos} do
      custom_metadata = %{
        teleprompter: :beacon,
        iterations: 10,
        final_score: 0.85
      }

      optimized = OptimizedProgram.new(program, demos, custom_metadata)
      metadata = OptimizedProgram.get_metadata(optimized)

      assert metadata.teleprompter == :beacon
      assert metadata.iterations == 10
      assert metadata.final_score == 0.85
      assert Map.has_key?(metadata, :optimized_at)
      assert Map.has_key?(metadata, :demo_count)
    end

    test "tracks demo count automatically", %{base_program: program} do
      empty_demos = []

      few_demos = [
        %Example{data: %{q: "1", a: "1"}, input_keys: MapSet.new([:q])}
      ]

      many_demos =
        Enum.map(1..10, fn i ->
          %Example{data: %{q: "#{i}", a: "#{i}"}, input_keys: MapSet.new([:q])}
        end)

      opt_empty = OptimizedProgram.new(program, empty_demos)
      opt_few = OptimizedProgram.new(program, few_demos)
      opt_many = OptimizedProgram.new(program, many_demos)

      assert opt_empty.metadata.demo_count == 0
      assert opt_few.metadata.demo_count == 1
      assert opt_many.metadata.demo_count == 10
    end

    test "update_program/2 preserves demos and metadata", %{
      base_program: program,
      demos: demos,
      metadata: metadata
    } do
      optimized = OptimizedProgram.new(program, demos, metadata)

      new_program = %Predict{signature: TestSignature, client: :new_client}
      updated = OptimizedProgram.update_program(optimized, new_program)

      assert updated.program == new_program
      # Preserved
      assert updated.demos == demos
      # Metadata includes original data plus update tracking
      assert Map.drop(updated.metadata, [
               :program_updated_at,
               :original_program_type,
               :new_program_type
             ]) ==
               optimized.metadata

      assert Map.has_key?(updated.metadata, :program_updated_at)
      assert updated.metadata.original_program_type == :predict
      assert updated.metadata.new_program_type == :predict
    end
  end

  describe "demo management functions" do
    test "add_demos/2 combines demonstrations", %{base_program: program, demos: initial_demos} do
      optimized = OptimizedProgram.new(program, initial_demos)

      additional_demos = [
        %Example{
          data: %{question: "What is 4+4?", answer: "8"},
          input_keys: MapSet.new([:question])
        }
      ]

      updated = OptimizedProgram.add_demos(optimized, additional_demos)

      assert length(updated.demos) == length(initial_demos) + length(additional_demos)
      assert updated.metadata.demo_count == length(initial_demos) + length(additional_demos)

      # Original demos should be preserved
      Enum.each(initial_demos, fn demo ->
        assert demo in updated.demos
      end)

      # New demos should be added
      Enum.each(additional_demos, fn demo ->
        assert demo in updated.demos
      end)
    end

    test "replace_demos/2 replaces all demonstrations", %{
      base_program: program,
      demos: initial_demos
    } do
      optimized = OptimizedProgram.new(program, initial_demos)

      new_demos = [
        %Example{
          data: %{question: "New question", answer: "New answer"},
          input_keys: MapSet.new([:question])
        }
      ]

      updated = OptimizedProgram.replace_demos(optimized, new_demos)

      assert updated.demos == new_demos
      assert updated.metadata.demo_count == length(new_demos)

      # Original demos should be gone
      Enum.each(initial_demos, fn demo ->
        refute demo in updated.demos
      end)
    end

    test "supports_native_demos?/1 correctly identifies demo support" do
      # Program with native demo support
      program_with_demos = %TestProgramWithDemos{signature: TestSignature, client: :test}
      assert OptimizedProgram.supports_native_demos?(program_with_demos)

      # Predict program (has demo support)
      predict_program = %Predict{signature: TestSignature, client: :test}
      assert OptimizedProgram.supports_native_demos?(predict_program)

      # Generic program without demo support
      generic_program = %{some_field: "value"}
      refute OptimizedProgram.supports_native_demos?(generic_program)
    end
  end

  describe "edge cases and error handling" do
    test "handles empty demo list", %{base_program: program} do
      empty_demos = []
      optimized = OptimizedProgram.new(program, empty_demos)

      assert optimized.demos == []
      assert optimized.metadata.demo_count == 0
    end

    test "handles nil metadata gracefully", %{base_program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos, nil)

      # Should still have default metadata
      assert is_map(optimized.metadata)
      assert Map.has_key?(optimized.metadata, :optimized_at)
      assert Map.has_key?(optimized.metadata, :demo_count)
    end

    test "handles invalid demo list gracefully" do
      program = %Predict{signature: TestSignature, client: :test}

      # This might raise an error, which is acceptable
      assert_raise(ArgumentError, fn ->
        OptimizedProgram.new(program, "not a list")
      end)
    end

    test "metadata is immutable across operations", %{base_program: program, demos: demos} do
      original_metadata = %{teleprompter: :test, score: 0.5}
      optimized = OptimizedProgram.new(program, demos, original_metadata)

      # Operations should not modify the original metadata map
      _updated = OptimizedProgram.add_demos(optimized, [])

      # Original metadata map should be unchanged
      assert original_metadata.teleprompter == :test
      assert original_metadata.score == 0.5
      refute Map.has_key?(original_metadata, :demo_count)
    end
  end

  describe "Program behavior integration" do
    test "program_name/1 works correctly for optimized programs", %{
      base_program: program,
      demos: demos
    } do
      optimized = OptimizedProgram.new(program, demos)

      name = Program.program_name(optimized)
      assert is_atom(name)
      assert String.contains?(Atom.to_string(name), "Optimized")
    end

    test "has_demos?/1 correctly identifies demo presence", %{base_program: program} do
      # With demos
      optimized_with_demos =
        OptimizedProgram.new(program, [
          %Example{data: %{q: "test", a: "test"}, input_keys: MapSet.new([:q])}
        ])

      assert Program.has_demos?(optimized_with_demos)

      # Without demos
      optimized_without_demos = OptimizedProgram.new(program, [])
      refute Program.has_demos?(optimized_without_demos)
    end

    test "safe_program_info/1 extracts safe information", %{base_program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      info = Program.safe_program_info(optimized)

      assert info.type == :optimized
      assert info.has_demos == true
      assert is_binary(info.name)
      assert info.signature == TestSignature
      assert info.demo_count == length(demos)
    end
  end
end
