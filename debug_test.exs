# Quick debug script
alias DSPEx.Test.{MockProvider, SimbaMockProvider}
alias DSPEx.{MockClientManager, Example, Predict}
alias DSPEx.Teleprompter.BootstrapFewShot

# Start mock provider
{:ok, _pid} = MockProvider.start_link(mode: :contextual)

# Check persistent_term before setup
IO.puts("Before setup:")
IO.inspect(:persistent_term.get())

# Set up bootstrap mocks
MockProvider.setup_bootstrap_mocks([
  %{content: "4"},
  %{content: "6"},
  %{content: "Paris"}
])

# Check persistent_term after setup
IO.puts("\nAfter setup:")
IO.inspect(:persistent_term.get())

# Test direct mock access
IO.puts("\nTesting direct mock access:")
[:test, :teacher, :openai, :gpt4, :gemini]
|> Enum.each(fn provider ->
  responses = MockClientManager.get_mock_responses(provider)
  IO.puts("Provider #{provider}: #{length(responses)} responses")
  if not Enum.empty?(responses) do
    IO.puts("  First response: #{inspect(List.first(responses))}")
  end
end)

IO.puts("\nDone!")