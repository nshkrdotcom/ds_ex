# Debug bootstrap process step by step
alias DSPEx.Test.{MockProvider, SimbaMockProvider}
alias DSPEx.{MockClientManager, Example, Predict, Program}
alias DSPEx.Teleprompter

# Define test signature
defmodule DebugBootstrapSignature do
  use DSPEx.Signature, "question -> answer"
end

# Create test programs  
student = %Predict{signature: DebugBootstrapSignature, client: :test}
teacher = %Predict{signature: DebugBootstrapSignature, client: :test}

# Create test example
example = %Example{
  data: %{question: "What is 2+2?", answer: "4"},
  input_keys: MapSet.new([:question])
}

# Start mock provider
{:ok, _pid} = MockProvider.start_link(mode: :contextual)

# Set up simple mock responses
MockProvider.setup_bootstrap_mocks([%{content: "4"}])

IO.puts("=== Debug Bootstrap Process ===")

# Test 1: Direct teacher call
IO.puts("\n1. Testing direct teacher call:")
inputs = Example.inputs(example)
IO.puts("Inputs: #{inspect(inputs)}")

result = Program.forward(teacher, inputs)
IO.puts("Teacher result: #{inspect(result)}")

# Test 2: Metric function test
if match?({:ok, prediction}, result) do
  IO.puts("\n2. Testing metric function:")
  {:ok, prediction} = result
  
  metric_fn = Teleprompter.exact_match(:answer)
  score = metric_fn.(example, prediction)
  IO.puts("Expected answer: #{inspect(Example.outputs(example)[:answer])}")
  IO.puts("Predicted answer: #{inspect(prediction[:answer])}")
  IO.puts("Metric score: #{score}")
else
  IO.puts("\n2. Teacher call failed, skipping metric test")
end

IO.puts("\n=== End Debug ===")