defmodule DebugBootstrapTest do
  use ExUnit.Case, async: false
  @moduletag :group_3

  alias DSPEx.Test.MockProvider
  alias DSPEx.{Example, Predict, Program}
  alias DSPEx.Teleprompter
  alias DSPEx.Teleprompter.BootstrapFewShot

  defmodule DebugSignature do
    use DSPEx.Signature, "question -> answer"
  end

  setup do
    {:ok, _pid} = MockProvider.start_link(mode: :contextual)

    teacher = %Predict{signature: DebugSignature, client: :test}

    example = %Example{
      data: %{question: "What is 2+2?", answer: "4"},
      input_keys: MapSet.new([:question])
    }

    %{teacher: teacher, example: example}
  end

  test "debug individual teacher call", %{teacher: teacher, example: example} do
    # Use direct MockClientManager approach instead of MockProvider
    DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "4"}])

    # Check what responses are actually set
    IO.puts("=== Mock Setup Debug ===")

    [:test, :teacher, :openai, :gpt4, :gemini]
    |> Enum.each(fn provider ->
      responses = DSPEx.MockClientManager.get_mock_responses(provider)
      IO.puts("Provider #{provider}: #{length(responses)} responses")

      if not Enum.empty?(responses) do
        IO.puts("  First response: #{inspect(List.first(responses))}")
      end
    end)

    # Test teacher call
    inputs = Example.inputs(example)
    IO.puts("\n=== Teacher Call Debug ===")
    IO.puts("Inputs: #{inspect(inputs)}")

    result = Program.forward(teacher, inputs)
    IO.puts("Result: #{inspect(result)}")

    case result do
      {:ok, prediction} ->
        assert prediction[:answer] == "4"

        # Test metric function
        metric_fn = Teleprompter.exact_match(:answer)
        score = metric_fn.(example, prediction)
        IO.puts("Expected: #{inspect(Example.outputs(example)[:answer])}")
        IO.puts("Predicted: #{inspect(prediction[:answer])}")
        IO.puts("Score: #{score}")

        assert score == 1.0

      {:error, reason} ->
        IO.puts("ERROR: #{inspect(reason)}")
        # Let's try a direct client call to debug
        messages = [%{role: "user", content: "What is 2+2?"}]
        direct_result = DSPEx.Client.request(:test, messages, %{})
        IO.puts("Direct client result: #{inspect(direct_result)}")

        flunk("Teacher call failed: #{inspect(reason)}")
    end
  end

  test "debug full bootstrap process", %{teacher: teacher, example: example} do
    # Set up mock responses
    DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "4"}])

    # Create student program
    student = %Predict{signature: DebugSignature, client: :test}

    # Create trainset
    trainset = [example]

    # Create metric function
    metric_fn = Teleprompter.exact_match(:answer)

    IO.puts("\n=== Bootstrap Process Debug ===")
    IO.puts("Trainset: #{inspect(trainset)}")
    IO.puts("Expected answer: #{inspect(Example.outputs(example)[:answer])}")

    # Test the bootstrap process step by step
    IO.puts("\n1. Testing teacher on trainset:")
    inputs = Example.inputs(example)
    teacher_result = Program.forward(teacher, inputs)
    IO.puts("Teacher result: #{inspect(teacher_result)}")

    case teacher_result do
      {:ok, prediction} ->
        IO.puts("\n2. Testing metric function:")
        score = metric_fn.(example, prediction)
        IO.puts("Metric score: #{score}")

        if score > 0.0 do
          IO.puts("\n3. Running full bootstrap:")

          result =
            BootstrapFewShot.compile(
              student,
              teacher,
              trainset,
              metric_fn,
              # Very low threshold
              quality_threshold: 0.0
            )

          IO.puts("Bootstrap result: #{inspect(result)}")

          case result do
            {:ok, optimized} ->
              IO.puts("✅ Bootstrap succeeded!")

              demos =
                case optimized do
                  %DSPEx.OptimizedProgram{demos: demos} -> demos
                  %{demos: demos} -> demos
                  _ -> []
                end

              IO.puts("Number of demos: #{length(demos)}")

            {:error, reason} ->
              IO.puts("❌ Bootstrap failed: #{inspect(reason)}")
              flunk("Bootstrap should have succeeded with quality_threshold: 0.0")
          end
        else
          flunk("Metric function returned 0.0 - this should not happen with exact match")
        end

      {:error, reason} ->
        flunk("Teacher call failed: #{inspect(reason)}")
    end
  end
end
