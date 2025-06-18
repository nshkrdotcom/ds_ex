defmodule DSPEx.MockHelpers do
  @moduledoc """
  Comprehensive mock helpers for DSPEx integration tests.

  This module provides a robust, contamination-free approach to testing that
  supports both mock and live API testing without global state pollution.

  ## Key Features

  - **Zero Global State Contamination**: No modification of System environment variables
  - **Clean Mock/Live Separation**: Explicit client types with isolated behavior
  - **Transparent Logging**: Clear indication of what's actually being tested
  - **State Validation**: Detection and prevention of environment contamination
  - **Unified Interface**: Consistent API regardless of client type

  ## Usage

      # Adaptive client setup - uses real API if available, mock otherwise
      {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)

      # Always returns mock client for deterministic testing
      {client_type, client} = MockHelpers.setup_mock_client(:gemini)

      # Force live client (fails if no API key)
      {client_type, client} = MockHelpers.setup_live_client(:gemini)

  ## Design Principles

  1. **Explicit Over Implicit**: Client types are clearly indicated
  2. **Fail Fast**: Environment contamination is detected immediately
  3. **Process Isolation**: Each test gets isolated client instances
  4. **Transparent Behavior**: Logging clearly shows what's being tested
  """

  require Logger

  @doc """
  Validates that the test environment is clean and uncontaminated.

  This function checks for evidence of state pollution from previous tests
  and raises an error if contamination is detected.
  """
  def validate_clean_environment!(provider \\ :gemini) do
    env_var = get_env_var_name(provider)
    current_value = System.get_env(env_var)

    case current_value do
      "mock-api-key-for-testing-persistent" ->
        raise """
        CRITICAL: Test environment contaminated!

        Mock API key found in global state: #{env_var}
        Value: #{inspect(current_value)}

        This indicates state pollution from previous tests. The test suite
        has been compromised and cannot provide reliable results.

        Resolution: Restart the test suite with a clean environment.
        """

      value when is_binary(value) and byte_size(value) > 0 ->
        # There's a real API key, which is fine
        :ok

      _ ->
        # No API key set, which is also fine
        :ok
    end
  end

  @doc """
  Sets up an adaptive client that uses real API when available, mock otherwise.

  This is the primary function for most integration tests. It provides
  automatic fallback to mock mode when API keys are not available while
  maintaining complete isolation from global state.

  ## Returns

  - `{:real, client_pid}` - Real ClientManager with live API integration
  - `{:mock, client_pid}` - MockClientManager with isolated mock behavior

  ## Examples

      # Basic adaptive setup
      {client_type, client} = setup_adaptive_client(:gemini)

      # Use the client through unified interface
      result = unified_request({client_type, client}, messages, opts)
  """
  def setup_adaptive_client(provider \\ :gemini) do
    alias DSPEx.TestModeConfig

    # First validate that environment is clean
    validate_clean_environment!(provider)

    case TestModeConfig.get_test_mode() do
      :mock ->
        # Pure mock mode - never attempt live API
        setup_isolated_mock_client(provider, %{mode_reason: "pure_mock_mode"})

      :fallback ->
        # Fallback mode - try live, fall back to mock
        if has_real_api_key?(provider) do
          setup_live_client(provider)
        else
          setup_isolated_mock_client(provider, %{mode_reason: "no_api_key_fallback"})
        end

      :live ->
        # Live mode - require API keys, fail if not available
        if has_real_api_key?(provider) do
          setup_live_client(provider)
        else
          raise RuntimeError, """
          Live API mode requires valid API keys but none found for #{provider}.

          Options:
          1. Set API key: export #{get_env_var_name(provider)}=your_key
          2. Use fallback mode: DSPEX_TEST_MODE=fallback mix test
          3. Use mock mode: DSPEX_TEST_MODE=mock mix test (or just: mix test)
          """
        end
    end
  end

  @doc """
  Forces setup of a live client with real API integration.

  This function will fail if no valid API key is available. Use this
  for tests that specifically need to validate live API integration.

  ## Returns

  - `{:real, client_pid}` - Real ClientManager process
  - Raises error if no API key available
  """
  def setup_live_client(provider \\ :gemini) do
    validate_clean_environment!(provider)

    unless has_real_api_key?(provider) do
      raise """
      Cannot setup live client for #{provider}: No API key available.

      To test live API integration, set the appropriate environment variable:
      - GEMINI_API_KEY for :gemini
      - OPENAI_API_KEY for :openai
      - ANTHROPIC_API_KEY for :anthropic
      """
    end

    api_key = System.get_env(get_env_var_name(provider))
    key_preview = mask_api_key(api_key)

    log_client_setup(provider, :real, %{key_preview: key_preview})

    {:ok, client} = DSPEx.ClientManager.start_link(provider)
    {:real, client}
  end

  @doc """
  Always sets up an isolated mock client for deterministic testing.

  This function creates a dedicated MockClientManager that provides
  realistic behavior without making any network calls or modifying
  global state.

  ## Options

  - `:simulate_delays` - Add realistic response delays (default: false)
  - `:failure_rate` - Fraction of requests that should fail (default: 0.0)
  - `:responses` - Response strategy (:contextual, :fixed, or list)

  ## Returns

  - `{:mock, client_pid}` - MockClientManager process
  """
  def setup_isolated_mock_client(provider \\ :gemini, opts \\ %{}) do
    validate_clean_environment!(provider)

    log_client_setup(provider, :mock, opts)

    {:ok, client} = DSPEx.MockClientManager.start_link(provider, opts)
    {:mock, client}
  end

  # Convenience alias for common usage
  def setup_mock_client(provider \\ :gemini, opts \\ %{}) do
    setup_isolated_mock_client(provider, opts)
  end

  @doc """
  Checks if a real (non-mock) API key is available for the provider.

  This function is contamination-aware and will return false for
  mock keys that may have been set by broken test infrastructure.
  """
  def has_real_api_key?(provider) do
    env_var = get_env_var_name(provider)

    case System.get_env(env_var) do
      nil ->
        false

      "" ->
        false

      "mock-api-key-for-testing-persistent" ->
        # Explicitly reject contaminated mock keys
        false

      value when is_binary(value) and byte_size(value) > 0 ->
        true

      _ ->
        false
    end
  end

  # Legacy compatibility - use has_real_api_key? instead
  def api_key_available?(provider), do: has_real_api_key?(provider)

  @doc """
  Unified request function that works transparently with both client types.

  Provides a consistent interface regardless of whether the client is
  mock or real, allowing tests to be written once and work in both modes.
  """
  def unified_request(client_tuple, messages, opts \\ %{})

  def unified_request({:real, client}, messages, opts) do
    DSPEx.ClientManager.request(client, messages, opts)
  end

  def unified_request({:mock, client}, messages, opts) do
    DSPEx.MockClientManager.request(client, messages, opts)
  end

  @doc """
  Unified stats function that works with both client types.
  """
  def unified_get_stats({:real, client}) do
    DSPEx.ClientManager.get_stats(client)
  end

  def unified_get_stats({:mock, client}) do
    DSPEx.MockClientManager.get_stats(client)
  end

  @doc """
  Check if client process is alive (works for both types).
  """
  def client_alive?({_type, client}) when is_pid(client) do
    Process.alive?(client)
  end

  def client_alive?(_), do: false

  @doc """
  Extract the actual client PID for direct API calls.
  """
  def extract_client({_type, client}), do: client

  @doc """
  Determines the client type from a client tuple.
  """
  def client_type({type, _client}), do: type

  @doc """
  Comprehensive test helper that validates environment and sets up client.

  This is the recommended helper for most integration tests as it provides
  complete validation and clear error reporting.
  """
  def setup_test_client(provider \\ :gemini, opts \\ %{}) do
    # Validate environment is clean
    validate_clean_environment!(provider)

    # Force mock if specifically requested
    if opts[:force_mock] do
      setup_isolated_mock_client(provider, opts)
    else
      setup_adaptive_client(provider)
    end
  end

  ## Private Implementation

  defp get_env_var_name(provider) do
    case provider do
      :gemini -> "GEMINI_API_KEY"
      :openai -> "OPENAI_API_KEY"
      :anthropic -> "ANTHROPIC_API_KEY"
      _ -> "UNKNOWN_API_KEY"
    end
  end

  defp mask_api_key(api_key) when is_binary(api_key) and byte_size(api_key) >= 4 do
    String.slice(api_key, 0, 4) <> "***"
  end

  defp mask_api_key(_), do: "***"

  defp log_client_setup(provider, :real, %{key_preview: key_preview}) do
    IO.puts("""

    🟢 [LIVE API] Testing #{provider} with REAL API integration
       API Key: #{key_preview}
       Mode: Actual network requests to live API endpoints
       Impact: Tests validate real API integration and behavior
    """)
  end

  defp log_client_setup(provider, :mock, opts) do
    alias DSPEx.TestModeConfig

    {emoji, mode_text} =
      case TestModeConfig.get_test_mode() do
        :mock -> {"🟦", "PURE MOCK"}
        _ -> {"🟡", "MOCK MODE"}
      end

    mode_reason =
      case Map.get(opts, :mode_reason) do
        "pure_mock_mode" -> " (pure mock mode active)"
        "no_api_key_fallback" -> " (fallback: no API key)"
        _ -> ""
      end

    opts_desc =
      if map_size(Map.delete(opts, :mode_reason)) > 0 do
        " with #{format_mock_opts(Map.delete(opts, :mode_reason))}"
      else
        ""
      end

    IO.puts("""

    #{emoji} [#{mode_text}] Testing #{provider} with ISOLATED mock client#{mode_reason}#{opts_desc}
       API Key: Not required (mock mode)
       Mode: No network requests - deterministic mock responses
       Impact: Tests validate integration logic without API dependencies
    """)
  end

  defp format_mock_opts(opts) do
    Enum.map_join(opts, ", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
  end

  ## Test Utilities

  @doc """
  Creates contextual mock responses for common test scenarios.
  """
  def create_contextual_responses do
    [
      # Math responses - in correct API format
      # For "2+2" questions
      {:ok, %{choices: [%{message: %{role: "assistant", content: "4"}}]}},
      # For general math questions
      {:ok, %{choices: [%{message: %{role: "assistant", content: "42"}}]}},

      # Geography responses
      # For capital questions
      {:ok, %{choices: [%{message: %{role: "assistant", content: "Paris"}}]}},

      # General test responses
      {:ok, %{choices: [%{message: %{role: "assistant", content: "Mock response for testing"}}]}},
      {:ok,
       %{choices: [%{message: %{role: "assistant", content: "Integration test mock response"}}]}},

      # Error scenarios for robustness testing
      {:error, :network_error},
      {:error, :api_error},
      {:error, :timeout},

      # Recovery responses
      {:ok, %{choices: [%{message: %{role: "assistant", content: "Recovered mock response"}}]}}
    ]
  end

  @doc """
  Creates mock responses that match specific patterns for predictable testing.
  """
  def create_pattern_responses(patterns) when is_map(patterns) do
    Enum.map(patterns, fn {pattern, response} ->
      {:pattern, pattern, response}
    end)
  end

  @doc """
  Test helper macro for writing adaptive tests that work in both modes.
  """
  defmacro adaptive_test(description, provider \\ :gemini, do: block) do
    quote do
      test unquote("#{description} (adaptive: mock/live)") do
        {client_type, client} = DSPEx.MockHelpers.setup_adaptive_client(unquote(provider))

        # Make client type and client available in test scope
        var!(client_type) = client_type
        var!(client) = client
        var!(adaptive_client) = {client_type, client}

        unquote(block)
      end
    end
  end

  @doc """
  Test helper macro for mock-only tests.
  """
  defmacro mock_test(description, provider \\ :gemini, opts \\ quote(do: %{}), do: block) do
    quote do
      test unquote("#{description} (mock only)") do
        {client_type, client} =
          DSPEx.MockHelpers.setup_mock_client(
            unquote(provider),
            unquote(opts)
          )

        # Ensure we got a mock client
        assert client_type == :mock

        # Make available in test scope
        var!(client_type) = client_type
        var!(client) = client
        var!(mock_client) = {client_type, client}

        unquote(block)
      end
    end
  end

  @doc """
  Test helper macro for live-only tests (skips if no API key).
  """
  defmacro live_test(description, provider \\ :gemini, do: block) do
    quote do
      test unquote("#{description} (live API only)") do
        case DSPEx.MockHelpers.has_real_api_key?(unquote(provider)) do
          false ->
            # Skip test if no API key available
            IO.puts(
              "Skipping live test: #{unquote(description)} (no #{unquote(provider)} API key)"
            )

            :skip

          true ->
            {client_type, client} = DSPEx.MockHelpers.setup_live_client(unquote(provider))

            # Ensure we got a live client
            assert client_type == :real

            # Make available in test scope
            var!(client_type) = client_type
            var!(client) = client
            var!(live_client) = {client_type, client}

            unquote(block)
        end
      end
    end
  end

  ## Validation and Debugging Utilities

  @doc """
  Comprehensive environment diagnostic for debugging contamination issues.
  """
  def diagnose_environment do
    providers = [:gemini, :openai, :anthropic]

    IO.puts("\n=== DSPEx Test Environment Diagnostic ===")

    Enum.each(providers, fn provider ->
      env_var = get_env_var_name(provider)
      value = System.get_env(env_var)

      status =
        case value do
          nil -> "✅ Clean (no key set)"
          "" -> "✅ Clean (empty key)"
          "mock-api-key-for-testing-persistent" -> "❌ CONTAMINATED (mock key detected)"
          key when is_binary(key) -> "🟢 Live key available (#{mask_api_key(key)})"
          _ -> "⚠️  Unknown state"
        end

      IO.puts("#{provider}: #{env_var} = #{status}")
    end)

    IO.puts("==========================================\n")
  end

  @doc """
  Resets test environment by clearing any contaminated state.

  WARNING: This should only be used in test cleanup, never in production.
  """
  def reset_test_environment! do
    providers = [:gemini, :openai, :anthropic]

    Enum.each(providers, fn provider ->
      env_var = get_env_var_name(provider)
      current_value = System.get_env(env_var)

      case current_value do
        "mock-api-key-for-testing-persistent" ->
          System.delete_env(env_var)
          IO.puts("Cleared contaminated mock key for #{provider}")

        _ ->
          # Leave real API keys alone
          :ok
      end
    end)
  end
end
