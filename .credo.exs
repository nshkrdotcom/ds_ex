%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/elixir_ml/", "test/elixir_ml/"],
        excluded: []
      },
      checks: [
        # You can customize which checks to run here, or leave as default
      ]
    }
  ]
}
