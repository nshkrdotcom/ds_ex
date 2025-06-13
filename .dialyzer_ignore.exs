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
  {"lib/dspex/config/schemas/teleprompter_configuration.ex", :pattern_match}
]
