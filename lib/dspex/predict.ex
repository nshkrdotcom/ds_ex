defmodule DSPEx.Predict do
  @moduledoc """
  Basic prediction program that routes through the adapter + client stack.
  """

  use DSPEx.Program

  @enforce_keys [:signature]
  defstruct [:signature, :client]

  @type t :: %__MODULE__{
          signature: module(),
          client: module() | nil
        }
  @type signature :: module()
  @type inputs :: map()
  @type outputs :: map()

  @doc """
  Create a new Predict program.
  """
  @spec new(signature(), keyword()) :: t()
  def new(signature, opts \\ []) do
    %__MODULE__{
      signature: signature,
      client: Keyword.get(opts, :client, DSPEx.Client)
    }
  end

  @doc """
  Convenience initializer specifying the client explicitly.
  """
  @spec new(signature(), any(), keyword()) :: t()
  def new(signature, client, opts) do
    opts_with_client = Keyword.put(opts, :client, client)
    new(signature, opts_with_client)
  end

  # DSPEx.Program behavior implementation
  @impl DSPEx.Program
  def forward(%__MODULE__{} = program, inputs, opts) do
    client = client_module(program)

    with {:ok, request} <- DSPEx.Adapter.prepare(program.signature, inputs, opts),
         {:ok, raw} <- client.request(request, opts),
         {:ok, outputs} <- DSPEx.Adapter.parse_response(program.signature, raw) do
      {:ok, outputs}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Convenience legacy entrypoint: forward with signature atom
  def forward(signature, inputs, opts) when is_atom(signature) do
    forward(new(signature), inputs, opts)
  end

  defp client_module(%__MODULE__{client: nil}), do: DSPEx.Client
  defp client_module(%__MODULE__{client: module}) when is_atom(module), do: module
end
