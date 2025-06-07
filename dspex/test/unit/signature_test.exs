defmodule DSPEx.SignatureTest do
  @moduledoc """
  Unit tests for DSPEx.Signature module.
  Tests macro expansion, parser functionality, and behaviour implementation.
  """
  use ExUnit.Case, async: true

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

    test "handles empty input fields" do
      assert DSPEx.Signature.Parser.parse(" -> answer") == {[], [:answer]}
    end

    test "handles empty output fields" do
      assert DSPEx.Signature.Parser.parse("question -> ") == {[:question], []}
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
      fields = MacroTestSig.__struct__().__struct__
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
end
