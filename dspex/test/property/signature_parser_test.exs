defmodule DSPEx.Property.SignatureParserTest do
  @moduledoc """
  Property-based tests for DSPEx.Signature parser.
  Tests parsing properties across wide range of inputs.
  """
  use ExUnit.Case
  use PropCheck

  describe "signature parsing properties" do
    property "parsed signatures maintain field order" do
      forall {inputs, outputs} <- {field_list(), field_list()} do
        signature_string = "#{Enum.join(inputs, ", ")} -> #{Enum.join(outputs, ", ")}"
        {parsed_inputs, parsed_outputs} = DSPEx.Signature.Parser.parse(signature_string)

        Enum.map(inputs, &String.to_atom/1) == parsed_inputs and
        Enum.map(outputs, &String.to_atom/1) == parsed_outputs
      end
    end

    property "valid signatures never crash parser" do
      forall sig_string <- valid_signature_string() do
        try do
          DSPEx.Signature.Parser.parse(sig_string)
          true
        rescue
          _ -> false
        end
      end
    end

    property "invalid signatures always raise errors" do
      forall invalid_sig <- invalid_signature_string() do
        try do
          DSPEx.Signature.Parser.parse(invalid_sig)
          false
        rescue
          CompileError -> true
          _ -> false
        end
      end
    end

    property "field count is preserved" do
      forall {inputs, outputs} <- {field_list(), field_list()} do
        signature_string = "#{Enum.join(inputs, ", ")} -> #{Enum.join(outputs, ", ")}"
        {parsed_inputs, parsed_outputs} = DSPEx.Signature.Parser.parse(signature_string)

        length(parsed_inputs) == length(inputs) and
        length(parsed_outputs) == length(outputs)
      end
    end

    property "round-trip consistency" do
      forall {inputs, outputs} <- {non_empty_field_list(), non_empty_field_list()} do
        # Create signature string
        signature_string = "#{Enum.join(inputs, ", ")} -> #{Enum.join(outputs, ", ")}"

        # Parse it
        {parsed_inputs, parsed_outputs} = DSPEx.Signature.Parser.parse(signature_string)

        # Reconstruct signature string
        reconstructed = "#{Enum.join(parsed_inputs, ", ")} -> #{Enum.join(parsed_outputs, ", ")}"

        # Parse again
        {final_inputs, final_outputs} = DSPEx.Signature.Parser.parse(reconstructed)

        # Should be identical to first parse
        parsed_inputs == final_inputs and parsed_outputs == final_outputs
      end
    end

    property "whitespace normalization is consistent" do
      forall {inputs, outputs} <- {field_list(), field_list()} do
        base_sig = "#{Enum.join(inputs, ", ")} -> #{Enum.join(outputs, ", ")}"

        # Add random whitespace
        spaced_sig = "  #{Enum.join(inputs, "  ,  ")}  ->  #{Enum.join(outputs, "  ,  ")}  "

        DSPEx.Signature.Parser.parse(base_sig) == DSPEx.Signature.Parser.parse(spaced_sig)
      end
    end
  end

  # Property generators
  defp field_list() do
    list(field_name())
  end

  defp non_empty_field_list() do
    non_empty(list(field_name()))
  end

  defp field_name() do
    let name <- non_empty(string()) do
      # Generate valid Elixir atom names
      clean_name = String.replace(name, ~r/[^a-zA-Z0-9]/, "")
      case clean_name do
        "" -> "field"
        ^clean_name -> "field_" <> clean_name
      end
    end
  end

  defp valid_signature_string() do
    let {inputs, outputs} <- {non_empty_field_list(), non_empty_field_list()} do
      "#{Enum.join(inputs, ", ")} -> #{Enum.join(outputs, ", ")}"
    end
  end

  defp invalid_signature_string() do
    oneof([
      "no arrow separator",
      "input ->",
      "-> output",
      "",
      "multiple -> arrows -> here",
      "input, -> output",
      "input -> , output",
      "123invalid -> output",
      "input -> 456invalid"
    ])
  end
end
