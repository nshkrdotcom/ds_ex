defmodule DSPEx.Services.TelemetrySetup do
  @moduledoc """
  Sets up DSPEx-specific telemetry handlers and metrics using Foundation's telemetry system.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Wait for Foundation to be ready
    :ok = wait_for_foundation()

    # Set up DSPEx telemetry
    setup_dspex_telemetry()

    # Register with Foundation's service registry
    :ok = Foundation.ServiceRegistry.register(:production, :dspex_telemetry_setup, self())

    # Set up graceful shutdown handling
    setup_shutdown_hooks()

    {:ok, %{telemetry_active: true, handlers_attached: true}}
  end

  defp wait_for_foundation do
    case Foundation.available?() do
      true ->
        :ok

      false ->
        Process.sleep(100)
        wait_for_foundation()
    end
  end

  defp setup_dspex_telemetry do
    # Define DSPEx-specific telemetry events
    events = [
      [:dspex, :predict, :start],
      [:dspex, :predict, :stop],
      [:dspex, :predict, :exception],
      [:dspex, :client, :request, :start],
      [:dspex, :client, :request, :stop],
      [:dspex, :client, :request, :exception],
      [:dspex, :adapter, :format, :start],
      [:dspex, :adapter, :format, :stop],
      [:dspex, :adapter, :parse, :start],
      [:dspex, :adapter, :parse, :stop],
      [:dspex, :signature, :validation, :start],
      [:dspex, :signature, :validation, :stop]
    ]

    # Attach Foundation's telemetry handlers
    Foundation.Telemetry.attach_handlers(events)

    # Set up custom DSPEx handlers
    :telemetry.attach_many(
      "dspex-telemetry-handlers",
      events,
      &__MODULE__.handle_dspex_event/4,
      %{}
    )

    Logger.info("DSPEx telemetry setup complete")
  end

  defp setup_shutdown_hooks do
    # Handle ExUnit test completion if in test environment
    if Code.ensure_loaded?(ExUnit) do
      setup_exunit_integration()
    end
  end

  defp setup_exunit_integration do
    # Hook into ExUnit's lifecycle to gracefully shutdown telemetry
    # This prevents race conditions during test cleanup
    pid = self()

    spawn(fn ->
      # Monitor ExUnit completion
      ref = Process.monitor(ExUnit.Server)

      receive do
        {:DOWN, ^ref, :process, _pid, _reason} ->
          # ExUnit is shutting down - signal our telemetry to stop
          send(pid, :prepare_for_shutdown)
      end
    end)
  end

  def handle_info(:prepare_for_shutdown, state) do
    Logger.debug("DSPEx Telemetry: Preparing for graceful shutdown")

    # Detach our telemetry handlers to prevent race conditions
    graceful_detach_handlers()

    {:noreply, %{state | telemetry_active: false, handlers_attached: false}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp graceful_detach_handlers do
    try do
      :telemetry.detach("dspex-telemetry-handlers")
      Logger.debug("DSPEx Telemetry: Handlers detached successfully")
    rescue
      error ->
        Logger.debug(
          "DSPEx Telemetry: Handler detach failed (expected during shutdown): #{inspect(error)}"
        )
    end
  end

  def terminate(_reason, state) do
    if state[:handlers_attached] do
      graceful_detach_handlers()
    end

    :ok
  end

  def handle_dspex_event(event, measurements, metadata, config) do
    # Enhanced defensive programming: Protect against Foundation/ExUnit race conditions
    # During test cleanup, ETS tables may be unavailable causing crashes

    # Track telemetry handler calls for debugging
    process_info = %{
      pid: self(),
      node: node(),
      application_running:
        Application.started_applications() |> Enum.any?(fn {app, _, _} -> app == :foundation end),
      test_mode: Code.ensure_loaded?(ExUnit)
    }

    try do
      # Only proceed if Foundation is still available
      if Foundation.available?() do
        do_handle_dspex_event(event, measurements, metadata, config)
      else
        # Foundation is shutting down - skip telemetry to prevent crashes
        log_telemetry_skip(:foundation_unavailable, event, process_info)
        :ok
      end
    rescue
      ArgumentError ->
        # ETS table may be gone during test cleanup - fail silently
        log_telemetry_skip(:ets_unavailable, event, process_info)
        :ok

      SystemLimitError ->
        # System under stress during test cleanup
        log_telemetry_skip(:system_limit, event, process_info)
        :ok

      UndefinedFunctionError ->
        # Foundation function may not be available
        log_telemetry_skip(:undefined_function, event, process_info)
        :ok

      FunctionClauseError ->
        # Foundation contract violation (like we saw with Events API)
        log_telemetry_skip(:function_clause, event, process_info)
        :ok
    catch
      :exit, {:noproc, _} ->
        # Process may be dead during cleanup
        log_telemetry_skip(:process_dead, event, process_info)
        :ok

      :exit, {:badarg, _} ->
        # ETS table corruption during cleanup
        log_telemetry_skip(:ets_corruption, event, process_info)
        :ok

      :exit, {:normal, _} ->
        # Process shutting down normally
        log_telemetry_skip(:process_shutdown, event, process_info)
        :ok

      kind, reason ->
        # Catch any other unexpected errors
        log_telemetry_skip({:unexpected_error, kind, reason}, event, process_info)
        :ok
    end
  end

  # Enhanced logging for telemetry issues
  defp log_telemetry_skip(reason, event, process_info) do
    if Application.get_env(:dspex, :telemetry_debug, false) do
      Logger.warning("""
      DSPEx Telemetry Handler: Skipped event due to #{inspect(reason)}
      Event: #{inspect(event)}
      Process Info: #{inspect(process_info)}

      This is expected during test cleanup or Foundation shutdown.
      To disable this logging, set config :dspex, telemetry_debug: false
      """)
    end
  end

  # Renamed original handlers to be called defensively
  defp do_handle_dspex_event([:dspex, :predict, :stop], measurements, metadata, _config) do
    # Track prediction performance with Foundation telemetry (v0.1.2 has emit_histogram)
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :prediction_duration],
      measurements.duration,
      %{
        signature: metadata[:signature],
        provider: metadata[:provider],
        success: measurements[:success] || true
      }
    )

    # Track prediction success/failure
    status = if measurements[:success] != false, do: "success", else: "error"

    Foundation.Telemetry.emit_counter(
      [:dspex, :predictions, :total],
      %{
        signature: metadata[:signature],
        provider: metadata[:provider],
        status: status
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :client, :request, :stop], measurements, metadata, _config) do
    # Track client request performance with Foundation telemetry (v0.1.2 has emit_histogram)
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :client_request_duration],
      measurements.duration,
      %{
        provider: metadata[:provider],
        model: metadata[:model],
        success: measurements[:success] || true
      }
    )

    # Track token usage if available
    if token_usage = metadata[:token_usage] do
      Foundation.Telemetry.emit_gauge(
        [:dspex, :usage, :tokens_consumed],
        token_usage[:total] || token_usage[:input] + token_usage[:output],
        %{
          provider: metadata[:provider],
          model: metadata[:model],
          type: "total"
        }
      )

      if input_tokens = token_usage[:input] do
        Foundation.Telemetry.emit_gauge(
          [:dspex, :usage, :tokens_consumed],
          input_tokens,
          %{
            provider: metadata[:provider],
            model: metadata[:model],
            type: "input"
          }
        )
      end

      if output_tokens = token_usage[:output] do
        Foundation.Telemetry.emit_gauge(
          [:dspex, :usage, :tokens_consumed],
          output_tokens,
          %{
            provider: metadata[:provider],
            model: metadata[:model],
            type: "output"
          }
        )
      end
    end

    # Track API costs if available
    if cost = metadata[:cost] do
      Foundation.Telemetry.emit_gauge(
        [:dspex, :usage, :api_cost],
        cost,
        %{
          provider: metadata[:provider],
          model: metadata[:model]
        }
      )
    end
  end

  defp do_handle_dspex_event([:dspex, :predict, :start], _measurements, metadata, _config) do
    # Track prediction start events
    Foundation.Telemetry.emit_counter(
      [:dspex, :predictions, :started],
      %{
        signature: metadata[:signature],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :predict, :exception], _measurements, metadata, _config) do
    # Track prediction exceptions
    Foundation.Telemetry.emit_counter(
      [:dspex, :errors, :predictions],
      %{
        signature: metadata[:signature],
        error_type: metadata[:error_type] || "unknown",
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :client, :request, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track client request start events
    Foundation.Telemetry.emit_counter(
      [:dspex, :client_requests, :started],
      %{
        provider: metadata[:provider],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :client, :request, :exception],
         _measurements,
         metadata,
         _config
       ) do
    # Track client request failures with Foundation telemetry
    Foundation.Telemetry.emit_counter(
      [:dspex, :errors, :client_requests],
      %{
        provider: metadata[:provider],
        error_type: metadata[:error_type] || "unknown"
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :adapter, :format, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track adapter format start events
    Foundation.Telemetry.emit_counter(
      [:dspex, :adapter, :format_started],
      %{
        signature: metadata[:signature],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :adapter, :parse, :start], _measurements, metadata, _config) do
    # Track adapter parse start events
    Foundation.Telemetry.emit_counter(
      [:dspex, :adapter, :parse_started],
      %{
        signature: metadata[:signature],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :signature, :validation, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track signature validation start events
    Foundation.Telemetry.emit_counter(
      [:dspex, :signature, :validation_started],
      %{
        signature: metadata[:signature],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :signature, :validation, :stop],
         measurements,
         metadata,
         _config
       ) do
    # Track signature validation performance
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :signature_validation_duration],
      measurements.duration,
      %{
        signature: metadata[:signature],
        success: measurements[:success] || true
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :adapter, :format, :stop], measurements, metadata, _config) do
    # Track adapter formatting performance with Foundation telemetry
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :adapter_format_duration],
      measurements.duration,
      %{
        adapter: metadata[:adapter] || "default",
        signature: metadata[:signature]
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :adapter, :parse, :stop], measurements, metadata, _config) do
    # Track adapter parsing performance with Foundation telemetry
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :adapter_parse_duration],
      measurements.duration,
      %{
        adapter: metadata[:adapter] || "default",
        signature: metadata[:signature],
        success: measurements[:success] || true
      }
    )
  end

  defp do_handle_dspex_event(event, _measurements, metadata, _config) do
    # Log unhandled events for debugging
    Logger.debug(
      "Unhandled DSPEx telemetry event: #{inspect(event)}, metadata: #{inspect(metadata)}"
    )
  end
end
