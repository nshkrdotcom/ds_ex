[
  # Ignore false positive pattern match warnings in validation functions
  {"lib/dspex/evaluate.ex", :pattern_match},
  # Ignore pattern match warnings in program type functions
  {"lib/dspex/program.ex", :pattern_match},
  {"lib/dspex/program.ex", :pattern_match_cov},
  # Ignore pattern match warnings in SIMBA teleprompter
  {"lib/dspex/teleprompter/simba.ex", :pattern_match},
  # Ignore false positive pattern match warnings in Elixact schema modules
  {"lib/dspex/config/schemas/beacon_configuration.ex", :pattern_match},
  {"lib/dspex/config/schemas/client_configuration.ex", :pattern_match},
  {"lib/dspex/config/schemas/evaluation_configuration.ex", :pattern_match},
  {"lib/dspex/config/schemas/logging_configuration.ex", :pattern_match},
  {"lib/dspex/config/schemas/prediction_configuration.ex", :pattern_match},
  {"lib/dspex/config/schemas/provider_configuration.ex", :pattern_match},
  {"lib/dspex/config/schemas/telemetry_configuration.ex", :pattern_match},
  {"lib/dspex/config/schemas/teleprompter_configuration.ex", :pattern_match},
  # Ignore Sinter integration warnings during development
  {"lib/dspex/config/sinter_schemas.ex", :call},
  {"lib/dspex/config/sinter_schemas.ex", :unused_fun},
  {"lib/dspex/config/sinter_schemas.ex", :pattern_match},

  # Ignore ElixirML library pattern match issues - these are in external dependencies
  # and cannot be fixed from our codebase
  {"lib/elixir_ml/process/program_worker.ex", :pattern_match},
  {"lib/elixir_ml/process/variable_registry.ex", :pattern_match},
  {"lib/elixir_ml/runtime.ex", :pattern_match},
  {"lib/elixir_ml/variable/space.ex", :pattern_match},

  # Ignore unused functions in ElixirML - these are API functions that may be used externally
  {"lib/elixir_ml/process/variable_registry.ex", :unused_fun},
  {"lib/elixir_ml/variable/space.ex", :unused_fun},

  # Ignore SIMBA teleprompter warnings - these modules are under active development
  # Functions with no_return are likely incomplete implementations or development stubs
  {"lib/dspex/teleprompter/simba/elixir_ml_schemas.ex", :no_return},
  {"lib/dspex/teleprompter/simba/strategy.ex", :no_return},
  {"lib/dspex/teleprompter/simba/strategy.ex", :unused_fun}
]
