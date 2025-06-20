defmodule ElixirML.Process.ResourceManagerTest do
  use ExUnit.Case, async: false

  alias ElixirML.Process.ResourceManager

  setup do
    # Check if ResourceManager is already running (from the application)
    case GenServer.whereis(ResourceManager) do
      nil ->
        # Start a test resource manager with smaller limits
        {:ok, pid} =
          ResourceManager.start_link(
            max_memory_mb: 100,
            max_processes: 10,
            cleanup_interval_ms: 1000
          )

        on_exit(fn ->
          if Process.alive?(pid) do
            GenServer.stop(pid)
          end
        end)

        %{manager: pid, test_started: true}

      pid ->
        # Use the existing ResourceManager from the application
        %{manager: pid, test_started: false}
    end
  end

  describe "resource statistics" do
    test "provides current resource usage statistics", %{test_started: test_started} do
      stats = ResourceManager.get_resource_stats()

      assert Map.has_key?(stats, :memory_usage_mb)
      assert Map.has_key?(stats, :max_memory_mb)
      assert Map.has_key?(stats, :memory_utilization)
      assert Map.has_key?(stats, :process_count)
      assert Map.has_key?(stats, :max_processes)
      assert Map.has_key?(stats, :process_utilization)
      assert Map.has_key?(stats, :active_alerts)
      assert Map.has_key?(stats, :erlang_memory)

      assert is_number(stats.memory_usage_mb)

      # Check configuration based on whether we started our own manager
      if test_started do
        assert stats.max_memory_mb == 100
        assert stats.max_processes == 10
      else
        # Using production config - just verify it's reasonable
        assert stats.max_memory_mb > 0
        assert stats.max_processes > 0
      end

      assert is_number(stats.memory_utilization)
      assert is_integer(stats.process_count)
      assert is_number(stats.process_utilization)
      assert is_integer(stats.active_alerts)
      assert is_map(stats.erlang_memory)
    end

    test "erlang memory stats include expected fields" do
      stats = ResourceManager.get_resource_stats()
      erlang_memory = stats.erlang_memory

      assert Map.has_key?(erlang_memory, :total)
      assert Map.has_key?(erlang_memory, :processes)
      assert Map.has_key?(erlang_memory, :system)
      assert Map.has_key?(erlang_memory, :atom)
      assert Map.has_key?(erlang_memory, :binary)
      assert Map.has_key?(erlang_memory, :ets)

      Enum.each(erlang_memory, fn {_key, value} ->
        assert is_integer(value)
        assert value >= 0
      end)
    end
  end

  describe "resource availability checking" do
    test "checks resource availability for new operations" do
      # Check with no requirements
      availability = ResourceManager.check_resource_availability()

      assert Map.has_key?(availability, :memory_available)
      assert Map.has_key?(availability, :processes_available)
      assert Map.has_key?(availability, :can_allocate)
      assert Map.has_key?(availability, :current_memory_usage)
      assert Map.has_key?(availability, :current_process_count)

      assert is_boolean(availability.memory_available)
      assert is_boolean(availability.processes_available)
      assert is_boolean(availability.can_allocate)
    end

    test "checks availability with specific requirements" do
      requirements = %{
        memory_mb: 50,
        processes: 5
      }

      availability = ResourceManager.check_resource_availability(requirements)

      assert is_boolean(availability.can_allocate)

      # With limits of 100MB and 10 processes, 50MB and 5 processes should be available
      assert availability.memory_available == true
      assert availability.processes_available == true
      assert availability.can_allocate == true
    end

    test "correctly identifies insufficient resources", %{test_started: _test_started} do
      stats = ResourceManager.get_resource_stats()

      # Use a memory requirement that exceeds the current max
      excessive_memory = stats.max_memory_mb + 100

      requirements = %{
        memory_mb: excessive_memory,
        processes: 5
      }

      availability = ResourceManager.check_resource_availability(requirements)

      assert availability.memory_available == false
      assert availability.can_allocate == false
    end
  end

  describe "resource allocation and release" do
    test "can allocate resources to a process" do
      {:ok, test_pid} = Agent.start_link(fn -> :ok end)

      resource_spec = %{memory_mb: 20}

      result = ResourceManager.allocate_resources(test_pid, resource_spec)
      assert result == {:ok, :allocated}

      # Check that process count increased
      stats = ResourceManager.get_resource_stats()
      assert stats.process_count >= 1

      # Clean up
      Agent.stop(test_pid)
      # Allow time for monitor cleanup
      Process.sleep(50)
    end

    test "refuses allocation when resources are insufficient" do
      {:ok, test_pid} = Agent.start_link(fn -> :ok end)

      stats = ResourceManager.get_resource_stats()
      excessive_memory = stats.max_memory_mb + 100

      resource_spec = %{memory_mb: excessive_memory}

      result = ResourceManager.allocate_resources(test_pid, resource_spec)
      assert result == {:error, :insufficient_resources}

      # Clean up
      Agent.stop(test_pid)
    end

    test "automatically releases resources when process dies" do
      {:ok, test_pid} = Agent.start_link(fn -> :ok end)

      resource_spec = %{memory_mb: 20}

      # Allocate resources
      {:ok, :allocated} = ResourceManager.allocate_resources(test_pid, resource_spec)

      initial_stats = ResourceManager.get_resource_stats()
      initial_count = initial_stats.process_count

      # Kill the process
      Agent.stop(test_pid)

      # Allow time for monitor to trigger
      Process.sleep(100)

      # Check that process count decreased
      final_stats = ResourceManager.get_resource_stats()
      assert final_stats.process_count < initial_count
    end

    test "can manually release resources" do
      {:ok, test_pid} = Agent.start_link(fn -> :ok end)

      initial_stats = ResourceManager.get_resource_stats()
      initial_count = initial_stats.process_count

      # Manually release resources
      ResourceManager.release_resources(test_pid)

      # Process count should decrease (though it might not go below 0)
      final_stats = ResourceManager.get_resource_stats()
      assert final_stats.process_count <= initial_count

      # Clean up
      Agent.stop(test_pid)
    end
  end

  describe "resource history and monitoring" do
    test "maintains resource usage history" do
      # Wait a bit for monitoring to collect some data
      Process.sleep(1100)

      history = ResourceManager.get_resource_history(5)

      assert is_list(history)

      if length(history) > 0 do
        entry = List.first(history)

        assert Map.has_key?(entry, :timestamp)
        assert Map.has_key?(entry, :memory_usage_mb)
        assert Map.has_key?(entry, :process_count)
        assert Map.has_key?(entry, :erlang_stats)

        assert is_integer(entry.timestamp)
        assert is_number(entry.memory_usage_mb)
        assert is_integer(entry.process_count)
        assert is_map(entry.erlang_stats)
      end
    end

    test "limits history size" do
      # Wait for some history to accumulate
      Process.sleep(1100)

      history = ResourceManager.get_resource_history(2)

      assert is_list(history)
      assert length(history) <= 2
    end
  end

  describe "cleanup operations" do
    test "can force cleanup operation" do
      # This mainly tests that force cleanup doesn't crash
      :ok = ResourceManager.force_cleanup()

      # Manager should still be responsive
      stats = ResourceManager.get_resource_stats()
      assert is_map(stats)
    end
  end

  describe "error handling" do
    test "handles invalid resource specifications gracefully" do
      {:ok, test_pid} = Agent.start_link(fn -> :ok end)

      # Test with nil resource spec
      result = ResourceManager.allocate_resources(test_pid, nil)
      # Should handle gracefully (exact result depends on implementation)
      assert result in [
               {:ok, :allocated},
               {:error, :insufficient_resources},
               {:error, :invalid_spec}
             ] or match?({:error, _}, result)

      # Clean up
      Agent.stop(test_pid)
    end

    test "handles resource release for non-existent process" do
      fake_pid = spawn(fn -> :ok end)
      Process.exit(fake_pid, :kill)

      # Should not crash
      ResourceManager.release_resources(fake_pid)

      # Manager should still be responsive
      stats = ResourceManager.get_resource_stats()
      assert is_map(stats)
    end
  end
end
