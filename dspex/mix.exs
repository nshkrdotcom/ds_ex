defmodule Dspex.MixProject do
  use Mix.Project

  def project do
    [
      app: :dspex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

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
      # HTTP & Networking
      {:req, "~> 0.5"},
      {:fuse, "~> 2.5"},
      {:cachex, "~> 3.6"},

      # Error Handling & Resilience
      {:error_message, "~> 0.3"},
      {:external_service, "~> 1.1"},
      {:retry, "~> 0.18"},

      # Data Processing
      {:broadway, "~> 1.2"},
      {:flow, "~> 1.2"},

      # Testing & Development
      {:propcheck, "~> 1.4", only: [:test, :dev]},
      {:mox, "~> 1.1", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
