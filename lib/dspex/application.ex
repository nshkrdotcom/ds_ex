defmodule Dspex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # DSPEx-specific services (Foundation starts automatically)
      {DSPEx.Services.ConfigManager, []},
      {DSPEx.Services.TelemetrySetup, []},

      # HTTP client pool for external API calls
      {Finch, name: DSPEx.Finch}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dspex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
