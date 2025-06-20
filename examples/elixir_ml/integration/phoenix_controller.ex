# Example: Phoenix Controller Integration
#
# This example demonstrates:
# - ElixirML integration with Phoenix controllers
# - API parameter validation
# - Error handling and response formatting
# - Performance monitoring in web context
#
# Usage: Add to your Phoenix application

defmodule MyAppWeb.MLController do
  @moduledoc """
  Comprehensive Phoenix controller example using ElixirML for ML API validation.

  This controller demonstrates:
  - LLM API parameter validation
  - Real-time performance monitoring
  - Structured error responses
  - Provider-specific optimizations
  """

  use MyAppWeb, :controller

  # Schema definitions for different ML endpoints
  @llm_generation_schema ElixirML.Runtime.create_schema([
    {:prompt, :string, min_length: 1, max_length: 50_000},
    {:model, :string, choices: ["gpt-4", "gpt-3.5-turbo", "claude-3-opus", "claude-3-sonnet"]},
    {:temperature, :float, gteq: 0.0, lteq: 2.0},
    {:max_tokens, :integer, gteq: 1, lteq: 8192},
    {:top_p, :float, gteq: 0.0, lteq: 1.0},
    {:stream, :boolean, optional: true}
  ])

  @embedding_schema ElixirML.Runtime.create_schema([
    {:input, :string, min_length: 1, max_length: 100_000},
    {:model, :string, choices: ["text-embedding-ada-002", "text-embedding-3-small", "text-embedding-3-large"]},
    {:dimensions, :integer, choices: [512, 768, 1024, 1536, 2048]},
    {:encoding_format, :string, choices: ["float", "base64"], optional: true}
  ])

  @optimization_schema ElixirML.Runtime.create_schema([
    {:objective, :string, choices: ["minimize_cost", "maximize_quality", "minimize_latency"]},
    {:constraints, :string, optional: true},
    {:budget_limit, :float, gteq: 0.01, lteq: 1000.0},
    {:quality_threshold, :float, gteq: 0.0, lteq: 10.0},
    {:max_iterations, :integer, gteq: 1, lteq: 1000}
  ])

  # LLM Text Generation API
  def generate_text(conn, params) do
    with {:ok, validated_params} <- validate_and_monitor(@llm_generation_schema, params, "llm_generation"),
         {:ok, result} <- LLMService.generate_text(validated_params),
         :ok <- log_api_usage(conn, validated_params, result) do

      json(conn, %{
        success: true,
        data: result,
        metadata: %{
          model: validated_params.model,
          tokens_used: result.usage.total_tokens,
          cost_estimate: calculate_cost(validated_params.model, result.usage.total_tokens)
        }
      })
    else
      {:error, :validation_error, errors} ->
        handle_validation_error(conn, errors)

      {:error, :service_error, reason} ->
        handle_service_error(conn, reason)

      {:error, reason} ->
        handle_generic_error(conn, reason)
    end
  end

  # Embedding Generation API
  def generate_embeddings(conn, params) do
    with {:ok, validated_params} <- validate_and_monitor(@embedding_schema, params, "embedding_generation"),
         {:ok, result} <- EmbeddingService.generate_embeddings(validated_params) do

      json(conn, %{
        success: true,
        data: result,
        metadata: %{
          model: validated_params.model,
          dimensions: length(hd(result.embeddings).embedding),
          input_tokens: result.usage.total_tokens
        }
      })
    else
      {:error, :validation_error, errors} ->
        handle_validation_error(conn, errors)

      error ->
        handle_generic_error(conn, error)
    end
  end

  # ML Optimization API
  def optimize_parameters(conn, params) do
    with {:ok, validated_params} <- validate_and_monitor(@optimization_schema, params, "optimization"),
         {:ok, optimization_space} <- create_optimization_space(validated_params),
         {:ok, result} <- OptimizationService.optimize(optimization_space, validated_params) do

      json(conn, %{
        success: true,
        data: result,
        metadata: %{
          iterations_completed: result.iterations,
          best_score: result.best_score,
          optimization_time_ms: result.duration_ms
        }
      })
    else
      {:error, :validation_error, errors} ->
        handle_validation_error(conn, errors)

      error ->
        handle_generic_error(conn, error)
    end
  end

  # Batch Processing API
  def batch_process(conn, %{"requests" => requests} = _params) when is_list(requests) do
    # Validate each request in the batch
    validation_results = Enum.map(requests, fn request ->
      case request["type"] do
        "generation" ->
          validate_and_monitor(@llm_generation_schema, request["params"], "batch_generation")
        "embedding" ->
          validate_and_monitor(@embedding_schema, request["params"], "batch_embedding")
        _ ->
          {:error, :validation_error, [%{field: "type", message: "Invalid request type"}]}
      end
    end)

    case Enum.split_with(validation_results, &match?({:ok, _}, &1)) do
      {valid_requests, []} ->
        # All requests valid, process batch
        process_batch_requests(conn, valid_requests)

      {_valid, invalid_requests} ->
        # Some requests invalid, return errors
        errors = Enum.map(invalid_requests, fn {:error, :validation_error, errs} -> errs end)

        conn
        |> put_status(:bad_request)
        |> json(%{
          success: false,
          error: "batch_validation_failed",
          message: "Some requests in the batch failed validation",
          errors: errors
        })
    end
  end

  def batch_process(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      error: "invalid_batch_format",
      message: "Batch requests must be provided as a list under 'requests' key"
    })
  end

  # Performance Monitoring API
  def performance_stats(conn, _params) do
    stats = %{
      validation_performance: get_validation_stats(),
      api_usage: get_api_usage_stats(),
      error_rates: get_error_rates(),
      cost_analysis: get_cost_analysis()
    }

    json(conn, %{
      success: true,
      data: stats,
      generated_at: DateTime.utc_now()
    })
  end

  # Schema Information API
  def schema_info(conn, %{"endpoint" => endpoint}) do
    schema = case endpoint do
      "generation" -> @llm_generation_schema
      "embedding" -> @embedding_schema
      "optimization" -> @optimization_schema
      _ -> nil
    end

    if schema do
      json_schema = ElixirML.Runtime.to_json_schema(schema)

      json(conn, %{
        success: true,
        data: %{
          endpoint: endpoint,
          json_schema: json_schema,
          field_count: map_size(json_schema.properties),
          required_fields: json_schema.required
        }
      })
    else
      conn
      |> put_status(:not_found)
      |> json(%{
        success: false,
        error: "schema_not_found",
        message: "Schema not found for endpoint: #{endpoint}",
        available_endpoints: ["generation", "embedding", "optimization"]
      })
    end
  end

  # Private helper functions

  defp validate_and_monitor(schema, params, operation_type) do
    start_time = System.monotonic_time(:microsecond)

    case ElixirML.Runtime.validate(schema, params) do
      {:ok, validated} ->
        end_time = System.monotonic_time(:microsecond)
        duration = end_time - start_time

        # Log performance metrics
        :telemetry.execute(
          [:elixir_ml, :validation, :success],
          %{duration_microseconds: duration},
          %{operation: operation_type, field_count: map_size(validated)}
        )

        {:ok, validated}

      {:error, errors} ->
        end_time = System.monotonic_time(:microsecond)
        duration = end_time - start_time

        # Log validation failures
        :telemetry.execute(
          [:elixir_ml, :validation, :error],
          %{duration_microseconds: duration},
          %{operation: operation_type, error_count: length(List.wrap(errors))}
        )

        {:error, :validation_error, errors}
    end
  end

  defp handle_validation_error(conn, errors) do
    formatted_errors = format_validation_errors(errors)

    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      error: "validation_failed",
      message: "Request parameters failed validation",
      errors: formatted_errors,
      help: %{
        documentation: "https://docs.example.com/api/validation",
        common_issues: [
          "Check that all required fields are present",
          "Verify numeric values are within allowed ranges",
          "Ensure string choices match exactly (case-sensitive)"
        ]
      }
    })
  end

  defp handle_service_error(conn, reason) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      success: false,
      error: "service_error",
      message: "ML service temporarily unavailable",
      reason: reason,
      retry_after: 30
    })
  end

  defp handle_generic_error(conn, reason) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{
      success: false,
      error: "internal_error",
      message: "An unexpected error occurred",
      request_id: get_request_id(conn)
    })
  end

  defp format_validation_errors(errors) when is_list(errors) do
    Enum.map(errors, &format_single_error/1)
  end

  defp format_validation_errors(error) do
    [format_single_error(error)]
  end

  defp format_single_error(%ElixirML.Schema.ValidationError{} = error) do
    %{
      field: error.field,
      message: error.message,
      received_value: error.value,
      constraints: error.constraints || %{}
    }
  end

  defp format_single_error(error) do
    %{
      message: inspect(error)
    }
  end

  defp process_batch_requests(conn, valid_requests) do
    # Process valid requests in parallel
    tasks = Enum.map(valid_requests, fn {:ok, validated_params} ->
      Task.async(fn ->
        # Process individual request based on type
        # This is a simplified example
        case validated_params do
          %{model: model} when model in ["gpt-4", "gpt-3.5-turbo"] ->
            LLMService.generate_text(validated_params)

          %{model: model} when model in ["text-embedding-ada-002"] ->
            EmbeddingService.generate_embeddings(validated_params)

          _ ->
            {:error, "unsupported_request_type"}
        end
      end)
    end)

    # Collect results
    results = Task.await_many(tasks, 30_000)

    json(conn, %{
      success: true,
      data: results,
      metadata: %{
        total_requests: length(results),
        successful_requests: Enum.count(results, &match?({:ok, _}, &1)),
        failed_requests: Enum.count(results, &match?({:error, _}, &1))
      }
    })
  end

  defp create_optimization_space(params) do
    case params.objective do
      "minimize_cost" ->
        {:ok, ElixirML.Variable.MLTypes.provider_optimized_space(:cost_optimized)}

      "maximize_quality" ->
        {:ok, ElixirML.Variable.MLTypes.provider_optimized_space(:quality_optimized)}

      "minimize_latency" ->
        {:ok, ElixirML.Variable.MLTypes.provider_optimized_space(:speed_optimized)}

      _ ->
        {:error, "unsupported_objective"}
    end
  end

  defp calculate_cost(model, tokens) do
    # Simplified cost calculation
    cost_per_1k_tokens = case model do
      "gpt-4" -> 0.03
      "gpt-3.5-turbo" -> 0.002
      "claude-3-opus" -> 0.015
      "claude-3-sonnet" -> 0.003
      _ -> 0.001
    end

    (tokens / 1000.0) * cost_per_1k_tokens
  end

  defp log_api_usage(conn, params, result) do
    usage_data = %{
      endpoint: conn.request_path,
      model: params.model,
      tokens_used: get_in(result, [:usage, :total_tokens]) || 0,
      cost_estimate: calculate_cost(params.model, get_in(result, [:usage, :total_tokens]) || 0),
      user_id: get_current_user_id(conn),
      timestamp: DateTime.utc_now()
    }

    # Log to your analytics system
    :telemetry.execute([:api, :ml, :usage], usage_data, %{})
    :ok
  end

  defp get_validation_stats do
    # Get validation performance stats from telemetry
    %{
      avg_validation_time_microseconds: 45.2,
      validations_per_second: 22_156,
      success_rate: 0.94,
      common_errors: ["temperature_out_of_range", "invalid_model_choice"]
    }
  end

  defp get_api_usage_stats do
    %{
      total_requests_today: 15_420,
      successful_requests: 14_502,
      failed_requests: 918,
      most_used_models: ["gpt-3.5-turbo", "gpt-4", "claude-3-sonnet"],
      avg_response_time_ms: 1_250
    }
  end

  defp get_error_rates do
    %{
      validation_errors: 0.06,
      service_errors: 0.02,
      timeout_errors: 0.01,
      rate_limit_errors: 0.003
    }
  end

  defp get_cost_analysis do
    %{
      total_cost_today_usd: 245.67,
      cost_by_model: %{
        "gpt-4" => 189.23,
        "gpt-3.5-turbo" => 34.12,
        "claude-3-opus" => 18.45,
        "claude-3-sonnet" => 3.87
      },
      avg_cost_per_request: 0.0159
    }
  end

  defp get_current_user_id(conn) do
    # Extract user ID from authentication
    get_in(conn.assigns, [:current_user, :id]) || "anonymous"
  end

  defp get_request_id(conn) do
    # Get request ID for tracing
    get_req_header(conn, "x-request-id") |> List.first() || "unknown"
  end
end

# Telemetry setup for monitoring
defmodule MyApp.MLTelemetry do
  @moduledoc """
  Telemetry setup for ElixirML performance monitoring.
  """

  def setup do
    :telemetry.attach_many(
      "elixir-ml-metrics",
      [
        [:elixir_ml, :validation, :success],
        [:elixir_ml, :validation, :error],
        [:api, :ml, :usage]
      ],
      &handle_event/4,
      %{}
    )
  end

  defp handle_event([:elixir_ml, :validation, :success], measurements, metadata, _config) do
    # Log successful validations
    Logger.info("ElixirML validation success",
      duration: measurements.duration_microseconds,
      operation: metadata.operation,
      field_count: metadata.field_count
    )

    # Send to metrics system (e.g., Prometheus, StatsD)
    :telemetry_metrics.counter([:elixir_ml, :validations, :total])
    :telemetry_metrics.histogram([:elixir_ml, :validation, :duration], measurements.duration_microseconds)
  end

  defp handle_event([:elixir_ml, :validation, :error], measurements, metadata, _config) do
    # Log validation errors
    Logger.warn("ElixirML validation error",
      duration: measurements.duration_microseconds,
      operation: metadata.operation,
      error_count: metadata.error_count
    )

    :telemetry_metrics.counter([:elixir_ml, :validation_errors, :total])
  end

  defp handle_event([:api, :ml, :usage], _measurements, metadata, _config) do
    # Log API usage for billing/analytics
    Logger.info("ML API usage",
      model: metadata.model,
      tokens: metadata.tokens_used,
      cost: metadata.cost_estimate,
      user_id: metadata.user_id
    )
  end
end

# Router configuration
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
    plug MyAppWeb.AuthPlug  # Your authentication
    plug MyAppWeb.RateLimitPlug  # Rate limiting
  end

  scope "/api/v1/ml", MyAppWeb do
    pipe_through :api

    post "/generate", MLController, :generate_text
    post "/embed", MLController, :generate_embeddings
    post "/optimize", MLController, :optimize_parameters
    post "/batch", MLController, :batch_process

    get "/stats", MLController, :performance_stats
    get "/schema/:endpoint", MLController, :schema_info
  end
end
