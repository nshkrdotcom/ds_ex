defmodule Dspex do
  @moduledoc """
  Entry point module for the DSPEx (Declarative Self-improving Programs in Elixir) library.

  DSPEx is an Elixir implementation of the DSPy (Declarative Self-improving Language Programs)
  framework for building and optimizing language model programs through declarative signatures,
  automatic optimization, and structured prompting.

  ## Key Features

  - **Declarative Signatures**: Define program interfaces through signature specifications
  - **Automatic Optimization**: Use teleprompter modules to optimize program performance
  - **Structured Examples**: Work with typed input/output examples
  - **Client Management**: Unified interface for various language model providers
  - **Testing Framework**: Comprehensive testing and evaluation tools

  ## Quick Start

      # Define a signature
      defmodule QASignature do
        use DSPEx.Signature, "question -> answer"
      end

      # Create a program
      program = DSPEx.Predict.new(QASignature, client: my_client)

      # Execute with inputs
      {:ok, result} = DSPEx.Program.forward(program, %{question: "What is 2+2?"})

  For detailed documentation, see the individual modules:
  - `DSPEx.Signature` - Define program interfaces
  - `DSPEx.Program` - Core program execution
  - `DSPEx.Example` - Data structures for examples
  - `DSPEx.Teleprompter` - Program optimization
  """

  @doc """
  Returns a greeting atom for basic library verification.

  This function is primarily used for testing the library installation
  and basic functionality.

  ## Returns

  The atom `:world`

  ## Examples

      iex> Dspex.hello()
      :world

  """
  @spec hello() :: :world
  def hello do
    :world
  end
end
