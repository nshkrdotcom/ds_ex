defmodule DSPEx.ProgramUtilitiesTest do
  @moduledoc """
  Unit tests for DSPEx.Program utility functions.

  CRITICAL: BEACON telemetry depends on program_name/1, implements_program?/1,
  program_type/1, safe_program_info/1, and has_demos?/1 functions. These utilities
  must work correctly for BEACON's observability and validation features.
  """
  use ExUnit.Case, async: true

  alias DSPEx.{Program, Predict, OptimizedProgram, Example}

  @moduletag :group_2

  # Create test signature
  defmodule TestSignature do
    use DSPEx.Signature, "question -> answer"
  end

  # Create test program for behavior testing
  defmodule TestProgram do
    use DSPEx.Program
    defstruct [:config, demos: []]

    def forward(_program, inputs, _opts) do
      {:ok, %{answer: "Test response for #{inputs[:question]}"}}
    end
  end

  # Create module that doesn't implement Program behavior
  defmodule NotAProgram do
    defstruct [:data]
  end

  setup do
    predict_program = %Predict{signature: TestSignature, client: :test}
    test_program = %TestProgram{config: :test}

    demos = [
      %Example{
        data: %{question: "Test", answer: "Response"},
        input_keys: MapSet.new([:question])
      }
    ]

    optimized_program = OptimizedProgram.new(predict_program, demos)

    %{
      predict_program: predict_program,
      test_program: test_program,
      optimized_program: optimized_program,
      demos: demos
    }
  end

  describe "program_name/1 - BEACON telemetry dependency" do
    test "extracts correct names from program modules", %{
      predict_program: predict,
      test_program: test_prog
    } do
      # Test with Predict program
      assert Program.program_name(predict) == :Predict

      # Test with custom program
      assert Program.program_name(test_prog) == :TestProgram
    end

    test "handles OptimizedProgram wrapper correctly", %{optimized_program: optimized} do
      name = Program.program_name(optimized)

      # Should indicate this is an optimized program
      assert is_atom(name)
      name_str = Atom.to_string(name)
      assert String.contains?(name_str, "OptimizedProgram")
    end

    test "handles edge cases gracefully" do
      # Test with invalid inputs
      assert Program.program_name("not a program") == :unknown
      assert Program.program_name(nil) == :unknown
      assert Program.program_name(%{}) == :unknown
      assert Program.program_name(123) == :unknown
    end

    test "works with deeply nested module names" do
      # Test that it extracts just the last part of the module name
      # Use existing Predict module which has nested name DSPEx.Predict
      nested_program = %Predict{signature: TestSignature, client: :test}
      assert Program.program_name(nested_program) == :Predict
    end

    test "returns consistent results for same program type", %{predict_program: predict} do
      # Multiple calls should return the same result
      name1 = Program.program_name(predict)
      name2 = Program.program_name(predict)
      name3 = Program.program_name(%Predict{signature: TestSignature, client: :other})

      assert name1 == name2
      # Same module, different instance
      assert name1 == name3
    end
  end

  describe "implements_program?/1 - BEACON validation dependency" do
    test "correctly identifies valid program modules" do
      # Modules that implement Program behavior
      assert Program.implements_program?(Predict)
      assert Program.implements_program?(OptimizedProgram)
      assert Program.implements_program?(TestProgram)
    end

    test "correctly rejects non-program modules" do
      # Modules that don't implement Program behavior
      refute Program.implements_program?(NotAProgram)
      refute Program.implements_program?(Example)
      refute Program.implements_program?(String)
      refute Program.implements_program?(Enum)
    end

    test "handles edge cases safely" do
      # Non-existent modules
      refute Program.implements_program?(NonExistentModule)
      refute Program.implements_program?(Some.Fake.Module)

      # Invalid inputs
      refute Program.implements_program?(nil)
      refute Program.implements_program?("not a module")
      refute Program.implements_program?(123)
    end

    test "works with module atoms and module references" do
      # Both should work
      assert Program.implements_program?(DSPEx.Predict)
      assert Program.implements_program?(Predict)
    end
  end

  describe "program_type/1 - BEACON classification" do
    test "classifies program types correctly", %{
      predict_program: predict,
      test_program: test_prog,
      optimized_program: optimized
    } do
      assert Program.program_type(predict) == :predict
      assert Program.program_type(test_prog) == :custom
      assert Program.program_type(optimized) == :optimized
    end

    test "handles unknown program types" do
      unknown_program = %NotAProgram{data: "test"}
      assert Program.program_type(unknown_program) == :custom

      # Invalid inputs
      assert Program.program_type("not a program") == :custom
      assert Program.program_type(nil) == :custom
    end
  end

  describe "safe_program_info/1 - BEACON telemetry extraction" do
    test "extracts safe information from Predict programs", %{predict_program: predict} do
      info = Program.safe_program_info(predict)

      expected_keys = [
        :demo_count,
        :has_demos,
        :name,
        :signature,
        :supports_native_demos,
        :supports_native_instruction,
        :type
      ]

      assert Map.keys(info) |> Enum.sort() == expected_keys

      assert info.type == :predict
      assert info.name == "Predict"
      assert info.signature == TestSignature
      assert info.has_demos == false
      assert info.demo_count == 0
    end

    test "extracts safe information from programs with demos", %{test_program: test_prog} do
      # Add demos to test program
      program_with_demos = %{
        test_prog
        | demos: [
            %Example{data: %{q: "test", a: "test"}, input_keys: MapSet.new([:q])}
          ]
      }

      info = Program.safe_program_info(program_with_demos)

      assert info.type == :custom
      assert info.name == "TestProgram"
      assert info.signature == nil
      assert info.has_demos == true
      assert info.demo_count == 1
    end

    test "extracts safe information from OptimizedProgram", %{optimized_program: optimized} do
      info = Program.safe_program_info(optimized)

      assert info.type == :optimized
      assert info.name == "OptimizedProgram"
      assert info.signature == TestSignature
      assert info.has_demos == true
      assert info.demo_count == 1
    end

    test "excludes sensitive information" do
      # Create program with potentially sensitive data
      sensitive_program = %Predict{
        signature: TestSignature,
        client: %{
          api_key: "secret-key-123",
          config: %{password: "secret"}
        }
      }

      info = Program.safe_program_info(sensitive_program)

      # Should only contain safe fields
      expected_keys = [
        :demo_count,
        :has_demos,
        :name,
        :signature,
        :supports_native_demos,
        :supports_native_instruction,
        :type
      ]

      assert Map.keys(info) |> Enum.sort() == expected_keys

      # Should not contain sensitive data
      refute Map.has_key?(info, :client)
      refute Map.has_key?(info, :api_key)
      refute Map.has_key?(info, :config)
    end

    test "handles invalid programs gracefully" do
      invalid_program = %NotAProgram{data: "test"}
      info = Program.safe_program_info(invalid_program)

      # Should extract what it can
      assert info.type == :custom
      assert info.name == "NotAProgram"
      assert info.signature == nil
      assert info.has_demos == false
      assert info.demo_count == 0
    end
  end

  describe "has_demos?/1 - BEACON demo detection" do
    test "detects demos in programs with demos field", %{test_program: test_prog} do
      # Program without demos
      refute Program.has_demos?(test_prog)

      # Program with empty demos
      program_empty_demos = %{test_prog | demos: []}
      refute Program.has_demos?(program_empty_demos)

      # Program with demos
      program_with_demos = %{
        test_prog
        | demos: [
            %Example{data: %{q: "test", a: "test"}, input_keys: MapSet.new([:q])}
          ]
      }

      assert Program.has_demos?(program_with_demos)
    end

    test "detects demos in OptimizedProgram", %{optimized_program: optimized} do
      assert Program.has_demos?(optimized)

      # Test OptimizedProgram without demos
      empty_optimized =
        OptimizedProgram.new(
          %Predict{signature: TestSignature, client: :test},
          []
        )

      refute Program.has_demos?(empty_optimized)
    end

    test "handles programs without demo support" do
      program_no_demos = %NotAProgram{data: "test"}
      refute Program.has_demos?(program_no_demos)

      # Programs with demos field but wrong type
      program_invalid_demos = %{demos: "not a list"}
      refute Program.has_demos?(program_invalid_demos)
    end

    test "handles edge cases" do
      # Nil program
      refute Program.has_demos?(nil)

      # Non-struct
      refute Program.has_demos?("not a program")

      # Empty map
      refute Program.has_demos?(%{})
    end
  end

  describe "program utilities integration" do
    test "utilities work together for comprehensive program analysis", %{
      predict_program: predict,
      optimized_program: optimized
    } do
      # Analyze predict program
      predict_name = Program.program_name(predict)
      predict_implements = Program.implements_program?(Predict)
      predict_type = Program.program_type(predict)
      predict_info = Program.safe_program_info(predict)
      predict_has_demos = Program.has_demos?(predict)

      assert predict_name == :Predict
      assert predict_implements == true
      assert predict_type == :predict
      assert predict_info.type == :predict
      assert predict_has_demos == false

      # Analyze optimized program
      optimized_name = Program.program_name(optimized)
      optimized_implements = Program.implements_program?(OptimizedProgram)
      optimized_type = Program.program_type(optimized)
      optimized_info = Program.safe_program_info(optimized)
      optimized_has_demos = Program.has_demos?(optimized)

      assert is_atom(optimized_name)
      assert optimized_implements == true
      assert optimized_type == :optimized
      assert optimized_info.type == :optimized
      assert optimized_has_demos == true
    end

    test "utilities are safe to call on any input" do
      invalid_inputs = [nil, "string", 123, %{}, [], :atom]

      Enum.each(invalid_inputs, fn input ->
        # None of these should crash
        name = Program.program_name(input)
        implements = Program.implements_program?(input)
        has_demos = Program.has_demos?(input)

        assert is_atom(name)
        assert is_boolean(implements)
        assert is_boolean(has_demos)

        # program_type and safe_program_info work with any input
        type = Program.program_type(input)
        assert is_atom(type)

        # safe_program_info might not work with all inputs
        case input do
          input when is_struct(input) ->
            info = Program.safe_program_info(input)
            assert is_map(info)

          _ ->
            # Skip non-structs for safe_program_info
            :ok
        end
      end)
    end
  end

  describe "performance characteristics" do
    @tag :todo_optimize
    test "program_name/1 is efficient for repeated calls" do
      program = %Predict{signature: TestSignature, client: :test}

      # Warm up
      Program.program_name(program)

      # Time multiple calls
      {time, _results} =
        :timer.tc(fn ->
          Enum.map(1..1000, fn _i ->
            Program.program_name(program)
          end)
        end)

      # Should be very fast (< 1ms total for 1000 calls)
      # microseconds
      assert time < 1000
    end

    @tag :todo_optimize
    test "implements_program?/1 handles module loading efficiently" do
      # Should not be too slow even for non-existent modules
      {time, results} =
        :timer.tc(fn ->
          Enum.map(1..100, fn i ->
            Program.implements_program?(:"NonExistent#{i}")
          end)
        end)

      # All should be false
      assert Enum.all?(results, &(&1 == false))

      # Should complete reasonably quickly
      # 350ms for 100 non-existent modules (increased tolerance for CI/WSL environment)
      assert time < 350_000
    end

    @tag :todo_optimize
    test "safe_program_info/1 is efficient for complex programs" do
      # Create a program with complex nested data
      complex_program = %Predict{
        signature: TestSignature,
        client: %{
          config: %{
            nested: %{
              data: Enum.map(1..100, fn i -> {i, "value#{i}"} end)
            }
          }
        }
      }

      # Should extract info quickly despite complex structure
      {time, info} =
        :timer.tc(fn ->
          Program.safe_program_info(complex_program)
        end)

      # Should be fast and not include nested data
      # 1ms
      assert time < 1000
      assert is_map(info)

      expected_keys = [
        :demo_count,
        :has_demos,
        :name,
        :signature,
        :supports_native_demos,
        :supports_native_instruction,
        :type
      ]

      assert Map.keys(info) |> Enum.sort() == expected_keys
    end
  end

  describe "BEACON-specific requirements validation" do
    test "all BEACON-required functions exist and work" do
      # BEACON requires these exact functions to exist
      assert function_exported?(Program, :program_name, 1)
      assert function_exported?(Program, :implements_program?, 1)
      assert function_exported?(Program, :program_type, 1)
      assert function_exported?(Program, :safe_program_info, 1)
      assert function_exported?(Program, :has_demos?, 1)

      # Test with realistic BEACON usage
      student = %Predict{signature: TestSignature, client: :gemini}
      teacher = %Predict{signature: TestSignature, client: :openai}

      # BEACON will call these during optimization
      student_name = Program.program_name(student)
      teacher_name = Program.program_name(teacher)

      assert student_name == :Predict
      assert teacher_name == :Predict

      assert Program.implements_program?(Predict)

      student_info = Program.safe_program_info(student)
      teacher_info = Program.safe_program_info(teacher)

      assert student_info.type == :predict
      assert teacher_info.type == :predict
    end

    test "utilities work correctly with OptimizedProgram (BEACON output)" do
      # BEACON creates OptimizedProgram instances
      base_program = %Predict{signature: TestSignature, client: :test}
      demos = [%Example{data: %{q: "test", a: "test"}, input_keys: MapSet.new([:q])}]

      optimized =
        OptimizedProgram.new(base_program, demos, %{
          teleprompter: :beacon,
          optimization_score: 0.85
        })

      # All utilities should work with BEACON's output
      assert is_atom(Program.program_name(optimized))
      assert Program.implements_program?(OptimizedProgram)
      assert Program.has_demos?(optimized)

      info = Program.safe_program_info(optimized)
      assert info.type == :optimized
      assert info.has_demos == true
    end

    test "telemetry integration readiness" do
      # BEACON uses these functions in telemetry events
      programs = [
        %Predict{signature: TestSignature, client: :test},
        %TestProgram{config: :test}
      ]

      # Should be able to extract telemetry data from any program
      Enum.each(programs, fn program ->
        # These are the calls BEACON makes for telemetry
        name = Program.program_name(program)
        type = Program.program_type(program)
        info = Program.safe_program_info(program)

        # All should return serializable data
        assert is_atom(name)
        assert is_atom(type)
        assert is_map(info)

        # Info should only contain safe, serializable data
        Enum.each(info, fn {key, value} ->
          assert is_atom(key)
          # Values should be serializable
          assert is_atom(value) or is_binary(value) or is_boolean(value) or
                   is_number(value) or is_nil(value)
        end)
      end)
    end
  end
end
