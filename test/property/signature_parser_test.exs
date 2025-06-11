defmodule DSPEx.Property.SignatureParserTest do
  @moduledoc """
  Property-like tests for DSPEx.Signature parser.
  Tests parsing behavior across wide range of inputs using regular unit tests.
  """
  use ExUnit.Case, async: true

  @moduletag :phase_1

  describe "signature parsing edge cases" do
    test "parsed signatures maintain field order" do
      test_cases = [
        {"input -> output", {[:input], [:output]}},
        {"question -> answer", {[:question], [:answer]}},
        {"data -> result", {[:data], [:result]}},
        {"input1, input2 -> output1", {[:input1, :input2], [:output1]}},
        {"question, context -> answer, confidence",
         {[:question, :context], [:answer, :confidence]}}
      ]

      for {signature_string, expected} <- test_cases do
        assert DSPEx.Signature.Parser.parse(signature_string) == expected
      end
    end

    test "valid simple signatures parse correctly" do
      test_cases = [
        {"input -> output", {[:input], [:output]}},
        {"question -> answer", {[:question], [:answer]}},
        {"context -> result", {[:context], [:result]}},
        {"field -> value", {[:field], [:value]}},
        {"item -> data", {[:item], [:data]}}
      ]

      for {signature_string, expected} <- test_cases do
        {parsed_inputs, parsed_outputs} = DSPEx.Signature.Parser.parse(signature_string)
        assert {parsed_inputs, parsed_outputs} == expected
      end
    end

    test "roundtrip parsing preserves structure" do
      test_cases = [
        "input -> output",
        "question -> answer",
        "data -> result",
        "input1, input2 -> output1",
        "question, context -> answer, confidence"
      ]

      for signature_string <- test_cases do
        {parsed_inputs, parsed_outputs} = DSPEx.Signature.Parser.parse(signature_string)

        # Reconstruct and parse again
        reconstructed = "#{Enum.join(parsed_inputs, ", ")} -> #{Enum.join(parsed_outputs, ", ")}"
        {reparsed_inputs, reparsed_outputs} = DSPEx.Signature.Parser.parse(reconstructed)

        assert {parsed_inputs, parsed_outputs} == {reparsed_inputs, reparsed_outputs}
      end
    end

    test "signature with duplicate fields fails" do
      duplicate_cases = [
        "field, field -> output",
        "input, input -> result",
        "question, question -> answer",
        "data -> result, result",
        "input -> output, output"
      ]

      for signature_string <- duplicate_cases do
        assert_raise CompileError, fn ->
          DSPEx.Signature.Parser.parse(signature_string)
        end
      end
    end

    test "invalid signature formats fail appropriately" do
      invalid_cases = [
        "no arrow separator",
        "input ->",
        "-> output",
        "",
        "multiple -> arrows -> here",
        "input, -> output",
        "input -> , output"
      ]

      for signature_string <- invalid_cases do
        assert_raise CompileError, fn ->
          DSPEx.Signature.Parser.parse(signature_string)
        end
      end
    end

    test "whitespace handling is consistent" do
      base_cases = [
        {"input->output", {[:input], [:output]}},
        {"  input  ->  output  ", {[:input], [:output]}},
        {"input,context->answer,confidence", {[:input, :context], [:answer, :confidence]}},
        {"  input  ,  context  ->  answer  ,  confidence  ",
         {[:input, :context], [:answer, :confidence]}}
      ]

      for {signature_string, expected} <- base_cases do
        assert DSPEx.Signature.Parser.parse(signature_string) == expected
      end
    end

    test "field name validation" do
      valid_cases = [
        "input -> output",
        "field_name -> result_value",
        "input1 -> output2",
        "question_text -> answer_text"
      ]

      for signature_string <- valid_cases do
        {inputs, outputs} = DSPEx.Signature.Parser.parse(signature_string)
        assert is_list(inputs) and is_list(outputs)
        assert Enum.all?(inputs, &is_atom/1)
        assert Enum.all?(outputs, &is_atom/1)
      end

      invalid_field_cases = [
        "123invalid -> output",
        "input -> 456invalid",
        # Capital letter start
        "Input -> output",
        # Hyphen not allowed
        "input-name -> output"
      ]

      for signature_string <- invalid_field_cases do
        assert_raise CompileError, fn ->
          DSPEx.Signature.Parser.parse(signature_string)
        end
      end
    end
  end
end
