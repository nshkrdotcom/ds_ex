defmodule Dspex.MixProject do
  use Mix.Project

  def project do
    [
      app: :dspex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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
      mod: {Dspex.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Infrastructure & Observability
      {:foundation, "~> 0.1.5"},

      # Core - JSON serialization (jason already included in foundation)
      # {:jason, "~> 1.4"}, # Removed - provided by Foundation

      # HTTP & Networking - minimal resilient client
      {:req, "~> 0.5"},
      # {:fuse, "~> 2.5"}, # Removed - provided by Foundation
      {:cachex, "~> 3.6"},
      {:external_service, "~> 1.1"},
      {:retry, "~> 0.18"},

      # Structured outputs
      {:instructor_lite, "~> 0.3.0"},
      {:sinter, github: "nshkrdotcom/sinter"},

      # Testing & Development
      {:propcheck, "~> 1.4", only: [:test, :dev]},
      {:mox, "~> 1.1", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
