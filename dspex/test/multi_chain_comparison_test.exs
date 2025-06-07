defmodule DSPEx.MultiChainComparisonTest do
  use ExUnit.Case, async: false

  defmodule QASignature do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule ComparisonSignature do
    @moduledoc "Compare multiple candidate answers and select the best one"
    use DSPEx.Signature, "question, candidates -> reasoning, answer"
  end

  defmodule MockClient do
    def request(_client, request) do
      # Return different responses based on request content
      content = Jason.encode!(request)

      cond do
        String.contains?(content, "candidates") ->
          # Comparison request
          {:ok, %{
            choices: [%{message: %{content: """
            [[ ## reasoning ## ]]
            Looking at the candidates: "blue", "red", "green".
            Blue is the most commonly cited color for the sky.

            [[ ## answer ## ]]
            blue
            """}}],
            usage: %{prompt_tokens: 30, completion_tokens: 20}
          }}

        true ->
          # Regular answer generation
          {:ok, %{
            choices: [%{message: %{content: "[[ ## answer ## ]]\nblue"}}],
            usage: %{prompt_tokens: 15, completion_tokens: 5}
          }}
      end
    end
  end

  setup do
    {:ok, client} = start_supervised({DSPEx.Client, %{
      api_key: "test",
      model: "test",
      adapter: MockClient
    }})

    %{client: client}
  end

  describe "multi-chain comparison initialization" do
    test "creates comparison program with signature", %{client: client} do
      mcc = DSPEx.MultiChainComparison.new(
        QASignature,
        client: client,
        comparison_signature: ComparisonSignature
      )

      assert mcc.base_signature == QASignature
      assert mcc.comparison_signature == ComparisonSignature
      assert mcc.client == client
    end

    test "uses default comparison signature if not provided", %{client: client} do
      mcc = DSPEx.MultiChainComparison.new(QASignature, client: client)

      assert mcc.base_signature == QASignature
      assert is_atom(mcc.comparison_signature)  # Dynamic signature
    end
  end

  describe "candidate generation and comparison" do
    test "generates multiple candidates and selects best", %{client: client} do
      mcc = DSPEx.MultiChainComparison.new(
        QASignature,
        client: client,
        comparison_signature: ComparisonSignature,
        num_candidates: 3
      )

      result = DSPEx.MultiChainComparison.forward(mcc, %{question: "What color is the sky?"})

      assert {:ok, prediction} = result
      assert prediction.answer == "blue"
      assert String.contains?(prediction.reasoning, "candidates")
      assert String.contains?(prediction.reasoning, "blue")
    end

    test "handles provided completions", %{client: client} do
      completions = [
        %{answer: "blue"},
        %{answer: "red"},
        %{answer: "green"}
      ]

      mcc = DSPEx.MultiChainComparison.new(
        QASignature,
        client: client,
        comparison_signature: ComparisonSignature
      )

      result = DSPEx.MultiChainComparison.forward(
        mcc,
        %{question: "What color is the sky?"},
        completions: completions
      )

      assert {:ok, prediction} = result
      assert prediction.answer == "blue"
    end

    test "validates minimum number of candidates", %{client: client} do
      mcc = DSPEx.MultiChainComparison.new(
        QASignature,
        client: client,
        num_candidates: 1  # Too few for meaningful comparison
      )

      result = DSPEx.MultiChainComparison.forward(mcc, %{question: "Test?"})

      assert {:error, :insufficient_candidates} = result
    end
  end

  describe "comparison strategies" do
    test "supports different comparison methods" do
      defmodule RankingSignature do
        use DSPEx.Signature, "question, candidates -> rankings, best_answer"
      end

      defmodule RankingMockClient do
        def request(_client, _request) do
          {:ok, %{
            choices: [%{message: %{content: """
            [[ ## rankings ## ]]
            1. blue (most accurate)
            2. cyan (close but less common)
            3. red (incorrect)

            [[ ## best_answer ## ]]
            blue
            """}}],
            usage: %{prompt_tokens: 25, completion_tokens: 15}
          }}
        end
      end

      {:ok, ranking_client} = start_supervised({DSPEx.Client, %{
        api_key: "test",
        model: "ranking_test",
        adapter: RankingMockClient
      }}, id: :ranking_client)

      mcc = DSPEx.MultiChainComparison.new(
        QASignature,
        client: ranking_client,
        comparison_signature: RankingSignature,
        num_candidates: 3
      )

      result = DSPEx.MultiChainComparison.forward(mcc, %{question: "What color is the sky?"})

      assert {:ok, prediction} = result
      assert prediction.best_answer == "blue"
      assert String.contains?(prediction.rankings, "most accurate")
    end
  end

  describe "error handling and robustness" do
    test "handles candidate generation failures", %{client: client} do
      defmodule FailingClient do
        @failure_count :ets.new(:failure_count, [:public, :set])

        def request(_client, _request) do
          case :ets.update_counter(@failure_count, :count, 1, {:count, 0}) do
            count when count <= 2 ->
              {:error, :generation_failed}
            _ ->
              {:ok, %{
                choices: [%{message: %{content: "[[ ## answer ## ]]\nfallback"}}],
                usage: %{prompt_tokens: 10, completion_tokens: 3}
              }}
          end
        end
      end

      {:ok, failing_client} = start_supervised({DSPEx.Client, %{
        api_key: "test",
        model: "failing_test",
        adapter: FailingClient
      }}, id: :failing_client)

      mcc = DSPEx.MultiChainComparison.new(
        QASignature,
        client: failing_client,
        num_candidates: 3,
        min_candidates: 1  # Allow fewer candidates if some fail
      )

      result = DSPEx.MultiChainComparison.forward(mcc, %{question: "Test?"})

      # Should succeed with at least one candidate
      assert {:ok, _prediction} = result
    end

    test "falls back gracefully when comparison fails", %{client: client} do
      defmodule ComparisonFailingClient do
        def request(_client, request) do
          content = Jason.encode!(request)

          if String.contains?(content, "candidates") do
            {:error, :comparison_failed}
          else
            {:ok, %{
              choices: [%{message: %{content: "[[ ## answer ## ]]\nfirst_candidate"}}],
              usage: %{prompt_tokens: 10, completion_tokens: 3}
            }}
          end
        end
      end

      {:ok, failing_client} = start_supervised({DSPEx.Client, %{
        api_key: "test",
        model: "comparison_failing",
        adapter: ComparisonFailingClient
      }}, id: :comparison_failing_client)

      mcc = DSPEx.MultiChainComparison.new(
        QASignature,
        client: failing_client,
        fallback_strategy: :first_candidate
      )

      result = DSPEx.MultiChainComparison.forward(mcc, %{question: "Test?"})

      # Should fall back to first candidate
      assert {:ok, prediction} = result
      assert prediction.answer == "first_candidate"
    end
  end
end
