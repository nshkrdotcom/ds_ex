defmodule DSPEx.SignatureSuiteTest do
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

    test "raises on invalid field names" do
      assert_raise CompileError, fn ->
        DSPEx.Signature.Parser.parse("123invalid -> answer")
      end
    end

    test "rejects empty input fields" do
      assert_raise CompileError, ~r/DSPEx signature must have at least one input field/, fn ->
        DSPEx.Signature.Parser.parse(" -> answer")
      end
    end

    test "rejects empty output fields" do
      assert_raise CompileError, ~r/DSPEx signature must have at least one output field/, fn ->
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

  describe "signature equality and comparison" do
    defmodule Sig1 do
      use DSPEx.Signature, "input1 -> output1"
    end

    defmodule Sig2 do
      use DSPEx.Signature, "input1 -> output1"
    end

    defmodule Sig3 do
      use DSPEx.Signature, "input2 -> output2"
    end

    test "signatures with same fields are equivalent" do
      assert Sig1.fields() == Sig2.fields()
      assert Sig1.input_fields() == Sig2.input_fields()
      assert Sig1.output_fields() == Sig2.output_fields()
    end

    test "signatures with different fields are not equivalent" do
      refute Sig1.fields() == Sig3.fields()
      refute Sig1.input_fields() == Sig3.input_fields()
      refute Sig1.output_fields() == Sig3.output_fields()
    end
  end

  describe "complex signature patterns" do
    defmodule ComplexSignature do
      @moduledoc "Multi-line instructions for complex reasoning"
      use DSPEx.Signature, "text, context, examples -> classification, confidence, reasoning"
    end

    test "handles complex multi-field signatures" do
      expected_inputs = [:text, :context, :examples]
      expected_outputs = [:classification, :confidence, :reasoning]

      assert ComplexSignature.input_fields() == expected_inputs
      assert ComplexSignature.output_fields() == expected_outputs
      assert ComplexSignature.fields() == expected_inputs ++ expected_outputs
    end

    test "preserves field order" do
      fields = ComplexSignature.fields()
      assert Enum.at(fields, 0) == :text
      assert Enum.at(fields, 1) == :context
      assert Enum.at(fields, 2) == :examples
      assert Enum.at(fields, 3) == :classification
      assert Enum.at(fields, 4) == :confidence
      assert Enum.at(fields, 5) == :reasoning
    end
  end
end
