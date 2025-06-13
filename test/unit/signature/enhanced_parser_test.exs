defmodule DSPEx.Signature.EnhancedParserTest do
  use ExUnit.Case, async: true
  doctest DSPEx.Signature.EnhancedParser

  alias DSPEx.Signature.EnhancedParser

  describe "enhanced_signature?/1" do
    test "detects enhanced signatures with types" do
      assert EnhancedParser.enhanced_signature?("name:string -> greeting:string")
      assert EnhancedParser.enhanced_signature?("age:integer -> valid:boolean")
    end

    test "detects enhanced signatures with constraints" do
      assert EnhancedParser.enhanced_signature?("name[min_length=2] -> greeting")
      assert EnhancedParser.enhanced_signature?("email:string[format=/^[^@]+@[^@]+$/] -> status")
    end

    test "rejects basic signatures" do
      refute EnhancedParser.enhanced_signature?("question -> answer")
      refute EnhancedParser.enhanced_signature?("question, context -> answer, confidence")
    end
  end

  describe "parse/1 - basic enhanced signatures" do
    test "parses type annotations" do
      {inputs, outputs} = EnhancedParser.parse("name:string -> greeting:string")

      assert length(inputs) == 1
      assert length(outputs) == 1

      input = hd(inputs)
      assert input.name == :name
      assert input.type == :string
      assert input.constraints == %{}
      assert input.required == true

      output = hd(outputs)
      assert output.name == :greeting
      assert output.type == :string
    end

    test "parses multiple types" do
      {inputs, outputs} = EnhancedParser.parse("age:integer, score:float -> pass:boolean")

      assert length(inputs) == 2
      assert length(outputs) == 1

      [age, score] = inputs
      assert age.name == :age
      assert age.type == :integer
      assert score.name == :score
      assert score.type == :float

      pass = hd(outputs)
      assert pass.type == :boolean
    end
  end

  describe "parse/1 - constraint parsing" do
    test "parses single constraints" do
      {[input], _} = EnhancedParser.parse("name:string[min_length=2] -> greeting")

      assert input.constraints == %{min_length: 2}
    end

    test "parses multiple constraints" do
      {[input], _} = EnhancedParser.parse("name:string[min_length=2,max_length=50] -> greeting")

      assert input.constraints == %{min_length: 2, max_length: 50}
    end

    test "parses numeric constraints" do
      {[input], _} = EnhancedParser.parse("score:integer[gteq=0,lteq=100] -> grade")

      assert input.constraints == %{gteq: 0, lteq: 100}
    end

    test "parses min_length constraints" do
      {[input], _} = EnhancedParser.parse("email:string[min_length=5] -> status")

      assert input.constraints.min_length == 5
    end

    test "parses max_length constraints" do
      {[input], _} = EnhancedParser.parse("grade:string[max_length=2] -> points")

      assert input.constraints.max_length == 2
    end

    test "parses default values" do
      {[input], _} = EnhancedParser.parse("status:string[default='pending'] -> result")

      assert input.default == "pending"
      assert input.required == false
    end

    test "parses optional fields" do
      {[input], _} = EnhancedParser.parse("optional_field:string[optional=true] -> result")

      assert input.required == false
      assert input.default == nil
    end
  end

  describe "parse/1 - array types" do
    test "parses simple array types" do
      {[input], _} = EnhancedParser.parse("tags:array(string) -> summary")

      assert input.type == {:array, :string}
    end

    test "parses array constraints" do
      {[input], _} =
        EnhancedParser.parse("tags:array(string)[min_items=1,max_items=10] -> summary")

      assert input.type == {:array, :string}
      assert input.constraints == %{min_items: 1, max_items: 10}
    end

    test "parses nested array types" do
      {[input], _} = EnhancedParser.parse("scores:array(integer) -> average:float")

      assert input.type == {:array, :integer}
    end
  end

  describe "parse/1 - error handling" do
    test "raises on invalid field names" do
      assert_raise CompileError, ~r/Invalid field name/, fn ->
        EnhancedParser.parse("123invalid:string -> result")
      end
    end

    test "raises on invalid types" do
      assert_raise CompileError, ~r/Invalid type/, fn ->
        EnhancedParser.parse("field:invalid_type -> result")
      end
    end

    test "raises on malformed constraint syntax" do
      assert_raise CompileError, ~r/Invalid type/, fn ->
        EnhancedParser.parse("field:string[unclosed_bracket -> result")
      end
    end

    test "raises on duplicate fields" do
      assert_raise CompileError, ~r/Duplicate fields/, fn ->
        EnhancedParser.parse("name:string -> name:string")
      end
    end

    test "raises on incompatible constraints" do
      assert_raise CompileError, ~r/not compatible/, fn ->
        EnhancedParser.parse("age:string[gteq=0] -> result")
      end
    end
  end

  describe "to_simple_signature/1" do
    test "converts enhanced to simple format" do
      enhanced =
        EnhancedParser.parse("name:string[min_length=2] -> greeting:string[max_length=100]")

      {inputs, outputs} = EnhancedParser.to_simple_signature(enhanced)

      assert inputs == [:name]
      assert outputs == [:greeting]
    end
  end

  describe "backward compatibility" do
    test "handles mixed enhanced and basic fields" do
      {inputs, _outputs} =
        EnhancedParser.parse("question, name:string[min_length=1] -> answer:string")

      assert length(inputs) == 2

      [question, name] = inputs
      assert question.name == :question
      # default type
      assert question.type == :string
      assert question.constraints == %{}

      assert name.name == :name
      assert name.type == :string
      assert name.constraints == %{min_length: 1}
    end
  end
end
