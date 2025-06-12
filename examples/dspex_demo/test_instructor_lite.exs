#!/usr/bin/env elixir

# Test DSPEx with InstructorLite structured outputs
IO.puts("🚀 Testing DSPEx + InstructorLite Integration")

alias DspexDemo.Signatures.QASignature

# Test structured prediction with InstructorLite
IO.puts("\n📝 Testing DSPEx.PredictStructured with Gemini...")

# Create structured prediction program  
program = DSPEx.PredictStructured.new(QASignature, :gemini)
IO.puts("✅ Created structured prediction program")

# Test questions
test_questions = [
  "What is the chemical symbol for gold?",
  "What is 25% of 80?", 
  "Who invented the telephone?"
]

Enum.each(test_questions, fn question ->
  IO.puts("\n" <> String.duplicate("=", 60))
  IO.puts("🤔 Question: #{question}")
  IO.puts(String.duplicate("=", 60))
  
  # Use DSPEx.Program.forward with our structured program
  case DSPEx.Program.forward(program, %{question: question}) do
    {:ok, result} ->
      IO.puts("✅ STRUCTURED SUCCESS!")
      IO.puts("   Answer: #{Map.get(result, :answer, "N/A")}")
      IO.puts("   Reasoning: #{Map.get(result, :reasoning, "N/A")}")
      IO.puts("   Confidence: #{Map.get(result, :confidence, "N/A")}")
      
    {:error, reason} ->
      IO.puts("❌ Error: #{inspect(reason)}")
  end
  
  # Small delay to avoid rate limiting
  :timer.sleep(2000)
end)

IO.puts("""

🎉 DSPEx + InstructorLite integration test complete!

This demonstrates how DSPEx can now provide structured outputs
using InstructorLite's JSON schema validation with Gemini.

""")