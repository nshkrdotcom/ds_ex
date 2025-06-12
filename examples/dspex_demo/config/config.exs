import Config

config :dspex,
  providers: %{
    gemini: %{
      api_key: {:system, "GEMINI_API_KEY"},
      base_url: "https://generativelanguage.googleapis.com/v1beta/models",
      default_model: "gemini-1.5-flash",
      timeout: 30_000
    },
    openai: %{
      api_key: {:system, "OPENAI_API_KEY"},
      base_url: "https://api.openai.com/v1",
      default_model: "gpt-4o-mini",
      timeout: 30_000
    }
  },
  prediction: %{
    default_provider: :gemini,
    default_temperature: 0.7,
    default_max_tokens: 150
  },
  teleprompters: %{
    simba: %{
      default_instruction_model: :openai,
      default_evaluation_model: :gemini,
      max_concurrent_operations: 10
    }
  }