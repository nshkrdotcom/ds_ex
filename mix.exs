defmodule Dspex.MixProject do
  use Mix.Project

  @source_url "https://github.com/nshkrdotcom/ds_ex"

  def project do
    [
      app: :dspex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      elixirc_options: elixirc_options(Mix.env()),
      dialyzer: [
        plt_add_apps: [:mix],
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      preferred_cli_env: [
        "test.mock": :test,
        "test.fallback": :test,
        "test.live": :test
      ]
    ]
  end

  defp elixirc_options(:test), do: [warnings_as_errors: false]
  defp elixirc_options(_), do: []

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Dspex.Application, []},
      registered: [
        ElixirML.Process.Orchestrator,
        ElixirML.Process.SchemaRegistry,
        ElixirML.Process.VariableRegistry,
        ElixirML.Process.ResourceManager,
        ElixirML.Process.ProgramSupervisor
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Infrastructure & Observability
      {:foundation, "~> 0.1.5"},

      # HTTP & Networking - minimal resilient client
      {:req, "~> 0.5"},
      # {:fuse, "~> 2.5"}, # Removed - provided by Foundation
      {:cachex, "~> 3.6"},
      {:external_service, "~> 1.1"},
      {:retry, "~> 0.18"},

      # Structured outputs / validation
      {:sinter, github: "nshkrdotcom/sinter"},
      {:json_remedy, "~> 0.1.11"},

      # LLM + embeddings
      {:req_llm, "~> 1.0"},

      # Testing & Development
      {:propcheck, "~> 1.4", only: [:test, :dev]},
      {:stream_data, "~> 1.2", only: [:test, :dev]},
      {:mox, "~> 1.1", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.0", only: :dev, runtime: false},

      # Optimization
      {:gepa_ex, "~> 0.1.2"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
