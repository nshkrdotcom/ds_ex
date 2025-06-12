#!/usr/bin/env elixir

# Simple test script for SIMBA demo
IO.puts("🚀 Testing SIMBA Example App")

# Test basic functionality first
alias DSPEx.{Predict, Program}  
alias DspexDemo.Signatures.QASignature

IO.puts("📝 Testing signature...")
# First, check what fields the signature expects
try do
  input_fields = QASignature.input_fields()
  output_fields = QASignature.output_fields()
  IO.puts("✅ Signature loaded successfully")
  IO.puts("   Input fields: #{inspect(input_fields)}")
  IO.puts("   Output fields: #{inspect(output_fields)}")
rescue
  e ->
    IO.puts("❌ Signature error: #{inspect(e)}")
end

IO.puts("📝 Testing basic program creation...")

# Create a simple program
program = Predict.new(QASignature, :gemini)
IO.puts("✅ Created program successfully")

# Test a simple question with just the question field
test_input = %{question: "What is 2+2?"}
IO.puts("🧠 Testing simple question: #{test_input.question}")

case Program.forward(program, test_input) do
  {:ok, result} ->
    IO.puts("✅ Success! Response: #{inspect(result, pretty: true)}")
  {:error, reason} ->
    IO.puts("❌ Error: #{inspect(reason)}")
end

IO.puts("🎯 Basic test complete!")