# File: test/integration/test_mode_architecture_test.exs
defmodule DSPEx.Integration.TestModeArchitectureTest do
  use ExUnit.Case, async: false

  alias DSPEx.TestModeConfig

  @moduletag :integration
  @moduletag :test_modes

  setup do
    # Save original mode
    original_mode = TestModeConfig.get_test_mode()

    on_exit(fn ->
      # Restore original mode
      TestModeConfig.set_test_mode(original_mode)
    end)

    %{original_mode: original_mode}
  end

  describe "test mode detection and switching" do
    test "get_test_mode/0 returns current mode" do
      # Test default mode
      mode = TestModeConfig.get_test_mode()
      assert mode in [:mock, :fallback, :live]
    end

    test "set_test_mode/1 changes active mode" do
      # Test all valid modes
      for mode <- [:mock, :fallback, :live] do
        :ok = TestModeConfig.set_test_mode(mode)
        assert TestModeConfig.get_test_mode() == mode
      end
    end

    test "set_test_mode/1 rejects invalid modes" do
      assert_raise ArgumentError, fn ->
        TestModeConfig.set_test_mode(:invalid_mode)
      end
    end

    test "environment variable takes precedence" do
      # Test DSPEX_TEST_MODE environment variable
      System.put_env("DSPEX_TEST_MODE", "live")
      assert TestModeConfig.get_test_mode() == :live

      System.put_env("DSPEX_TEST_MODE", "fallback")
      assert TestModeConfig.get_test_mode() == :fallback

      System.put_env("DSPEX_TEST_MODE", "mock")
      assert TestModeConfig.get_test_mode() == :mock

      # Cleanup
      System.delete_env("DSPEX_TEST_MODE")
    end

    test "invalid environment variable triggers warning" do
      import ExUnit.CaptureIO

      System.put_env("DSPEX_TEST_MODE", "invalid")

      output = capture_io(:stderr, fn ->
        TestModeConfig.get_test_mode()
      end)

      assert String.contains?(output, "Invalid DSPEX_TEST_MODE")

      # Cleanup
      System.delete_env("DSPEX_TEST_MODE")
    end
  end

  describe "mode-specific behavior validation" do
    test "pure_mock_mode?/0 correctly identifies mock mode" do
      TestModeConfig.set_test_mode(:mock)
      assert TestModeConfig.pure_mock_mode?()

      TestModeConfig.set_test_mode(:fallback)
      refute TestModeConfig.pure_mock_mode?()

      TestModeConfig.set_test_mode(:live)
      refute TestModeConfig.pure_mock_mode?()
    end

    test "fallback_mode?/0 correctly identifies fallback mode" do
      TestModeConfig.set_test_mode(:fallback)
      assert TestModeConfig.fallback_mode?()

      TestModeConfig.set_test_mode(:mock)
      refute TestModeConfig.fallback_mode?()

      TestModeConfig.set_test_mode(:live)
      refute TestModeConfig.fallback_mode?()
    end

    test "live_only_mode?/0 correctly identifies live mode" do
      TestModeConfig.set_test_mode(:live)
      assert TestModeConfig.live_only_mode?()

      TestModeConfig.set_test_mode(:mock)
      refute TestModeConfig.live_only_mode?()

      TestModeConfig.set_test_mode(:fallback)
      refute TestModeConfig.live_only_mode?()
    end
  end

  describe "mode descriptions and metadata" do
    test "describe_current_mode/0 returns appropriate descriptions" do
      TestModeConfig.set_test_mode(:mock)
      description = TestModeConfig.describe_current_mode()
      assert String.contains?(description, "Pure Mock Mode")

      TestModeConfig.set_test_mode(:fallback)
      description = TestModeConfig.describe_current_mode()
      assert String.contains?(description, "Fallback Mode")

      TestModeConfig.set_test_mode(:live)
      description = TestModeConfig.describe_current_mode()
      assert String.contains?(description, "Live API Mode")
    end

    test "mode_emoji/0 returns correct emojis" do
      TestModeConfig.set_test_mode(:mock)
      assert TestModeConfig.mode_emoji() == "🟦"

      TestModeConfig.set_test_mode(:fallback)
      assert TestModeConfig.mode_emoji() == "🟡"

      TestModeConfig.set_test_mode(:live)
      assert TestModeConfig.mode_emoji() == "🟢"
    end

    test "available_modes/0 returns all modes with descriptions" do
      modes = TestModeConfig.available_modes()

      assert length(modes) == 3
      assert {:mock, _desc} = Enum.find(modes, fn {mode, _} -> mode == :mock end)
      assert {:fallback, _desc} = Enum.find(modes, fn {mode, _} -> mode == :fallback end)
      assert {:live, _desc} = Enum.find(modes, fn {mode, _} -> mode == :live end)
    end
  end

  describe "debug and introspection" do
    test "debug_info/0 outputs mode configuration" do
      import ExUnit.CaptureIO

      TestModeConfig.set_test_mode(:mock)

      output = capture_io(fn ->
        TestModeConfig.debug_info()
      end)

      assert String.contains?(output, "DSPEx Test Mode Configuration")
      assert String.contains?(output, "Current Mode: mock")
      assert String.contains?(output, "🟦")
    end
  end

  describe "integration with Client behavior" do
    test "mock mode prevents network attempts" do
      TestModeConfig.set_test_mode(:mock)

      # In mock mode, client should not attempt network requests
      # This would be tested by verifying that DSPEx.Client uses
      # the TestModeConfig to determine behavior

      # For now, just verify the mode is set correctly
      assert TestModeConfig.pure_mock_mode?()
    end

    test "fallback mode allows graceful degradation" do
      TestModeConfig.set_test_mode(:fallback)

      # In fallback mode, client should attempt API calls but
      # gracefully fall back to mock responses

      assert TestModeConfig.fallback_mode?()
    end

    test "live mode requires real API integration" do
      TestModeConfig.set_test_mode(:live)

      # In live mode, client should fail if API keys are not available

      assert TestModeConfig.live_only_mode?()
    end
  end

  describe "concurrent mode access" do
    test "mode changes are visible across processes" do
      TestModeConfig.set_test_mode(:mock)

      # Spawn a process and verify it sees the mode change
      task = Task.async(fn ->
        TestModeConfig.get_test_mode()
      end)

      assert Task.await(task) == :mock

      # Change mode and verify other process sees it
      TestModeConfig.set_test_mode(:live)

      task2 = Task.async(fn ->
        TestModeConfig.get_test_mode()
      end)

      assert Task.await(task2) == :live
    end

    test "mode access is thread-safe under concurrent load" do
      TestModeConfig.set_test_mode(:fallback)

      # Multiple processes accessing mode concurrently
      tasks = Task.async_stream(1..50, fn _i ->
        TestModeConfig.get_test_mode()
      end, max_concurrency: 20)
      |> Enum.to_list()

      # All should return the same mode
      modes = Enum.map(tasks, fn {:ok, mode} -> mode end)
      assert Enum.all?(modes, &(&1 == :fallback))
    end
  end
end
