#!/usr/bin/env elixir

# Test to confirm live API vs mock responses
IO.puts("🔍 Testing Live API vs Mock Detection")
IO.puts("=====================================")

alias DSPEx.{Predict, Program}  
alias DspexDemo.Signatures.QASignature

# Test with a complex question that would generate different responses
# between live API and mock
test_questions = [
  "Explain the difference between supervised and unsupervised machine learning in exactly 50 words",
  "What are the key benefits of using Elixir's OTP for building distributed systems?",
  "Write a haiku about functional programming"
]

program = Predict.new(QASignature, :gemini)

Enum.each(test_questions, fn question ->
  IO.puts("\n🤔 Question: #{question}")
  IO.puts("#{String.duplicate("-", 80)}")
  
  case Program.forward(program, %{question: question}) do
    {:ok, result} ->
      answer = Map.get(result, :answer, "No answer")
      reasoning = Map.get(result, :reasoning, "No reasoning")
      confidence = Map.get(result, :confidence, "No confidence")
      
      IO.puts("📝 Answer: #{answer}")
      IO.puts("🧠 Reasoning: #{reasoning}")  
      IO.puts("📊 Confidence: #{confidence}")
      
      # Check if this looks like a mock response
      if String.contains?(answer, "Mock response") or 
         String.contains?(answer, "testing purposes") or
         answer == "4" or
         String.length(answer) < 10 do
        IO.puts("🔵 DETECTED: Mock response")
      else
        IO.puts("🟢 DETECTED: Likely live API response")
      end
      
    {:error, reason} ->
      IO.puts("❌ Error: #{inspect(reason)}")
  end
end)

IO.puts("\n🎯 Live API test complete!")