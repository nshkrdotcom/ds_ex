defmodule DSPEx.Test.MockProvider do
  @moduledoc """
  Enhanced mock provider for testing SIMBA optimization workflows.

  This module provides a test-focused wrapper around DSPEx.MockClientManager
  with specialized functions for SIMBA testing scenarios including bootstrap
  learning, instruction generation, and optimization workflows.
  """

  use GenServer
  alias DSPEx.{MockClientManager, Test.SimbaMockProvider}

  defstruct [:client_pid, :mode, :opts, :call_history]

  ## Public API

  @doc """
  Starts a mock provider for testing.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sets up bootstrap few-shot learning mock responses.
  """
  def setup_bootstrap_mocks(teacher_responses) do
    SimbaMockProvider.setup_bootstrap_mocks(teacher_responses)
  end

  @doc """
  Sets up instruction generation mock responses.
  """
  def setup_instruction_generation_mocks(instruction_responses) do
    SimbaMockProvider.setup_instruction_generation_mocks(instruction_responses)
  end

  @doc """
  Sets up evaluation mock responses with specific scores.
  """
  def setup_evaluation_mocks(score_map) when is_map(score_map) do
    SimbaMockProvider.setup_evaluation_mocks(score_map)
  end

  def setup_evaluation_mocks(scores) when is_list(scores) do
    # Convert list of scores to map for compatibility
    score_map =
      scores
      |> Enum.with_index()
      |> Enum.into(%{}, fn {score, index} -> {"evaluation_#{index}", score} end)

    SimbaMockProvider.setup_evaluation_mocks(score_map)
  end

  @doc """
  Sets up comprehensive SIMBA optimization workflow mocks.
  """
  def setup_simba_optimization_mocks(config) when is_list(config) do
    config_map = Enum.into(config, %{})
    SimbaMockProvider.setup_simba_optimization_mocks(config_map)
  end

  def setup_simba_optimization_mocks(config) when is_map(config) do
    SimbaMockProvider.setup_simba_optimization_mocks(config)
  end

  @doc """
  Resets all mock state.
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc """
  Gets the call history for analysis.
  """
  def get_call_history do
    GenServer.call(__MODULE__, :get_call_history)
  end

  ## GenServer Callbacks

  @impl GenServer
  def init(opts) do
    mode = Keyword.get(opts, :mode, :contextual)

    # Start a mock client for the primary provider
    {:ok, client_pid} =
      MockClientManager.start_link(:test, %{
        simulate_delays: Keyword.get(opts, :latency_simulation, false),
        failure_rate: Keyword.get(opts, :failure_rate, 0.0),
        base_delay_ms: Keyword.get(opts, :base_delay_ms, 50),
        max_delay_ms: Keyword.get(opts, :max_delay_ms, 200),
        responses: mode
      })

    state = %__MODULE__{
      client_pid: client_pid,
      mode: mode,
      opts: opts,
      call_history: []
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:mock_request, messages, opts}, _from, state) do
    start_time = System.monotonic_time()

    # Make the request to the underlying mock client manager
    response = GenServer.call(state.client_pid, {:request, messages, opts})

    end_time = System.monotonic_time()
    latency_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

    # Record in call history
    call_record = %{
      timestamp: DateTime.utc_now(),
      messages: messages,
      options: opts,
      response: response,
      latency_ms: latency_ms
    }

    new_state = %{state | call_history: [call_record | state.call_history]}

    {:reply, response, new_state}
  end

  @impl GenServer
  def handle_call(:reset, _from, state) do
    # Clear call history and reset mock responses
    SimbaMockProvider.reset_all_simba_mocks()
    MockClientManager.clear_all_mock_responses()

    new_state = %{state | call_history: []}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_call_history, _from, state) do
    # Return history in chronological order (reverse since we prepend)
    history = Enum.reverse(state.call_history)
    {:reply, history, state}
  end

  ## Private Helpers

  # Note: Helper functions for contextual response generation can be added here when needed
end
