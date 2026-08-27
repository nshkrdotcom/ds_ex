# DSPEx Vertical Slice (Supported Stack) — 2025-12-07

This is the **minimal, supported vertical slice** of DSPEx. Anything outside this path (e.g., BEACON, SIMBA, Scout/Optuna) is out of scope until rebuilt with real code and tests.

## Stack Overview

- **Signatures + Adapter**: Define shapes with `use DSPEx.Signature`; `DSPEx.Adapter` validates inputs/outputs via Sinter, normalizes list contexts (JSON-encodes), and repairs malformed JSON with `json_remedy`.
- **Client + Predict**: `DSPEx.Client` wraps ReqLLM with modes `:mock` (default), `:live`, `:fallback`; supports `llm_module` injection and mock embeddings (`dimensions`, `mock_embedding`). `DSPEx.Predict` wires Adapter → Client → Adapter.parse.
- **Retrieval/RAG**: `DSPEx.Retrieve.Embeddings`, in-memory `Retrieve.Index`, and `Retrieve.RAG` helper with thresholding and string/list context formats; `Retrieve.RAGHelpers` builds an index from docs for one-off runs.
- **Teleprompters**: `BootstrapFewShot` generates demos with retries/backoff and metadata (`skipped`, `total_attempts`, `demo_count`). `GEPA` delegates to `gepa_ex`, respects `seed_instruction`, `max_metric_calls`, `reflection_llm`, and surfaces `teleprompter: :gepa` + best scores/`total_metric_calls` in metadata while pushing instruction overrides into `OptimizedProgram`.
- **Evaluation/Metrics**: Metrics helpers (`exact_match`, `contains`, `f1_boolean`, `f1_tokens`, `rouge1_overlap`); `DSPEx.Evaluate.run/4` concurrent executor with `return_scores`, `scores_only`, `return_failures`.

## Modes (mock/live/fallback)

- Default mode is `:mock` (`DSPEX_TEST_MODE` env or `mode:` option overrides). `:fallback` tries live then falls back to mock on errors.
- Inject custom LLMs via `llm_module:`; mock embeddings configurable with `dimensions`/`mock_embedding`.
- Retrieval uses the same mock embeddings; zero vectors are tolerated in similarity scoring.

## Examples

### Predict (mock by default)

```elixir
defmodule QASig do
  use DSPEx.Signature, "question -> answer"
end

program = DSPEx.Predict.new(QASig)
{:ok, outputs} = DSPEx.Program.forward(program, %{question: "hi"})
# => %{answer: "mock_answer"}
```

### RAG (list context + threshold)

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

# If all matches are filtered out:
assert {:error, :no_results} ==
         DSPEx.Retrieve.RAG.run(index, program, "?", context_format: :list, threshold: 9.9)
```

### BootstrapFewShot flow

```elixir
defmodule QASig do
  use DSPEx.Signature, "question -> answer"
end

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
# meta.skipped -> [%{reason: {:teacher_error, reason} | {:metric_error, error} | :below_threshold, ...}]
# meta.total_attempts -> total teacher calls (including retries)
# meta.demo_count -> selected demos after truncation
```

### GEPA flow

```elixir
defmodule QASig do
  use DSPEx.Signature, "question -> answer"
end

student = DSPEx.Predict.new(QASig)
metric = DSPEx.Metrics.exact_match(:answer)
examples = [DSPEx.Example.new(%{question: "2+2?", answer: "4"}, [:question])]

{:ok, optimized} =
  DSPEx.Teleprompter.GEPA.compile(student, student, examples, metric,
    seed_instruction: "Be concise",
    reflection_llm: GEPA.LLM.Mock.new(responses: ["Return just the number"]),
    max_metric_calls: 5
  )

instruction = DSPEx.OptimizedProgram.get_instruction(optimized)
meta = DSPEx.OptimizedProgram.get_metadata(optimized)
# meta.teleprompter == :gepa
# meta.best_score / meta.score -> best validation score seen
# meta.total_metric_calls -> how many metric calls GEPA made (bounded by max_metric_calls + 1 for minibatches)
# instruction is pushed into the optimized program for downstream Predict/RAG calls
```

### Full-stack walkthrough (mock mode)

Run `mix run examples/full_stack_demo.exs` to see a stitched flow:

- Predict-only Q&A in mock mode.
- Build an in-memory RAG index, query with list context + threshold, and see the `{:error, :no_results}` path.
- Compile `BootstrapFewShot`, inspect `demo_count`/`skipped` metadata, and use the optimized program for prediction.
- Compile `GEPA` with a mock reflection LLM, check `best_score`/`total_metric_calls`, and forward with the instruction override.

## Evaluation & Failure Handling

- `DSPEx.Evaluate.run/4` returns `%{score, stats}` by default. Options:
  - `scores_only: true` → `%{scores: [...]}` (no stats)
  - `return_scores: true` → includes raw scores alongside stats
  - `return_failures: true` → adds `:failures` entries for invalid scores, `{:error, reason}`, or `{:exit, reason}` (including timeouts)
- `DSPEx.Retrieve.RAG.run/4` returns `{:error, :no_results}` when nothing passes the threshold.
- Teleprompter metadata records skip reasons so failures are auditable.

## Out of Scope (until rebuilt)

- BEACON teleprompter
- SIMBA teleprompter
- Scout/Optuna integrations and other DSPy teleprompters
- Legacy SIMBA/BEACON planning docs are archived under `docs/_legacy/`
