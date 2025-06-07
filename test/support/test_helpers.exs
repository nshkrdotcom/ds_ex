defmodule DSPEx.TestHelpers do
  @moduledoc "Common test utilities for DSPEx tests"

  def create_mock_client(responses) when is_list(responses) do
    Agent.start_link(fn -> responses end)
  end

  def mock_client_request(agent, _request) do
    case Agent.get_and_update(agent, fn
           [response | rest] -> {response, rest}
           [] -> {{:error, :no_more_responses}, []}
         end) do
      {:ok, response} -> {:ok, response}
      error -> error
    end
  end

  def assert_signature_equivalent(sig1, sig2) do
    assert sig1.input_fields() == sig2.input_fields()
    assert sig1.output_fields() == sig2.output_fields()
    assert sig1.fields() == sig2.fields()
  end

  def create_test_examples(count \\ 5) do
    for i <- 1..count do
      DSPEx.Example.new(%{
        question: "Question #{i}?",
        answer: "Answer #{i}",
        confidence: Enum.random(["high", "medium", "low"]),
        metadata: %{id: i, created_at: DateTime.utc_now()}
      })
    end
  end

  def wait_for_condition(condition_fn, timeout \\ 1000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_condition_loop(condition_fn, end_time)
  end

  defp wait_for_condition_loop(condition_fn, end_time) do
    if condition_fn.() do
      true
    else
      if System.monotonic_time(:millisecond) < end_time do
        Process.sleep(10)
        wait_for_condition_loop(condition_fn, end_time)
      else
        false
      end
    end
  end

  def capture_logs(fun) do
    ExUnit.CaptureLog.capture_log(fun)
  end

  def temporary_config(config_changes, fun) do
    original_config = Application.get_all_env(:dspex)

    try do
      Enum.each(config_changes, fn {key, value} ->
        Application.put_env(:dspex, key, value)
      end)

      fun.()
    after
      Application.put_all_env([{:dspex, original_config}])
    end
  end
end
