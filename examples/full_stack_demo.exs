# Honor DSPEX_TEST_MODE if set; default to mock otherwise.
mode_env = System.get_env("DSPEX_TEST_MODE") || "mock"
mode_atom =
  case mode_env do
    "live" -> :live
    "fallback" -> :fallback
    _ -> :mock
  end

System.put_env("DSPEX_TEST_MODE", mode_env)
IO.puts("\n=== DSPEX_TEST_MODE=#{mode_atom} ===")
if mode_atom == :mock do
  IO.puts("Hint: run with DSPEX_TEST_MODE=live|fallback mix run examples/full_stack_demo.exs for real calls.")
end

live_model = System.get_env("DSPEX_MODEL") || "google:gemini-2.5-flash"
if mode_atom != :mock do
  System.put_env("DSPEX_MODEL", live_model)
end

defmodule Demo.Signatures.QA do
  use DSPEx.Signature, "question -> answer"
end

defmodule Demo.Signatures.RAG do
  use DSPEx.Signature, "question, context -> answer"
end

defmodule Demo.Teacher do
  use DSPEx.Program
  defstruct [:signature]

  @impl DSPEx.Program
  def forward(_prog, inputs, _opts) do
    {:ok, %{answer: inputs.question |> to_string() |> String.upcase()}}
  end
end

IO.puts("\n--- Predict (#{mode_atom} mode) ---")
predict = DSPEx.Predict.new(Demo.Signatures.QA)
{:ok, predict_out} = DSPEx.Program.forward(predict, %{question: "hi"}, mode: mode_atom)
IO.inspect(predict_out, label: "predict outputs")

IO.puts("\n--- RAG (list context + threshold) ---")
embedding_model =
  case mode_atom do
    :mock -> :mock
    _ -> System.get_env("DSPEX_EMBEDDING_MODEL") || "google:gemini-embedding-001"
  end

{:ok, rag_index} =
  DSPEx.Retrieve.Index.new(
    ["Paris is in France", "The Pacific is the largest ocean"],
    model: embedding_model
  )

rag_program = DSPEx.Predict.new(Demo.Signatures.RAG)

{:ok, rag_out} =
  DSPEx.Retrieve.RAG.run(rag_index, rag_program, "Where is Paris?",
    context_format: :list,
    threshold: 0.0,
    mode: mode_atom
  )

IO.inspect(rag_out, label: "rag outputs")

no_results =
  DSPEx.Retrieve.RAG.run(rag_index, rag_program, "Unknown?",
    context_format: :list,
    threshold: 0.99,
    mode: mode_atom
  )

IO.inspect(no_results, label: "rag no-results")

IO.puts("\n--- BootstrapFewShot compile ---")
teacher = struct(Demo.Teacher, signature: Demo.Signatures.QA)
metric = DSPEx.Metrics.exact_match(:answer)

trainset = [
  DSPEx.Example.new(%{question: "hello", answer: "HELLO"}, [:question]),
  DSPEx.Example.new(%{question: "bye", answer: "BYE"}, [:question])
]

{:ok, bfs_opt} =
  DSPEx.Teleprompter.BootstrapFewShot.compile(predict, teacher, trainset, metric,
    max_demos: 2,
    retry_delay_ms: 1,
    mode: mode_atom
  )

{:ok, bfs_out} =
  DSPEx.Program.forward(bfs_opt, %{question: "hola"},
    mode: mode_atom
  )
IO.inspect(DSPEx.OptimizedProgram.get_demos(bfs_opt), label: "bootstrap demos")
IO.inspect(DSPEx.OptimizedProgram.get_metadata(bfs_opt), label: "bootstrap metadata")
IO.inspect(bfs_out, label: "bootstrap predict")

IO.puts("\n--- GEPA compile with reflection llm ---")
reflection_llm =
  case mode_atom do
    :mock ->
      GEPA.LLM.Mock.new(responses: ["Return the exact answer."])

    _ ->
      provider =
        case String.downcase(System.get_env("GEPA_PROVIDER") || "openai") do
          "gemini" -> :gemini
          _ -> :openai
        end

      model = System.get_env("GEPA_MODEL")

      opts = if model, do: [provider: provider, model: model], else: [provider: provider]

      try do
        GEPA.LLM.ReqLLM.new(opts)
      rescue
        _ -> GEPA.LLM.Mock.new(responses: ["Return the exact answer."])
      end
  end

{:ok, gepa_opt} =
  DSPEx.Teleprompter.GEPA.compile(predict, predict, trainset, metric,
    seed_instruction: "Be concise",
    reflection_llm: reflection_llm,
    max_metric_calls: 4
  )

{:ok, gepa_out} =
  DSPEx.Program.forward(gepa_opt, %{question: "2+2?"},
    mode: mode_atom
  )

IO.inspect(DSPEx.OptimizedProgram.get_instruction(gepa_opt), label: "gepa instruction")
IO.inspect(DSPEx.OptimizedProgram.get_metadata(gepa_opt), label: "gepa metadata")
IO.inspect(gepa_out, label: "gepa predict")

IO.puts("\nDone.")
