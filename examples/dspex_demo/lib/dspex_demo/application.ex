defmodule DspexDemo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start HTTP client pool
      {Finch, name: DspexDemo.Finch}
    ]

    opts = [strategy: :one_for_one, name: DspexDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end