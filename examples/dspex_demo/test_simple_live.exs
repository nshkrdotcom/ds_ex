#!/usr/bin/env elixir

# Simple test to check if we get live API responses
IO.puts("🔍 Testing Simple Live API Detection")

alias DSPEx.{Predict, Program}  
alias DspexDemo.Signatures.QASignature

# Pre-load signature module like in the working examples
QASignature.input_fields()

# Use the exact same setup as test_simple.exs but with a unique question
# that should give different responses between mock and live
test_input = %{question: "What is the capital of Zimbabwe?"}

IO.puts("🤔 Question: #{test_input.question}")

program = Predict.new(QASignature, :gemini)

case Program.forward(program, test_input) do
  {:ok, result} ->
    answer = Map.get(result, :answer, "No answer")
    IO.puts("📝 Full result: #{inspect(result, pretty: true)}")
    IO.puts("📝 Answer: #{answer}")
    
    # Check characteristics to determine if mock or live
    cond do
      String.contains?(answer, "Mock response") ->
        IO.puts("🔵 CONFIRMED: Mock response detected")
        
      answer == "4" ->
        IO.puts("🔵 CONFIRMED: Standard mock response")
        
      String.length(answer) > 15 and not String.contains?(answer, "Mock") ->
        IO.puts("🟢 LIKELY: Live API response (detailed answer)")
        
      true ->
        IO.puts("❓ UNCLEAR: Could be either mock or live")
    end
    
  {:error, reason} ->
    IO.puts("❌ Error: #{inspect(reason)}")
end

IO.puts("🎯 Test complete!")