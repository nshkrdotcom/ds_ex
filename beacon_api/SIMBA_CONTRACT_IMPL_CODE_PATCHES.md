# Contract Implementation Patches
# Apply these changes to implement the DSPEx-SIMBA API contract

# =============================================================================
# PATCH 1: lib/dspex/program.ex - Add missing Program contract functions
# =============================================================================

# Add after existing program_name/1 function:

@doc """
Determine the type of a program for SIMBA optimization strategies.
"""
@spec program_type(t()) :: :predict | :optimized | :custom | :unknown
def program_type(program) when is_struct(program) do
  case program.__struct__ |> Module.split() |> List.last() do
    "Predict" -> :predict
    "OptimizedProgram" -> :optimized
    _ -> :custom
  end
end
def program_type(_), do: :unknown

@doc """
Extract safe program information without sensitive data.
Critical: Used by SIMBA for program analysis and telemetry.
"""
@spec safe_program_info(t()) :: %{
  type: atom(),
  name: atom(),
  has_demos: boolean(),
  signature: atom() | nil
}
def safe_program_info(program) when is_struct(program) do
  %{
    type: program_type(program),
    name: program_name(program),
    has_demos: has_demos?(program),
    signature: get_signature_module(program)
  }
end

@doc """
Check if a program contains demonstration examples.
Critical: Used by SIMBA to determine wrapping strategy.
"""
@spec has_demos?(t()) :: boolean()
def has_demos?(program) when is_struct(program) do
  cond do
    Map.has_key?(program, :demos) and is_list(program.demos) ->
      length(program.demos) > 0
    true -> 
      false
  end
end

# Replace the existing forward/2 function with enhanced forward/2 and forward/3:

@spec forward(program(), inputs()) :: {:ok, outputs()} | {:error, term()}
def forward(program, inputs) when is_map(inputs) do
  forward(program, inputs, [])
end

@spec forward(program(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}
def forward(program, inputs, opts) when is_map(inputs) and is_list(opts) do
  # Extract and validate options
  correlation_id = Keyword.get(opts, :correlation_id) || generate_correlation_id()
  timeout = Keyword.get(opts, :timeout, 30_000)
  
  # Wrap execution with timeout and enhanced telemetry
  task = Task.async(fn ->
    start_time = System.monotonic_time()
    
    :telemetry.execute(
      [:dspex, :program, :forward, :start],
      %{system_time: System.system_time()},
      %{
        program: program_name(program),
        correlation_id: correlation_id,
        input_count: map_size(inputs)
      }
    )
    
    result = program.__struct__.forward(program, inputs, opts)
    
    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)
    
    :telemetry.execute(
      [:dspex, :program, :forward, :stop],
      %{duration: duration, success: success},
      %{
        program: program_name(program),
        correlation_id: correlation_id
      }
    )
    
    result
  end)
  
  case Task.yield(task, timeout) do
    {:ok, result} -> result
    nil ->
      Task.shutdown(task, :brutal_kill)
      {:error, :timeout}
  end
end

def forward(_, inputs, _) when not is_map(inputs),
  do: {:error, {:invalid_inputs, "inputs must be a map"}}

# Add private helper functions:

defp get_signature_module(program) when is_struct(program) do
  cond do
    # For Predict programs
    Map.has_key?(program, :signature) and is_atom(program.signature) ->
      program.signature
    
    # For OptimizedProgram wrapping Predict
    Map.has_key?(program, :program) and is_struct(program.program) and
        Map.has_key?(program.program, :signature) ->
      program.program.signature
    
    true ->
      nil
  end
end

defp generate_correlation_id do
  try do
    Foundation.Utils.generate_correlation_id()
  rescue
    _ -> 
      "program-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end

# =============================================================================
# PATCH 2: lib/dspex/optimized_program.ex - Enhance metadata support
# =============================================================================

# Replace the new/3 function with enhanced version:

@doc """
Create a new optimized program wrapper with SIMBA metadata support.
SIMBA stores optimization results, instructions, and Bayesian optimization data.
"""
@spec new(struct(), [DSPEx.Example.t()], map()) :: t()
def new(program, demos, metadata \\ %{}) do
  # Validate metadata is serializable for SIMBA
  validated_metadata = validate_simba_metadata(metadata)
  
  %__MODULE__{
    program: program,
    demos: demos,
    metadata: Map.merge(
      %{
        optimized_at: DateTime.utc_now(),
        demo_count: length(demos)
      },
      validated_metadata
    )
  }
end

# Add new functions for SIMBA support:

@doc """
Check if a program natively supports demonstrations.
Used by SIMBA to determine wrapping strategy.
"""
@spec supports_native_demos?(struct()) :: boolean()
def supports_native_demos?(program) when is_struct(program) do
  Map.has_key?(program, :demos)
end

def supports_native_demos?(_), do: false

@doc """
Check if a program natively supports instructions.
Used by SIMBA to determine enhancement strategy.
"""
@spec supports_native_instruction?(struct()) :: boolean()
def supports_native_instruction?(program) when is_struct(program) do
  Map.has_key?(program, :instruction)
end

def supports_native_instruction?(_), do: false

@doc """
Determine SIMBA enhancement strategy for a program.
"""
@spec simba_enhancement_strategy(struct()) :: :native_full | :native_demos | :wrap_optimized
def simba_enhancement_strategy(program) when is_struct(program) do
  cond do
    supports_native_demos?(program) and supports_native_instruction?(program) ->
      :native_full
    supports_native_demos?(program) ->
      :native_demos
    true ->
      :wrap_optimized
  end
end

def simba_enhancement_strategy(_), do: :wrap_optimized

# Add private helper functions:

# SIMBA metadata validation
defp validate_simba_metadata(metadata) when is_map(metadata) do
  # Ensure SIMBA metadata fields are preserved
  required_simba_fields = [
    :optimization_method,
    :instruction,
    :optimization_score,
    :optimization_stats,
    :bayesian_trials,
    :best_configuration
  ]
  
  # Keep all SIMBA fields, sanitize others
  Enum.reduce(metadata, %{}, fn {key, value}, acc ->
    cond do
      key in required_simba_fields ->
        Map.put(acc, key, value)
      is_atom(key) and is_serializable?(value) ->
        Map.put(acc, key, value)
      true ->
        # Skip non-serializable values but log warning
        Logger.debug("Skipping non-serializable metadata field: #{inspect(key)}")
        acc
    end
  end)
end

defp validate_simba_metadata(_), do: %{}

defp is_serializable?(value) do
  try do
    Jason.encode!(value)
    true
  rescue
    _ -> false
  end
end

# =============================================================================
# PATCH 3: lib/dspex/services/config_manager.ex - Enhance SIMBA config support
# =============================================================================

# Replace the get_default_config/0 function with enhanced version:

@spec get_default_config() :: map()
defp get_default_config do
  base_config = %{
    providers: %{
      gemini: %{
        api_key: {:system, "GEMINI_API_KEY"},
        base_url: "https://generativelanguage.googleapis.com/v1beta/models",
        default_model: "gemini-2.5-flash-preview-05-20",
        timeout: 30_000,
        rate_limit: %{
          requests_per_minute: 60,
          tokens_per_minute: 100_000
        },
        circuit_breaker: %{
          failure_threshold: 5,
          recovery_time: 30_000
        }
      },
      openai: %{
        api_key: {:system, "OPENAI_API_KEY"},
        base_url: "https://api.openai.com/v1",
        default_model: "gpt-4",
        timeout: 30_000,
        rate_limit: %{
          requests_per_minute: 50,
          tokens_per_minute: 150_000
        },
        circuit_breaker: %{
          failure_threshold: 3,
          recovery_time: 15_000
        }
      }
    },
    prediction: %{
      default_provider: :gemini,
      default_temperature: 0.7,
      default_max_tokens: 150,
      cache_enabled: true,
      cache_ttl: 3600
    },
    teleprompters: %{
      simba: %{
        default_instruction_model: :openai,
        default_evaluation_model: :gemini,
        max_concurrent_operations: 20,
        default_timeout: 60_000,
        cache_enabled: true
      }
    },
    telemetry: %{
      enabled: true,
      detailed_logging: false,
      performance_tracking: true
    }
  }

  # Merge with Mix config (config/test.exs, config/dev.exs, etc.)
  mix_config = Application.get_env(:dspex, :providers, %{})
  mix_prediction_config = Application.get_env(:dspex, :prediction, %{})
  mix_teleprompter_config = Application.get_env(:dspex, :teleprompters, %{})
  mix_telemetry_config = Application.get_env(:dspex, :telemetry, %{})

  base_config
  |> put_in([:providers], Map.merge(base_config.providers, mix_config))
  |> put_in([:prediction], Map.merge(base_config.prediction, mix_prediction_config))
  |> put_in([:teleprompters], Map.merge(base_config.teleprompters, mix_teleprompter_config))
  |> put_in([:telemetry], Map.merge(base_config.telemetry, mix_telemetry_config))
end

# Enhance the init/1 function for better service conflict resolution:

@impl GenServer
def init(_opts) do
  # Enhanced initialization with conflict resolution
  case wait_for_foundation() do
    :ok ->
      # Foundation available, proceed with setup
      setup_dspex_config()
      setup_circuit_breakers()
      
      # Register with Foundation's service registry safely
      case Foundation.ServiceRegistry.register(:production, :config_server, self()) do
        :ok -> 
          {:ok, %{fallback_config: get_default_config(), foundation_available: true}}
        {:error, :already_registered} ->
          # Another instance already registered, operate in fallback mode
          Logger.info("ConfigManager already registered, using fallback mode")
          {:ok, %{fallback_config: get_default_config(), foundation_available: false}}
        {:error, reason} ->
          Logger.warning("Foundation registration failed: #{inspect(reason)}, using fallback")
          {:ok, %{fallback_config: get_default_config(), foundation_available: false}}
      end
      
    :timeout ->
      # Foundation not available, use pure fallback mode
      Logger.info("Foundation not available, ConfigManager running in fallback mode")
      {:ok, %{fallback_config: get_default_config(), foundation_available: false}}
  end
end

# Add enhanced Foundation waiting:

defp wait_for_foundation do
  wait_for_foundation(5000) # 5 second timeout
end

defp wait_for_foundation(timeout) when timeout <= 0, do: :timeout

defp wait_for_foundation(timeout) do
  case Foundation.available?() do
    true -> :ok
    false ->
      Process.sleep(100)
      wait_for_foundation(timeout - 100)
  end
end

# =============================================================================
# PATCH 4: lib/dspex/client.ex - Stabilize response format for SIMBA
# =============================================================================

# Add response format normalization after existing parse_response functions:

# Ensure response always has expected structure for SIMBA
defp ensure_stable_response_format(response) do
  %{
    choices: response.choices |> Enum.map(&ensure_choice_format/1)
  }
end

defp ensure_choice_format(choice) do
  %{
    message: %{
      role: get_in(choice, [:message, :role]) || "assistant",
      content: get_in(choice, [:message, :content]) || ""
    }
  }
end

# Update parse_gemini_response to use stable format:

defp parse_gemini_response(%{"candidates" => candidates}) when is_list(candidates) do
  parsed_choices = Enum.map(candidates, &parse_gemini_candidate/1)
  response = %{choices: parsed_choices}
  {:ok, ensure_stable_response_format(response)}
end

defp parse_gemini_response(_), do: {:error, :invalid_response}

# Update parse_openai_response to use stable format:

defp parse_openai_response(%{"choices" => choices}) when is_list(choices) do
  parsed_choices = Enum.map(choices, &parse_openai_choice/1)
  response = %{choices: parsed_choices}
  {:ok, ensure_stable_response_format(response)}
end

defp parse_openai_response(_), do: {:error, :invalid_response}

# Add consistent error categorization:

@type error_reason ::
  :timeout | :network_error | :api_error | :rate_limited |
  :invalid_messages | :provider_not_configured | :no_api_key

defp categorize_client_error(error) do
  case error do
    %{reason: :timeout} -> :timeout
    %{reason: :closed} -> :network_error
    %{reason: :econnrefused} -> :network_error
    %HTTPoison.Error{reason: :timeout} -> :timeout
    %HTTPoison.Error{reason: :nxdomain} -> :network_error
    _ -> :api_error
  end
end

# =============================================================================
# PATCH 5: lib/dspex/teleprompter/bootstrap_fewshot.ex - Fix empty demo handling
# =============================================================================

# Replace the select_best_demonstrations function:

defp select_best_demonstrations(quality_demos, config) do
  # Sort by quality score (highest first) and take the best ones
  selected = quality_demos
    |> Enum.sort_by(fn demo -> demo.data[:__quality_score] || 0.0 end, :desc)
    |> Enum.take(config.max_bootstrapped_demos)

  if config.progress_callback do
    progress = %{
      phase: :demonstration_selection,
      selected_count: length(selected),
      total_candidates: length(quality_demos),
      quality_threshold: config.quality_threshold
    }

    config.progress_callback.(progress)
  end

  # CRITICAL FIX: Always return selected demonstrations (even if empty)
  # This allows SIMBA to handle empty demo scenarios gracefully
  {:ok, selected}
end

# Replace the create_optimized_student function:

defp create_optimized_student(student, selected_demos, config) do
  # Enhanced to handle empty demo lists
  optimized = case selected_demos do
    [] ->
      # No demos available, return enhanced student with metadata only
      case student do
        %{demos: _} ->
          %{student | demos: []}
        _ ->
          DSPEx.OptimizedProgram.new(student, [], %{
            teleprompter: :bootstrap_fewshot,
            quality_threshold: config.quality_threshold,
            optimization_type: :bootstrap_few_shot,
            demo_generation_failed: true,
            fallback_reason: "No quality demonstrations generated"
          })
      end
    
    demos ->
      # Normal path with demonstrations
      case student do
        %{demos: _} ->
          %{student | demos: demos}
        _ ->
          DSPEx.OptimizedProgram.new(student, demos, %{
            teleprompter: :bootstrap_fewshot,
            quality_threshold: config.quality_threshold,
            optimization_type: :bootstrap_few_shot,
            demo_count: length(demos)
          })
      end
  end

  {:ok, optimized}
end

# =============================================================================
# PATCH 6: lib/dspex/services/telemetry_setup.ex - Add SIMBA events
# =============================================================================

# Update the setup_dspex_telemetry function to include SIMBA events:

defp setup_dspex_telemetry do
  # Enhanced event list including SIMBA events
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
    [:dspex, :signature, :validation, :stop],
    [:dspex, :program, :forward, :start],
    [:dspex, :program, :forward, :stop],
    [:dspex, :teleprompter, :bootstrap, :start],
    [:dspex, :teleprompter, :bootstrap, :stop],
    # SIMBA-specific events
    [:dspex, :teleprompter, :simba, :start],
    [:dspex, :teleprompter, :simba, :stop],
    [:dspex, :teleprompter, :simba, :optimization, :start],
    [:dspex, :teleprompter, :simba, :optimization, :stop],
    [:dspex, :teleprompter, :simba, :instruction, :start],
    [:dspex, :teleprompter, :simba, :instruction, :stop]
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

  Logger.info("DSPEx telemetry setup complete with SIMBA events")
  :ok
end
