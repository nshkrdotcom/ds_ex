defmodule DspexDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :dspex_demo,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {DspexDemo.Application, []}
    ]
  end

  defp deps do
    [
      # Use DSPEx as dependency (relative path since it's two levels higher)
      {:dspex, path: "../../"}
    ]
  end
end
