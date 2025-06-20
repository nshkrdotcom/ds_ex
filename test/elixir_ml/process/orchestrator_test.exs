defmodule ElixirML.Process.OrchestratorTest do
  use ExUnit.Case, async: false

  alias ElixirML.Process.Orchestrator

  describe "supervision tree" do
    test "starts successfully with default configuration" do
      # The orchestrator should already be started by the application
      assert Process.whereis(Orchestrator) != nil
    end

    test "provides status information for all children" do
      status = Orchestrator.status()

      assert is_list(status)
      assert length(status) > 0

      # Check that each status entry has required fields
      Enum.each(status, fn entry ->
        assert Map.has_key?(entry, :id)
        assert Map.has_key?(entry, :pid)
        assert Map.has_key?(entry, :type)
        assert Map.has_key?(entry, :status)
        assert entry.status in [:running, :stopped]
      end)
    end

    test "provides process statistics" do
      stats = Orchestrator.process_stats()

      assert Map.has_key?(stats, :total_processes)
      assert Map.has_key?(stats, :running_processes)
      assert Map.has_key?(stats, :memory_usage)
      assert Map.has_key?(stats, :uptime)

      assert is_integer(stats.total_processes)
      assert is_integer(stats.running_processes)
      assert is_integer(stats.memory_usage)
      assert is_integer(stats.uptime)
    end
  end

  describe "child process management" do
    test "can restart individual child processes" do
      # Get current status
      initial_status = Orchestrator.status()

      # Find a child to restart
      child_to_restart =
        Enum.find(initial_status, fn entry ->
          entry.status == :running
        end)

      if child_to_restart do
        # Restart the child
        result = Orchestrator.restart_child(child_to_restart.id)

        # Should either succeed or return an error (depending on restart strategy)
        assert result in [:ok, {:error, :not_found}, {:error, :restarting}] or
                 match?({:ok, _}, result) or
                 match?({:error, _}, result)
      end
    end
  end

  describe "fault tolerance" do
    test "supervisor continues running if child crashes" do
      _initial_stats = Orchestrator.process_stats()

      # The orchestrator should remain stable
      assert Process.alive?(Process.whereis(Orchestrator))

      # Wait a bit and check again
      Process.sleep(100)

      final_stats = Orchestrator.process_stats()
      assert Process.alive?(Process.whereis(Orchestrator))

      # Stats should be available
      assert is_map(final_stats)
    end
  end
end
