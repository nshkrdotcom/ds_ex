defmodule DSPEx.Signature.EnhancedMacroTest do
  use ExUnit.Case, async: true

  describe "enhanced signature detection and compilation" do
    test "compiles enhanced signature with constraints" do
      defmodule TestEnhancedSignature do
        use DSPEx.Signature,
            "name:string[min_length=2,max_length=50] -> greeting:string[max_length=100]"
      end

      # Test basic signature behavior
      assert TestEnhancedSignature.input_fields() == [:name]
      assert TestEnhancedSignature.output_fields() == [:greeting]
      assert TestEnhancedSignature.fields() == [:name, :greeting]

      # Test enhanced field definitions are stored
      assert function_exported?(TestEnhancedSignature, :__enhanced_fields__, 0)
      enhanced_fields = TestEnhancedSignature.__enhanced_fields__()

      assert length(enhanced_fields) == 2

      [name_field, greeting_field] = enhanced_fields
      assert name_field.name == :name
      assert name_field.type == :string
      assert name_field.constraints == %{min_length: 2, max_length: 50}

      assert greeting_field.name == :greeting
      assert greeting_field.type == :string
      assert greeting_field.constraints == %{max_length: 100}
    end

    test "compiles array type signatures" do
      defmodule TestArraySignature do
        use DSPEx.Signature, "tags:array(string)[min_items=1,max_items=10] -> summary:string"
      end

      enhanced_fields = TestArraySignature.__enhanced_fields__()
      [tags_field, _] = enhanced_fields

      assert tags_field.type == {:array, :string}
      assert tags_field.constraints == %{min_items: 1, max_items: 10}
    end

    test "falls back gracefully for basic signatures" do
      defmodule TestBasicSignature do
        use DSPEx.Signature, "question -> answer"
      end

      # Should not have enhanced fields function for basic signatures
      refute function_exported?(TestBasicSignature, :__enhanced_fields__, 0)

      # But should still work normally
      assert TestBasicSignature.input_fields() == [:question]
      assert TestBasicSignature.output_fields() == [:answer]
    end

    test "maintains backward compatibility" do
      defmodule TestCompatibilitySignature do
        use DSPEx.Signature, "question, context -> answer, confidence"
      end

      # Test normal operation
      signature =
        TestCompatibilitySignature.new(%{
          question: "Test",
          context: "Context",
          answer: "Answer",
          confidence: 0.9
        })

      assert signature.question == "Test"
      assert signature.answer == "Answer"

      # Validation should work
      assert :ok =
               TestCompatibilitySignature.validate_inputs(%{question: "Test", context: "Context"})

      assert {:error, {:missing_inputs, [:context]}} =
               TestCompatibilitySignature.validate_inputs(%{question: "Test"})
    end
  end

  describe "enhanced field definitions storage" do
    test "stores constraint information correctly" do
      defmodule TestConstraintStorage do
        use DSPEx.Signature,
            "score:integer[gteq=0,lteq=100] -> grade:string[min_length=1,max_length=1]"
      end

      enhanced_fields = TestConstraintStorage.__enhanced_fields__()
      [score_field, grade_field] = enhanced_fields

      # Test numeric constraints
      assert score_field.constraints.gteq == 0
      assert score_field.constraints.lteq == 100

      # Test string constraints
      assert grade_field.constraints.min_length == 1
      assert grade_field.constraints.max_length == 1
    end

    test "stores default and required information" do
      defmodule TestRequiredDefaults do
        use DSPEx.Signature,
            "required:string[min_length=1], optional:string[default='test'] -> result:string"
      end

      enhanced_fields = TestRequiredDefaults.__enhanced_fields__()
      [required_field, optional_field, _result] = enhanced_fields

      assert required_field.required == true
      assert required_field.default == nil

      assert optional_field.required == false
      assert optional_field.default == "test"
    end
  end

  describe "compile-time validation" do
    test "raises on invalid enhanced signature syntax" do
      assert_raise CompileError, fn ->
        defmodule TestInvalidSyntax do
          use DSPEx.Signature, "field:invalid_type -> result"
        end
      end
    end

    test "raises on constraint-type mismatches" do
      assert_raise CompileError, fn ->
        defmodule TestTypeMismatch do
          use DSPEx.Signature, "text:string[min_items=1] -> result"
        end
      end
    end
  end
end
