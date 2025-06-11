# File: test/unit/program_utilities_test.exs
defmodule DSPEx.ProgramUtilitiesTest do
  use ExUnit.Case, async: true

  alias DSPEx.{Program, Predict, OptimizedProgram, Example}

  doctest DSPEx.Program

  setup do
    # Create test signature
    defmodule TestUtilitiesSignature do
      use DSPEx.Signature, "question -> answer"
    end

    %{signature: TestUtilitiesSignature}
  end

  describe "program name extraction" do
    test "program_name/1 extracts correct names from Predict programs", %{signature: signature} do
      program = %Predict{signature: signature, client: :test}

      assert Program.program_name(program) == :Predict
    end

    test "program_name/1 extracts correct names from OptimizedProgram", %{signature: signature} do
      base_program = %Predict{signature: signature, client: :test}
      optimized = OptimizedProgram.new(base_program, [])

      result = Program.program_name(optimized)

      # Should indicate it's an optimized version
      assert is_atom(result)
      assert Atom.to_string(result) |> String.contains?("Optimized")
    end

    test "program_name/1 handles custom program modules" do
      # Create a mock custom program
      defmodule CustomTestProgram do
        defstruct [:signature, :client]
      end

      custom_program = %CustomTestProgram{signature: TestUtilitiesSignature, client: :test}

      assert Program.program_name(custom_program) == :CustomTestProgram
    end

    test "program_name/1 returns :unknown for invalid inputs" do
      assert Program.program_name("not a program") == :unknown
      assert Program.program_name(nil) == :unknown
      assert Program.program_name(123) == :unknown
      assert Program.program_name(%{not: "a struct"}) == :unknown
    end

    test "program_name/1 handles modules with complex names" do
      # Create a module with nested namespace
      defmodule MyApp.Advanced.ComplexProgram do
        defstruct [:field]
      end

      complex_program = %MyApp.Advanced.ComplexProgram{field: "test"}

      assert Program.program_name(complex_program) == :ComplexProgram
    end

    test "program_name/1 handles OptimizedProgram with various wrapped programs", %{signature: signature} do
      # Test with different wrapped program types
      predict_program = %Predict{signature: signature, client: :openai}
      optimized_predict = OptimizedProgram.new(predict_program, [])

      result = Program.program_name(optimized_predict)
      assert is_atom(result)
      optimized_name = Atom.to_string(result)
      assert String.contains?(optimized_name, "Optimized")

      # Test with custom wrapped program
      defmodule CustomWrappedProgram do
        defstruct [:signature]
      end

      custom_program = %CustomWrappedProgram{signature: signature}
      optimized_custom = OptimizedProgram.new(custom_program, [])

      result2 = Program.program_name(optimized_custom)
      assert is_atom(result2)
      assert String.contains?(Atom.to_string(result2), "Optimized")
    end
  end

  describe "program behavior checking" do
    test "implements_program?/1 correctly identifies DSPEx.Program implementations" do
      # Test with known Program implementations
      assert Program.implements_program?(Predict)
      assert Program.implements_program?(OptimizedProgram)

      # Test with modules that don't implement Program
      refute Program.implements_program?(String)
      refute Program.implements_program?(Example)
      refute Program.implements_program?(Enum)
    end

    test "implements_program?/1 returns false for non-program modules" do
      refute Program.implements_program?(GenServer)
      refute Program.implements_program?(Agent)
      refute Program.implements_program?(Task)
      refute Program.implements_program?(Process)
    end

    test "implements_program?/1 handles module loading errors gracefully" do
      # Test with non-existent module
      refute Program.implements_program?(NonExistentModule)

      # Test with invalid module names
      refute Program.implements_program?("StringModuleName")
      refute Program.implements_program?(123)
      refute Program.implements_program?(nil)
    end

    test "implements_program?/1 handles modules without proper attributes" do
      # Create a module without behavior attributes
      defmodule ModuleWithoutBehavior do
        def some_function, do: :ok
      end

      refute Program.implements_program?(ModuleWithoutBehavior)
    end

    test "implements_program?/1 handles complex behavior scenarios" do
      # Test with module that implements multiple behaviors
      defmodule MultipleehaviorModule do
        @behaviour GenServer
        @behaviour DSPEx.Program

        def init(_), do: {:ok, %{}}
        def forward(_program, _inputs, _opts \\ []), do: {:ok, %{}}
      end

      assert Program.implements_program?(MultipleBehaviorModule)
    end
  end

  describe "safe program info extraction" do
    test "safe_program_info/1 extracts metadata without sensitive information", %{signature: signature} do
      program = %Predict{signature: signature, client: :test}

      info = Program.safe_program_info(program)

      assert %{
        type: :predict,
        name: :Predict,
        module: Predict,
        has_demos: false
      } = info

      # Should not contain sensitive fields like API keys
      refute Map.has_key?(info, :api_key)
      refute Map.has_key?(info, :client_config)
    end

    test "safe_program_info/1 handles all program types", %{signature: signature} do
      # Test with Predict
      predict_program = %Predict{signature: signature, client: :openai}
      predict_info = Program.safe_program_info(predict_program)

      assert predict_info.type == :predict
      assert predict_info.name == :Predict
      assert predict_info.has_demos == false

      # Test with OptimizedProgram
      optimized = OptimizedProgram.new(predict_program, [])
      optimized_info = Program.safe_program_info(optimized)

      assert optimized_info.type == :optimized
      assert is_atom(optimized_info.name)
      assert optimized_info.has_demos == false  # No demos in this case

      # Test with OptimizedProgram that has demos
      demo = %Example{data: %{q: "test", a: "response"}, input_keys: MapSet.new([:q])}
      optimized_with_demos = OptimizedProgram.new(predict_program, [demo])
      optimized_demos_info = Program.safe_program_info(optimized_with_demos)

      assert optimized_demos_info.has_demos == true
    end

    test "safe_program_info/1 handles programs with demo fields", %{signature: signature} do
      # Test with program that has demos field
      program_with_demos = %Predict{
        signature: signature,
        client: :test,
        demos: [%Example{data: %{test: "demo"}, input_keys: MapSet.new()}]
      }

      info = Program.safe_program_info(program_with_demos)

      assert info.has_demos == true
      assert info.type == :predict
      assert info.name == :Predict
    end

    test "safe_program_info/1 filters out sensitive configuration" do
      # Create program with potentially sensitive data
      program_with_config = %Predict{
        signature: TestUtilitiesSignature,
        client: :test,
        # These fields shouldn't appear in safe info
        adapter: "sensitive_adapter_config"
      }

      info = Program.safe_program_info(program_with_config)

      # Should only include safe fields
      expected_keys = [:type, :name, :module, :has_demos]
      actual_keys = Map.keys(info)

      assert Enum.all?(expected_keys, &(&1 in actual_keys))

      # Should not include potentially sensitive fields
      refute Map.has_key?(info, :adapter)
      refute Map.has_key?(info, :client)
    end
  end

  describe "has_demos?/1 functionality" do
    test "has_demos?/1 correctly identifies programs with demonstrations", %{signature: signature} do
      # Program without demos
      program_no_demos = %Predict{signature: signature, client: :test}
      refute Program.has_demos?(program_no_demos)

      # Program with empty demos list
      program_empty_demos = %Predict{signature: signature, client: :test, demos: []}
      refute Program.has_demos?(program_empty_demos)

      # Program with demos
      demo = %Example{data: %{q: "test", a: "response"}, input_keys: MapSet.new([:q])}
      program_with_demos = %Predict{signature: signature, client: :test, demos: [demo]}
      assert Program.has_demos?(program_with_demos)
    end

    test "has_demos?/1 handles OptimizedProgram correctly", %{signature: signature} do
      base_program = %Predict{signature: signature, client: :test}

      # OptimizedProgram without demos
      optimized_no_demos = OptimizedProgram.new(base_program, [])
      refute Program.has_demos?(optimized_no_demos)

      # OptimizedProgram with demos
      demo = %Example{data: %{q: "test", a: "response"}, input_keys: MapSet.new([:q])}
      optimized_with_demos = OptimizedProgram.new(base_program, [demo])
      assert Program.has_demos?(optimized_with_demos)
    end

    test "has_demos?/1 handles edge cases" do
      # Test with programs that have demos field but it's not a list
      program_invalid_demos = %{demos: "not a list"}
      refute Program.has_demos?(program_invalid_demos)

      # Test with programs that have demos field as nil
      program_nil_demos = %{demos: nil}
      refute Program.has_demos?(program_nil_demos)

      # Test with non-program structures
      refute Program.has_demos?("not a program")
      refute Program.has_demos?(nil)
      refute Program.has_demos?(%{})
    end

    test "has_demos?/1 handles various demo field types" do
      # Test with different demo structures
      demo1 = %Example{data: %{test: "demo1"}, input_keys: MapSet.new()}
      demo2 = %{not: "a proper demo"}  # Invalid demo type

      # Program with valid demos
      program_valid = %{demos: [demo1]}
      assert Program.has_demos?(program_valid)

      # Program with mixed demo types (should still return true for non-empty list)
      program_mixed = %{demos: [demo1, demo2]}
      assert Program.has_demos?(program_mixed)

      # Program with only invalid demos (should still return true for non-empty list)
      program_invalid_demos = %{demos: [demo2]}
      assert Program.has_demos?(program_invalid_demos)
    end
  end

  describe "program type classification" do
    test "program_type/1 identifies different program types correctly", %{signature: signature} do
      # Test Predict program
      predict_program = %Predict{signature: signature, client: :test}
      assert Program.program_type(predict_program) == :predict

      # Test OptimizedProgram
      optimized = OptimizedProgram.new(predict_program, [])
      assert Program.program_type(optimized) == :optimized

      # Test custom program
      defmodule CustomTypeProgram do
        defstruct [:field]
      end

      custom_program = %CustomTypeProgram{field: "test"}
      assert Program.program_type(custom_program) == :customtypeprogram
    end

    test "program_type/1 handles invalid inputs" do
      assert Program.program_type("not a program") == :unknown
      assert Program.program_type(nil) == :unknown
      assert Program.program_type(123) == :unknown
      assert Program.program_type(%{not: "a struct"}) == :unknown
    end

    test "program_type/1 handles complex module names" do
      defmodule MyApp.Complex.ProgramType do
        defstruct [:field]
      end

      complex_program = %MyApp.Complex.ProgramType{field: "test"}
      assert Program.program_type(complex_program) == :programtype
    end
  end

  describe "integration with telemetry and logging" do
    test "program utilities support telemetry metadata extraction", %{signature: signature} do
      program = %Predict{signature: signature, client: :openai}

      # Test that all utility functions provide data suitable for telemetry
      name = Program.program_name(program)
      type = Program.program_type(program)
      has_demos = Program.has_demos?(program)
      safe_info = Program.safe_program_info(program)

      # All should return telemetry-safe values
      assert is_atom(name)
      assert is_atom(type)
      assert is_boolean(has_demos)
      assert is_map(safe_info)

      # Safe info should be JSON-serializable (no functions, PIDs, etc.)
      json_result = try do
        Jason.encode!(safe_info)
        :ok
      rescue
        _ -> :error
      end

      assert json_result == :ok
    end

    test "utilities handle concurrent access safely", %{signature: signature} do
      program = %Predict{signature: signature, client: :test}

      # Test concurrent access to utility functions
      tasks = Task.async_stream(1..100, fn _i ->
        %{
          name: Program.program_name(program),
          type: Program.program_type(program),
          has_demos: Program.has_demos?(program),
          implements_behavior: Program.implements_program?(Predict)
        }
      end, max_concurrency: 20)
      |> Enum.to_list()

      # All should complete successfully
      assert length(tasks) == 100
      assert Enum.all?(tasks, fn {:ok, result} ->
        result.name == :Predict and
        result.type == :predict and
        result.has_demos == false and
        result.implements_behavior == true
      end)
    end

    test "utilities provide consistent results across calls", %{signature: signature} do
      program = %Predict{signature: signature, client: :test}

      # Call each utility multiple times
      names = Enum.map(1..10, fn _i -> Program.program_name(program) end)
      types = Enum.map(1..10, fn _i -> Program.program_type(program) end)
      demo_checks = Enum.map(1..10, fn _i -> Program.has_demos?(program) end)

      # Results should be consistent
      assert Enum.uniq(names) == [:Predict]
      assert Enum.uniq(types) == [:predict]
      assert Enum.uniq(demo_checks) == [false]
    end
  end

  describe "error handling and edge cases" do
    test "utilities handle malformed program structures gracefully" do
      # Test with incomplete program structure
      incomplete_program = %{signature: TestUtilitiesSignature}  # Missing required fields

      # Should not crash, but may return :unknown or default values
      name = Program.program_name(incomplete_program)
      type = Program.program_type(incomplete_program)
      has_demos = Program.has_demos?(incomplete_program)

      # All should complete without crashing
      assert is_atom(name) or name == :unknown
      assert is_atom(type) or type == :unknown
      assert is_boolean(has_demos)
    end

    test "utilities handle very large program structures" do
      # Create program with large metadata
      large_metadata = Enum.reduce(1..1000, %{}, fn i, acc ->
        Map.put(acc, :"field_#{i}", "value_#{i}")
      end)

      large_program = Map.merge(%Predict{signature: TestUtilitiesSignature, client: :test}, large_metadata)

      # Utilities should handle large structures efficiently
      {time_us, name} = :timer.tc(fn -> Program.program_name(large_program) end)
      assert name == :Predict
      assert time_us < 10_000  # Should complete quickly (less than 10ms)

      {time_us2, safe_info} = :timer.tc(fn -> Program.safe_program_info(large_program) end)
      assert is_map(safe_info)
      assert time_us2 < 50_000  # Should complete reasonably quickly (less than 50ms)
    end
  end
end
