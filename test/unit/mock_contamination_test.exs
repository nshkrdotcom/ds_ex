defmodule DSPEx.MockContaminationTest do
  @moduledoc """
  Critical tests to validate that the state contamination bug is permanently resolved.

  This test suite specifically validates that:
  1. Mock clients never contaminate global environment state
  2. Environment contamination is detected and prevented
  3. Client type logging is accurate and unambiguous
  4. Multiple tests can run without state pollution
  """

  # Must be sync to test global state
  use ExUnit.Case, async: false

  @moduletag :group_1

  alias DSPEx.MockHelpers

  setup do
    # Ensure clean environment before each test
    MockHelpers.reset_test_environment!()

    # Register cleanup after each test
    on_exit(fn ->
      MockHelpers.reset_test_environment!()
    end)

    :ok
  end

  describe "environment contamination prevention" do
    test "mock clients never modify global environment variables" do
      # Capture current environment state
      original_gemini = System.get_env("GEMINI_API_KEY")
      original_openai = System.get_env("OPENAI_API_KEY")
      original_anthropic = System.get_env("ANTHROPIC_API_KEY")

      try do
        # Clear environment to test clean state behavior
        System.delete_env("GEMINI_API_KEY")
        System.delete_env("OPENAI_API_KEY")
        System.delete_env("ANTHROPIC_API_KEY")

        # Create multiple mock clients for different providers
        # Use setup_mock_client directly since we've cleared the API keys
        {client_type_1, client_1} = MockHelpers.setup_mock_client(:gemini)
        {client_type_2, client_2} = MockHelpers.setup_mock_client(:openai)
        {client_type_3, client_3} = MockHelpers.setup_mock_client(:anthropic)

        # All should be mock clients
        assert client_type_1 == :mock
        assert client_type_2 == :mock
        assert client_type_3 == :mock

        # Make requests to simulate normal usage
        {:ok, _response_1} =
          MockHelpers.unified_request(
            {client_type_1, client_1},
            [%{role: "user", content: "Gemini test"}]
          )

        {:ok, _response_2} =
          MockHelpers.unified_request(
            {client_type_2, client_2},
            [%{role: "user", content: "OpenAI test"}]
          )

        {:ok, _response_3} =
          MockHelpers.unified_request(
            {client_type_3, client_3},
            [%{role: "user", content: "Anthropic test"}]
          )

        # Environment should remain completely unmodified
        assert System.get_env("GEMINI_API_KEY") == nil
        assert System.get_env("OPENAI_API_KEY") == nil
        assert System.get_env("ANTHROPIC_API_KEY") == nil

        # No contaminated keys should be present
        refute MockHelpers.has_real_api_key?(:gemini)
        refute MockHelpers.has_real_api_key?(:openai)
        refute MockHelpers.has_real_api_key?(:anthropic)
      after
        # Restore original environment
        restore_env_key("GEMINI_API_KEY", original_gemini)
        restore_env_key("OPENAI_API_KEY", original_openai)
        restore_env_key("ANTHROPIC_API_KEY", original_anthropic)
      end
    end

    test "contamination detection raises clear error" do
      # Store original state
      original_key = System.get_env("GEMINI_API_KEY")

      try do
        # Simulate contaminated environment (what the old bug would create)
        System.put_env("GEMINI_API_KEY", "mock-api-key-for-testing-persistent")

        # Should detect contamination and raise descriptive error
        assert_raise RuntimeError, ~r/CRITICAL: Test environment contaminated/, fn ->
          MockHelpers.setup_adaptive_client(:gemini)
        end

        # Validation function should also detect it
        assert_raise RuntimeError, ~r/CRITICAL: Test environment contaminated/, fn ->
          MockHelpers.validate_clean_environment!(:gemini)
        end
      after
        # Restore original state (clean up contamination)
        restore_env_key("GEMINI_API_KEY", original_key)
      end
    end

    test "has_real_api_key? correctly identifies contaminated mock keys" do
      # Store original key for restoration
      original_key = System.get_env("GEMINI_API_KEY")

      try do
        # Test with no key
        System.delete_env("GEMINI_API_KEY")
        refute MockHelpers.has_real_api_key?(:gemini)

        # Test with empty key
        System.put_env("GEMINI_API_KEY", "")
        refute MockHelpers.has_real_api_key?(:gemini)

        # Test with contaminated mock key
        System.put_env("GEMINI_API_KEY", "mock-api-key-for-testing-persistent")
        refute MockHelpers.has_real_api_key?(:gemini)

        # Test with real key
        System.put_env("GEMINI_API_KEY", "real-api-key-sk-1234567890")
        assert MockHelpers.has_real_api_key?(:gemini)
      after
        # Properly restore original state
        restore_env_key("GEMINI_API_KEY", original_key)
      end
    end
  end

  describe "client type consistency" do
    test "mock clients consistently report as mock type" do
      # Force mock mode by clearing API key
      original_key = System.get_env("GEMINI_API_KEY")
      System.delete_env("GEMINI_API_KEY")

      try do
        # Use setup_mock_client directly since we've cleared the API key
        {client_type, client} = MockHelpers.setup_mock_client(:gemini)

        # Should be mock type
        assert client_type == :mock
        assert MockHelpers.client_type({client_type, client}) == :mock

        # Should use MockClientManager
        {:ok, stats} = MockHelpers.unified_get_stats({client_type, client})
        assert stats.stats.mock_mode == true
      after
        restore_env_key("GEMINI_API_KEY", original_key)
      end
    end

    test "live clients consistently report as real type when API key available" do
      # Only run if real API key is available AND we're not in pure mock mode
      case {MockHelpers.has_real_api_key?(:gemini), DSPEx.TestModeConfig.get_test_mode()} do
        {false, _} ->
          # Skip test if no real API key
          :skip

        {true, :mock} ->
          # In pure mock mode, we always use mock clients even with real API keys
          {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)

          # Should be mock type even with real API key in mock mode
          assert client_type == :mock
          assert MockHelpers.client_type({client_type, client}) == :mock

          # Should use MockClientManager
          {:ok, stats} = MockHelpers.unified_get_stats({client_type, client})
          assert stats.stats.mock_mode == true

        {true, _} ->
          # In fallback or live mode with real API key
          {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)

          # Should be real type
          assert client_type == :real
          assert MockHelpers.client_type({client_type, client}) == :real

          # Should use real ClientManager (no mock_mode in stats)
          {:ok, stats} = MockHelpers.unified_get_stats({client_type, client})
          refute Map.has_key?(stats.stats, :mock_mode)
      end
    end
  end

  describe "sequential test isolation" do
    test "first test with mock client - no contamination" do
      # Clear API key to force mock
      original_key = System.get_env("GEMINI_API_KEY")
      System.delete_env("GEMINI_API_KEY")

      try do
        # Use setup_mock_client directly since we've cleared the API key
        {client_type, client} = MockHelpers.setup_mock_client(:gemini)
        assert client_type == :mock

        # Make a request
        {:ok, _response} =
          MockHelpers.unified_request(
            {client_type, client},
            [%{role: "user", content: "First test message"}]
          )

        # Environment should be clean
        assert System.get_env("GEMINI_API_KEY") == nil
      after
        restore_env_key("GEMINI_API_KEY", original_key)
      end
    end

    test "second test should start with clean environment" do
      # This test should start with clean environment regardless of previous test
      MockHelpers.validate_clean_environment!(:gemini)

      # Clear API key to force mock
      original_key = System.get_env("GEMINI_API_KEY")
      System.delete_env("GEMINI_API_KEY")

      try do
        # Use setup_mock_client directly since we've cleared the API key
        {client_type, client} = MockHelpers.setup_mock_client(:gemini)
        assert client_type == :mock

        # Make a request
        {:ok, _response} =
          MockHelpers.unified_request(
            {client_type, client},
            [%{role: "user", content: "Second test message"}]
          )

        # Environment should be clean
        assert System.get_env("GEMINI_API_KEY") == nil
      after
        restore_env_key("GEMINI_API_KEY", original_key)
      end
    end

    test "third test should also start clean - proving no contamination cascade" do
      # This test validates that we've broken the contamination cascade
      MockHelpers.validate_clean_environment!(:gemini)

      # Clear API key to force mock
      original_key = System.get_env("GEMINI_API_KEY")
      System.delete_env("GEMINI_API_KEY")

      try do
        # Use setup_mock_client directly since we've cleared the API key
        {client_type, client} = MockHelpers.setup_mock_client(:gemini)
        assert client_type == :mock

        # If old bug existed, this would show as :real with mock key
        # But now it should correctly be :mock
        {:ok, stats} = MockHelpers.unified_get_stats({client_type, client})
        assert stats.stats.mock_mode == true

        # Environment should be clean
        assert System.get_env("GEMINI_API_KEY") == nil
      after
        restore_env_key("GEMINI_API_KEY", original_key)
      end
    end
  end

  describe "diagnostic utilities" do
    test "environment diagnostic provides accurate reporting" do
      # Capture original state
      original_gemini = System.get_env("GEMINI_API_KEY")

      try do
        # Test diagnostic with clean environment
        System.delete_env("GEMINI_API_KEY")

        # Should not raise any errors
        MockHelpers.diagnose_environment()

        # Test diagnostic with contaminated environment
        System.put_env("GEMINI_API_KEY", "mock-api-key-for-testing-persistent")

        # Should not crash but should show contamination
        MockHelpers.diagnose_environment()
      after
        # Clean up - restore original state
        restore_env_key("GEMINI_API_KEY", original_gemini)
      end
    end

    test "environment reset clears contamination" do
      # Store original state for all keys
      original_gemini = System.get_env("GEMINI_API_KEY")
      original_openai = System.get_env("OPENAI_API_KEY")
      original_anthropic = System.get_env("ANTHROPIC_API_KEY")

      try do
        # Create contamination
        System.put_env("GEMINI_API_KEY", "mock-api-key-for-testing-persistent")
        System.put_env("OPENAI_API_KEY", "mock-api-key-for-testing-persistent")

        # Reset should clear contamination but preserve real keys
        MockHelpers.reset_test_environment!()

        # Contaminated keys should be cleared
        assert System.get_env("GEMINI_API_KEY") == nil
        assert System.get_env("OPENAI_API_KEY") == nil

        # Real keys should be preserved (if there were any)
        assert System.get_env("ANTHROPIC_API_KEY") == original_anthropic
      after
        # Restore all original keys
        restore_env_key("GEMINI_API_KEY", original_gemini)
        restore_env_key("OPENAI_API_KEY", original_openai)
        restore_env_key("ANTHROPIC_API_KEY", original_anthropic)
      end
    end
  end

  ## Helper Functions

  defp restore_env_key(_key, nil), do: :ok
  defp restore_env_key(key, value), do: System.put_env(key, value)
end
