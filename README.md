# DSPEx – Supported Vertical Slice

> Status: BEACON and SIMBA teleprompters are **not implemented**. Legacy references are for planning only.

This repo hosts a minimal, working slice of DSPEx inspired by DSPy. It focuses on signatures, adapter/client wiring, retrieval, two teleprompters (BootstrapFewShot and GEPA), and evaluation helpers. For a fuller walkthrough see `docs/20251207/VERTICAL_SLICE.md`.

## What Works Now

- **Signatures + Adapter**: `use DSPEx.Signature`, Sinter-backed validation, `json_remedy` repair, list contexts JSON-encoded for validation/prompting.
- **Client + Predict**: ReqLLM wrapper with `:mock`/`:live`/`:fallback` modes, `llm_module` injection, mock embeddings (`dimensions`, `mock_embedding`), and normalization of object/content responses.
- **Retrieval/RAG**: In-memory embeddings, `Retrieve.Index`, `Retrieve.RAG` helper with thresholding and string/list context formatting, plus `Retrieve.RAGHelpers` for one-shot runs.
- **Teleprompters**: `BootstrapFewShot` (retries, `max_demos`, `quality_threshold`, metadata for skipped reasons/attempts) and `GEPA` (seed instruction, `max_metric_calls`, `reflection_llm`, best score metadata).
- **Evaluation/Metrics**: Metrics helpers (`exact_match`, `contains`, `f1_boolean`, `f1_tokens`, `rouge1_overlap`) and `DSPEx.Evaluate.run/4` with `scores_only`, `return_scores`, `return_failures`.

## Quickstart (mock by default)

```elixir
defmodule QASig do
  use DSPEx.Signature, "question -> answer"
end

program = DSPEx.Predict.new(QASig)
{:ok, outputs} = DSPEx.Program.forward(program, %{question: "hi"})
# %{answer: "mock_answer"}
```

### RAG

```elixir
defmodule RAGSig do
  use DSPEx.Signature, "question, context -> answer"
end

{:ok, index} = DSPEx.Retrieve.Index.new(["Paris is in France"], model: :mock)
program = DSPEx.Predict.new(RAGSig)

{:ok, outputs} =
  DSPEx.Retrieve.RAG.run(index, program, "Where is Paris?",
    context_format: :list,
    threshold: 0.0
  )

# When everything is filtered out:
assert {:error, :no_results} ==
         DSPEx.Retrieve.RAG.run(index, program, "?", context_format: :list, threshold: 9.9)
```

### BootstrapFewShot

```elixir
defmodule Teacher do
  use DSPEx.Program
  defstruct [:signature]
  @impl DSPEx.Program
  def forward(_p, inputs, _opts), do: {:ok, %{answer: String.upcase(inputs.question)}}
end

student = DSPEx.Predict.new(QASig)
teacher = %Teacher{signature: QASig}
metric = DSPEx.Metrics.exact_match(:answer)
trainset = [DSPEx.Example.new(%{question: "hi", answer: "HI"}, [:question])]

{:ok, optimized} =
  DSPEx.Teleprompter.BootstrapFewShot.compile(student, teacher, trainset, metric,
    max_demos: 1,
    max_attempts: 2,
    retry_delay_ms: 1
  )

meta = DSPEx.OptimizedProgram.get_metadata(optimized)
# meta.skipped -> reasons like {:teacher_error, reason} | {:metric_error, error} | :below_threshold
# meta.total_attempts -> teacher calls (including retries)
# meta.demo_count -> selected demos after truncation
```

### GEPA

```elixir
metric = DSPEx.Metrics.exact_match(:answer)
examples = [DSPEx.Example.new(%{question: "2+2?", answer: "4"}, [:question])]

{:ok, optimized} =
  DSPEx.Teleprompter.GEPA.compile(student, teacher, examples, metric,
    seed_instruction: "Be concise",
    reflection_llm: GEPA.LLM.Mock.new(responses: ["Return just the number"]),
    max_metric_calls: 5
  )

DSPEx.OptimizedProgram.get_instruction(optimized)
# metadata.teleprompter == :gepa
# metadata.score / metadata.best_score -> best validation score
# metadata.total_metric_calls -> observed metric calls (bounded by max_metric_calls + 1 for minibatches)
```

### Full-stack example

- Run `mix run examples/full_stack_demo.exs` to see predict-only, RAG with list context + threshold/no-results, BootstrapFewShot compilation, and GEPA compilation with a custom reflection LLM in mock mode.

## Modes and Testing

- Default mode is `:mock`. Override via `DSPEX_TEST_MODE=live|fallback` or `mode:` option on client-facing calls.
- `:fallback` tries live ReqLLM calls first and falls back to mock on errors; `:live` requires keys.
- Inject custom providers with `llm_module:`. Embeddings respect `dimensions`/`mock_embedding` in mock mode.
- `mix test` runs everything in mock mode; see `docs/20251207/VERTICAL_SLICE.md` for flow coverage.

## Out of Scope (until rebuilt)

- BEACON teleprompter
- SIMBA teleprompter
- Scout/Optuna and other DSPy teleprompters
- Legacy SIMBA/BEACON planning docs live under `docs/_legacy/` for reference only

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
