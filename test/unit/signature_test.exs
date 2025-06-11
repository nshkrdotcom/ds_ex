defmodule DSPEx.SignatureTest do
  @moduledoc """
  Unit tests for DSPEx.Signature module.
  Tests macro expansion, parser functionality, and behaviour implementation.
  """
  use ExUnit.Case, async: true

  @moduletag :group_1

  describe "signature parsing" do
    test "parses simple input -> output" do
      assert DSPEx.Signature.Parser.parse("question -> answer") ==
               {[:question], [:answer]}
    end

    test "parses multiple inputs and outputs" do
      assert DSPEx.Signature.Parser.parse("question, context -> answer, confidence") ==
               {[:question, :context], [:answer, :confidence]}
    end

    test "handles whitespace gracefully" do
      assert DSPEx.Signature.Parser.parse("  question  ,  context  ->  answer  ") ==
               {[:question, :context], [:answer]}
    end

    test "raises on invalid format" do
      assert_raise CompileError, fn ->
        DSPEx.Signature.Parser.parse("invalid signature")
      end
    end

    test "raises on duplicate fields" do
      assert_raise CompileError, fn ->
        DSPEx.Signature.Parser.parse("question, question -> answer")
      end
    end

    test "validates field names are valid atoms" do
      assert_raise CompileError, fn ->
        DSPEx.Signature.Parser.parse("123invalid -> answer")
      end
    end

    test "rejects empty input fields" do
      assert_raise CompileError, fn ->
        DSPEx.Signature.Parser.parse(" -> answer")
      end
    end

    test "rejects empty output fields" do
      assert_raise CompileError, fn ->
        DSPEx.Signature.Parser.parse("question -> ")
      end
    end
  end

  describe "generated signature modules" do
    defmodule TestSignature do
      @moduledoc "Test signature for unit testing"
      use DSPEx.Signature, "question, context -> answer, reasoning"
    end

    test "implements behaviour correctly" do
      assert TestSignature.instructions() == "Test signature for unit testing"
      assert TestSignature.input_fields() == [:question, :context]
      assert TestSignature.output_fields() == [:answer, :reasoning]
      assert TestSignature.fields() == [:question, :context, :answer, :reasoning]
    end

    test "creates valid struct" do
      sig = TestSignature.new(%{question: "What is 2+2?", context: "math"})
      assert %TestSignature{question: "What is 2+2?", context: "math"} = sig
    end

    test "validates inputs correctly" do
      assert TestSignature.validate_inputs(%{question: "test", context: "test"}) == :ok

      assert TestSignature.validate_inputs(%{question: "test"}) ==
               {:error, {:missing_inputs, [:context]}}
    end

    test "validates outputs correctly" do
      assert TestSignature.validate_outputs(%{answer: "test", reasoning: "because"}) == :ok

      assert TestSignature.validate_outputs(%{answer: "test"}) ==
               {:error, {:missing_outputs, [:reasoning]}}
    end
  end

  describe "compile-time macro behavior" do
    defmodule MacroTestSig do
      @moduledoc "Macro behavior testing signature"
      use DSPEx.Signature, "input1, input2 -> output1"
    end

    test "generates struct with correct fields" do
      assert %MacroTestSig{} = struct(MacroTestSig)

      # Check that all fields exist on the struct
      _fields = MacroTestSig.__struct__().__struct__
      struct_fields = Map.keys(MacroTestSig.__struct__()) -- [:__struct__]
      expected_fields = [:input1, :input2, :output1]

      assert Enum.all?(expected_fields, &(&1 in struct_fields))
    end

    test "generates type specification" do
      # This is a compile-time check - if the code compiles, the type spec exists
      # We can verify the module implements the behavior correctly
      assert function_exported?(MacroTestSig, :__struct__, 0)
      assert function_exported?(MacroTestSig, :__struct__, 1)
    end

    test "extracts instructions from moduledoc" do
      assert MacroTestSig.instructions() == "Macro behavior testing signature"
    end

    test "handles signatures with no moduledoc" do
      defmodule NoDocSig do
        use DSPEx.Signature, "in -> out"
      end

      # Should have a default instruction when no moduledoc is provided
      instructions = NoDocSig.instructions()
      assert is_binary(instructions)
      assert String.length(instructions) > 0
    end
  end

  describe "signature field ordering" do
    defmodule OrderTestSig do
      @moduledoc "Field ordering test"
      use DSPEx.Signature, "first, second, third -> alpha, beta"
    end

    test "preserves input field order" do
      assert OrderTestSig.input_fields() == [:first, :second, :third]
    end

    test "preserves output field order" do
      assert OrderTestSig.output_fields() == [:alpha, :beta]
    end

    test "preserves overall field order" do
      assert OrderTestSig.fields() == [:first, :second, :third, :alpha, :beta]
    end
  end

  describe "signature validation edge cases" do
    test "handles single character field names" do
      assert DSPEx.Signature.Parser.parse("a, b -> c") == {[:a, :b], [:c]}
    end

    test "handles underscored field names" do
      assert DSPEx.Signature.Parser.parse("input_field -> output_field") ==
               {[:input_field], [:output_field]}
    end

    test "handles numeric suffixes in field names" do
      assert DSPEx.Signature.Parser.parse("input1, input2 -> output1") ==
               {[:input1, :input2], [:output1]}
    end

    test "rejects field names starting with numbers" do
      assert_raise CompileError, fn ->
        DSPEx.Signature.Parser.parse("1input -> output")
      end
    end

    test "rejects field names with special characters" do
      assert_raise CompileError, fn ->
        DSPEx.Signature.Parser.parse("input-field -> output")
      end
    end
  end

  describe "DSPEx.Signature.extend/2" do
    defmodule QASignature do
      @moduledoc "Answer questions with detailed reasoning"
      use DSPEx.Signature, "question -> answer"
    end

    test "extends a signature with additional output fields" do
      # Test extending QASignature with reasoning field
      {:ok, extended_signature} = DSPEx.Signature.extend(QASignature, %{reasoning: :text})

      # Verify the extended signature has all fields
      assert :question in extended_signature.input_fields()
      assert :answer in extended_signature.output_fields()
      assert :reasoning in extended_signature.output_fields()

      # Verify it can create structs with new field
      instance =
        extended_signature.new(%{
          question: "What is 2+2?",
          answer: "4",
          reasoning: "Basic arithmetic"
        })

      assert instance.question == "What is 2+2?"
      assert instance.answer == "4"
      assert instance.reasoning == "Basic arithmetic"
    end

    test "extends signature with multiple additional fields" do
      {:ok, extended} =
        DSPEx.Signature.extend(QASignature, %{
          reasoning: :text,
          confidence: :float,
          sources: :list
        })

      # Verify all new fields are in outputs
      assert :reasoning in extended.output_fields()
      assert :confidence in extended.output_fields()
      assert :sources in extended.output_fields()

      # Original fields still present
      assert :question in extended.input_fields()
      assert :answer in extended.output_fields()
    end

    test "returns error for conflicting field names" do
      # Try to add field that already exists
      {:error, error} = DSPEx.Signature.extend(QASignature, %{question: :text})

      assert error.__struct__ == ArgumentError
      assert error.message =~ "Field name conflicts"
    end

    test "returns error for non-signature module" do
      {:error, error} = DSPEx.Signature.extend(String, %{new_field: :text})

      assert error.__struct__ == ArgumentError
      assert error.message =~ "must implement DSPEx.Signature behavior"
    end

    test "extended signature maintains original instructions" do
      {:ok, extended} = DSPEx.Signature.extend(QASignature, %{reasoning: :text})

      # Should maintain the original instructions
      assert extended.instructions() == QASignature.instructions()
    end

    test "extended signature validation works correctly" do
      {:ok, extended} = DSPEx.Signature.extend(QASignature, %{reasoning: :text})

      # Valid inputs
      assert :ok == extended.validate_inputs(%{question: "test"})

      # Invalid inputs (missing required)
      {:error, {:missing_inputs, missing}} = extended.validate_inputs(%{})
      assert :question in missing

      # Valid outputs
      assert :ok == extended.validate_outputs(%{answer: "test", reasoning: "because"})

      # Invalid outputs (missing required)
      {:error, {:missing_outputs, missing}} = extended.validate_outputs(%{answer: "test"})
      assert :reasoning in missing
    end
  end

  describe "DSPEx.Signature.get_field_info/2" do
    defmodule FieldInfoTestSig do
      use DSPEx.Signature, "question -> answer"
    end

    test "returns field information for input fields" do
      {:ok, info} = DSPEx.Signature.get_field_info(FieldInfoTestSig, :question)

      assert info.name == :question
      assert info.type == :input
      assert info.category == :input
    end

    test "returns field information for output fields" do
      {:ok, info} = DSPEx.Signature.get_field_info(FieldInfoTestSig, :answer)

      assert info.name == :answer
      assert info.type == :output
      assert info.category == :output
    end

    test "returns error for non-existent fields" do
      assert {:error, :field_not_found} ==
               DSPEx.Signature.get_field_info(FieldInfoTestSig, :nonexistent)
    end
  end
end
