defmodule DSPEx.EnhancedSignatureIntegrationTest do
  use ExUnit.Case, async: true

  alias DSPEx.{Example, Signature}

  describe "end-to-end enhanced signature workflows" do
    test "complete enhanced signature lifecycle" do
      # 1. Define enhanced signature
      defmodule TestLifecycleSignature do
        @moduledoc "Process user input with validation"
        use DSPEx.Signature,
            "username:string[min_length=3,max_length=20], email:string[min_length=5] -> welcome:string[max_length=100], user_id:integer[gteq=1]"
      end

      # 2. Verify signature compilation
      assert TestLifecycleSignature.input_fields() == [:username, :email]
      assert TestLifecycleSignature.output_fields() == [:welcome, :user_id]
      assert function_exported?(TestLifecycleSignature, :__enhanced_fields__, 0)

      # 3. Generate Elixact schema
      {:ok, schema_module} = Signature.Elixact.signature_to_schema(TestLifecycleSignature)

      # 4. Validate data through the schema
      valid_input = %{
        username: "alice_doe",
        email: "alice@example.com",
        welcome: "Welcome, Alice!",
        user_id: 123
      }

      {:ok, validated} = schema_module.validate(valid_input)
      assert validated.username == "alice_doe"
      assert validated.user_id == 123

      # 5. Test constraint violations
      invalid_input = %{
        # too short
        username: "al",
        # wrong format
        email: "invalid-email",
        welcome: "Welcome!",
        # below minimum
        user_id: 0
      }

      {:error, error} = schema_module.validate(invalid_input)
      assert %Elixact.Error{} = error
    end

    test "enhanced signatures with DSPEx.Example integration" do
      defmodule TestExampleIntegration do
        use DSPEx.Signature,
            "question:string[min_length=1], difficulty:integer[gteq=1,lteq=5] -> answer:string[max_length=200], confidence:float[gteq=0.0,lteq=1.0]"
      end

      # Create example with enhanced signature validation
      example_data = %{
        question: "What is the capital of France?",
        difficulty: 2,
        answer: "Paris",
        confidence: 0.95
      }

      example = Example.new(example_data, [:question, :difficulty])

      # Validate example inputs using enhanced constraints
      {:ok, _} =
        Signature.Elixact.validate_with_elixact(
          TestExampleIntegration,
          Example.inputs(example),
          field_type: :inputs
        )

      # Validate example outputs using enhanced constraints
      {:ok, _} =
        Signature.Elixact.validate_with_elixact(
          TestExampleIntegration,
          Example.outputs(example),
          field_type: :outputs
        )
    end

    test "JSON schema generation and external validation" do
      defmodule TestJSONExport do
        use DSPEx.Signature,
            "product:string[min_length=1], price:float[gteq=0.01], categories:array(string)[min_items=1,max_items=5] -> recommendation:string, score:integer[gteq=1,lteq=10]"
      end

      # Generate JSON schema
      {:ok, json_schema} = Signature.Elixact.to_json_schema(TestJSONExport)

      # Verify JSON schema structure
      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema, "properties")
      assert Map.has_key?(json_schema, "required")

      # Verify constraints are properly exported
      product_props = json_schema["properties"]["product"]
      assert product_props["minLength"] == 1

      price_props = json_schema["properties"]["price"]
      assert price_props["minimum"] == 0.01

      categories_props = json_schema["properties"]["categories"]
      assert categories_props["minItems"] == 1
      assert categories_props["maxItems"] == 5
    end
  end

  describe "performance characteristics" do
    test "enhanced signature compilation performance" do
      # Measure compilation time for enhanced vs basic signatures
      basic_time =
        :timer.tc(fn ->
          defmodule TestBasicPerf do
            use DSPEx.Signature, "input1, input2, input3 -> output1, output2, output3"
          end
        end)

      enhanced_time =
        :timer.tc(fn ->
          defmodule TestEnhancedPerf do
            use DSPEx.Signature,
                "input1:string[min_length=1], input2:integer[gteq=0], input3:array(string)[max_items=5] -> output1:string[max_length=100], output2:float[gteq=0.0], output3:boolean"
          end
        end)

      # Enhanced compilation should be reasonable (within 10x of basic)
      {basic_microseconds, _} = basic_time
      {enhanced_microseconds, _} = enhanced_time

      assert enhanced_microseconds < basic_microseconds * 10
    end

    test "validation performance under load" do
      defmodule TestValidationPerf do
        use DSPEx.Signature,
            "data:string[min_length=1,max_length=1000], count:integer[gteq=1,lteq=100] -> result:string[max_length=500], status:boolean"
      end

      {:ok, schema} = Signature.Elixact.signature_to_schema(TestValidationPerf)

      # Test data for validation
      test_data = %{
        data: String.duplicate("x", 500),
        count: 50,
        result: "Processed successfully",
        status: true
      }

      # Measure validation performance
      {time_microseconds, _} =
        :timer.tc(fn ->
          # Run 100 validations
          Enum.each(1..100, fn _ ->
            {:ok, _} = schema.validate(test_data)
          end)
        end)

      # Should complete 100 validations in reasonable time (< 100ms)
      assert time_microseconds < 100_000
    end

    test "memory usage for large signatures" do
      # Create a signature with many fields and constraints
      defmodule TestLargeSignature do
        use DSPEx.Signature,
            "field1:string[min_length=1], field2:integer[gteq=0], field3:float[gteq=0.0], field4:boolean, field5:array(string)[max_items=10], field6:string[min_length=1], field7:integer[lteq=1000], field8:string[max_length=10], field9:float[lteq=100.0], field10:array(integer)[min_items=1] -> result1:string[max_length=200], result2:integer[gteq=1], result3:boolean, result4:array(string)[max_items=5], result5:float[gteq=0.0,lteq=1.0]"
      end

      memory_before = :erlang.memory(:total)

      # Generate schema
      {:ok, _schema} = Signature.Elixact.signature_to_schema(TestLargeSignature)

      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before

      # Memory usage should be reasonable (< 10MB for schema generation)
      assert memory_used < 10 * 1024 * 1024
    end
  end

  describe "error handling and edge cases" do
    test "graceful handling of invalid constraint combinations" do
      assert_raise CompileError, ~r/not compatible/, fn ->
        defmodule TestInvalidConstraints do
          use DSPEx.Signature, "text:string[min_items=1] -> result:string"
        end
      end
    end

    test "proper error propagation in Elixact integration" do
      defmodule TestErrorPropagation do
        use DSPEx.Signature, "input:string[min_length=5] -> output:string[max_length=10]"
      end

      {:ok, schema} = Signature.Elixact.signature_to_schema(TestErrorPropagation)

      # Test constraint violation
      {:error, error} = schema.validate(%{input: "x", output: "valid"})
      assert %Elixact.Error{} = error
      assert error.code == :min_length
    end

    test "backward compatibility with basic signatures" do
      defmodule TestBackwardCompat do
        use DSPEx.Signature, "question -> answer"
      end

      # Should work with Elixact even without enhanced features
      {:ok, schema} = Signature.Elixact.signature_to_schema(TestBackwardCompat)
      {:ok, _} = schema.validate(%{question: "test", answer: "response"})
    end

    test "handling of complex nested constraints" do
      defmodule TestNestedConstraints do
        use DSPEx.Signature,
            "config:array(string)[min_items=1,max_items=5], metadata:string[min_length=1] -> processed:array(string)[max_items=10], valid:boolean"
      end

      {:ok, schema} = Signature.Elixact.signature_to_schema(TestNestedConstraints)

      # Valid data
      valid_data = %{
        config: ["option1", "option2"],
        metadata: "ValidMetadata",
        processed: ["result1", "result2"],
        valid: true
      }

      {:ok, _} = schema.validate(valid_data)

      # Invalid data - array too large
      invalid_data = %{
        # exceeds max_items
        config: ["a", "b", "c", "d", "e", "f"],
        metadata: "ValidMetadata",
        processed: ["result1"],
        valid: true
      }

      {:error, _} = schema.validate(invalid_data)
    end

    test "proper handling of default values and optional fields" do
      defmodule TestDefaults do
        use DSPEx.Signature,
            "required:string[min_length=1], optional:string[default='test'] -> result:string"
      end

      {:ok, schema} = Signature.Elixact.signature_to_schema(TestDefaults)

      # Should work with only required field
      {:ok, validated} = schema.validate(%{required: "value", result: "output"})
      assert validated.required == "value"

      # Test with optional field provided
      {:ok, validated} =
        schema.validate(%{required: "value", optional: "custom", result: "output"})

      assert validated.optional == "custom"
    end
  end

  describe "integration stress testing" do
    test "rapid schema generation and validation" do
      # Define multiple test signatures
      defmodule TestRapidSchema1 do
        use DSPEx.Signature, "input1:string[min_length=1] -> output1:string[max_length=10]"
      end

      defmodule TestRapidSchema2 do
        use DSPEx.Signature, "input2:string[min_length=2] -> output2:string[max_length=20]"
      end

      defmodule TestRapidSchema3 do
        use DSPEx.Signature, "input3:string[min_length=3] -> output3:string[max_length=30]"
      end

      # Test generating schemas rapidly
      schemas =
        [TestRapidSchema1, TestRapidSchema2, TestRapidSchema3]
        |> Enum.map(fn module_name ->
          {:ok, schema} = Signature.Elixact.signature_to_schema(module_name)
          schema
        end)

      assert length(schemas) == 3

      # Test validation on all schemas
      Enum.each(schemas, fn schema ->
        # This will fail validation but should not crash
        {:error, _} = schema.validate(%{})
      end)
    end

    test "concurrent validation operations" do
      defmodule TestConcurrentValidation do
        use DSPEx.Signature,
            "data:string[min_length=1], count:integer[gteq=1] -> status:string[max_length=50], result:boolean"
      end

      {:ok, schema} = Signature.Elixact.signature_to_schema(TestConcurrentValidation)

      # Run concurrent validations
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            test_data = %{
              data: "test_data_#{i}",
              count: i,
              status: "processed_#{i}",
              result: rem(i, 2) == 0
            }

            schema.validate(test_data)
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "field type edge cases and boundary conditions" do
      defmodule TestEdgeCases do
        use DSPEx.Signature,
            "min_str:string[min_length=0], max_str:string[max_length=1000], zero_int:integer[gteq=0,lteq=0], float_range:float[gt=-1.0,lt=1.0] -> result:string"
      end

      {:ok, schema} = Signature.Elixact.signature_to_schema(TestEdgeCases)

      # Test boundary conditions
      boundary_data = %{
        # minimum length
        min_str: "",
        # maximum length
        max_str: String.duplicate("x", 1000),
        # exact value
        zero_int: 0,
        # within range
        float_range: 0.0,
        result: "boundary_test"
      }

      {:ok, _} = schema.validate(boundary_data)

      # Test violations
      violation_data = %{
        min_str: "",
        # exceeds max
        max_str: String.duplicate("x", 1001),
        # exceeds max
        zero_int: 1,
        # equals boundary (should fail with 'lt')
        float_range: 1.0,
        result: "violation_test"
      }

      {:error, _} = schema.validate(violation_data)
    end
  end
end
