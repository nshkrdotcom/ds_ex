home@Desktop:~/p/g/n/ds_ex$ mix test

12:50:27.345 [info] Starting Foundation application...

12:50:27.365 [info] Configuration server initialized successfully in namespace :production

12:50:27.365 [info] Event store initialized successfully

12:50:27.366 [info] Telemetry service initialized successfully in namespace :production

12:50:27.366 [info] ConnectionManager started

12:50:27.370 [info] Foundation application started successfully

12:50:27.423 [debug] DSPEx config path is restricted - using fallback config only

12:50:27.430 [info] Initialized circuit breaker :dspex_client_gemini with config %{failure_threshold: 5, recovery_time: 30000}

12:50:27.430 [debug] Initialized circuit breaker for gemini

12:50:27.431 [info] Initialized circuit breaker :dspex_client_openai with config %{failure_threshold: 3, recovery_time: 15000}

12:50:27.431 [debug] Initialized circuit breaker for openai

12:50:27.431 [debug] Registering service :config_server in namespace :production

12:50:27.431 [info] Successfully registered service :config_server in namespace :production

12:50:27.431 [info] DSPEx telemetry setup complete

12:50:27.431 [debug] Registering service :telemetry_service in namespace :production

12:50:27.431 [info] Successfully registered service :telemetry_service in namespace :production
     warning: using single-quoted strings to represent charlists is deprecated.
     Use ~c"" if you indeed want a charlist or use "" instead.
     You may run "mix format --migrate" to change all single-quoted
     strings to use the ~c sigil and fix this warning.
     │
 380 │         %{question: 'charlist'},
     │                     ~
     │
     └─ test/unit/system_edge_cases_test.exs:380:21

Running ExUnit with seed: 538002, max_cases: 48
Excluding tags: [:group_1, :group_2, :live_api, :integration, :end_to_end, :performance, :external_api, :phase2_features, :reproduction_test, :todo_optimize, :phase5a, :stress_test, :integration_test]

     warning: variable "program" is unused (there is a variable with the same name in the context, use the pin operator (^) to match on it or prefix this variable with underscore if it is not meant to be used)
     │
 612 │         program = nil
     │         ~
     │
     └─ test/unit/system_edge_cases_test.exs:612:9: DSPEx.SystemEdgeCasesTest."test concurrent edge cases rapid program creation and destruction"/1

     warning: variable "large_examples" is unused (there is a variable with the same name in the context, use the pin operator (^) to match on it or prefix this variable with underscore if it is not meant to be used)
     │
 682 │       large_examples = nil
     │       ~~~~~~~~~~~~~~
     │
     └─ test/unit/system_edge_cases_test.exs:682:7: DSPEx.SystemEdgeCasesTest."test memory and resource edge cases large example collections don't cause memory leaks"/1

     warning: variable "processed" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 677 │       processed = Enum.map(large_examples, fn example ->
     │       ~~~~~~~~~
     │
     └─ test/unit/system_edge_cases_test.exs:677:7: DSPEx.SystemEdgeCasesTest."test memory and resource edge cases large example collections don't cause memory leaks"/1

     warning: variable "processed" is unused (there is a variable with the same name in the context, use the pin operator (^) to match on it or prefix this variable with underscore if it is not meant to be used)
     │
 683 │       processed = nil
     │       ~~~~~~~~~
     │
     └─ test/unit/system_edge_cases_test.exs:683:7: DSPEx.SystemEdgeCasesTest."test memory and resource edge cases large example collections don't cause memory leaks"/1

     warning: function collect_progress_messages/1 is unused
     │
 413 │   defp collect_progress_messages(acc) do
     │        ~
     │
     └─ test/unit/bootstrap_advanced_test.exs:413:8: DSPEx.Teleprompter.BootstrapAdvancedTest (module)


12:50:27.832 [debug] MockClientManager started for provider test with opts: %{responses: :contextual, simulate_delays: false, failure_rate: 0.0, base_delay_ms: 50, max_delay_ms: 200}


  1) test resource limitation scenarios handles memory constraints gracefully (DSPEx.SystemEdgeCasesTest)
     test/unit/system_edge_cases_test.exs:193
     ** (MatchError) no match of right hand side value: {:error, {:already_started, #PID<0.540.0>}}
     stacktrace:
       test/unit/system_edge_cases_test.exs:10: DSPEx.SystemEdgeCasesTest.__ex_unit_setup_0/1
       test/unit/system_edge_cases_test.exs:2: DSPEx.SystemEdgeCasesTest.__ex_unit__/2



  2) test resource limitation scenarios timeout handling at various levels (DSPEx.SystemEdgeCasesTest)
     test/unit/system_edge_cases_test.exs:221
     ** (MatchError) no match of right hand side value: {:error, {:already_started, #PID<0.540.0>}}
     stacktrace:
       test/unit/system_edge_cases_test.exs:10: DSPEx.SystemEdgeCasesTest.__ex_unit_setup_0/1
       test/unit/system_edge_cases_test.exs:2: DSPEx.SystemEdgeCasesTest.__ex_unit__/2



  3) test concurrent edge cases rapid program creation and destruction (DSPEx.SystemEdgeCasesTest)
     test/unit/system_edge_cases_test.exs:602
     ** (MatchError) no match of right hand side value: {:error, {:already_started, #PID<0.540.0>}}
     stacktrace:
       test/unit/system_edge_cases_test.exs:10: DSPEx.SystemEdgeCasesTest.__ex_unit_setup_0/1
       test/unit/system_edge_cases_test.exs:2: DSPEx.SystemEdgeCasesTest.__ex_unit__/2



  4) test error message consistency timeout errors are informative (DSPEx.SystemEdgeCasesTest)
     test/unit/system_edge_cases_test.exs:443
     ** (MatchError) no match of right hand side value: {:error, {:already_started, #PID<0.540.0>}}
     stacktrace:
       test/unit/system_edge_cases_test.exs:10: DSPEx.SystemEdgeCasesTest.__ex_unit_setup_0/1
       test/unit/system_edge_cases_test.exs:2: DSPEx.SystemEdgeCasesTest.__ex_unit__/2



  5) test complex nested compositions program wrapping and unwrapping (DSPEx.SystemEdgeCasesTest)
     test/unit/system_edge_cases_test.exs:269
     ** (MatchError) no match of right hand side value: {:error, {:already_started, #PID<0.540.0>}}
     stacktrace:
       test/unit/system_edge_cases_test.exs:10: DSPEx.SystemEdgeCasesTest.__ex_unit_setup_0/1
       test/unit/system_edge_cases_test.exs:2: DSPEx.SystemEdgeCasesTest.__ex_unit__/2



  6) test malformed input handling extremely long input strings (DSPEx.SystemEdgeCasesTest)
     test/unit/system_edge_cases_test.exs:130
     ** (MatchError) no match of right hand side value: {:error, {:already_started, #PID<0.540.0>}}
     stacktrace:
       test/unit/system_edge_cases_test.exs:10: DSPEx.SystemEdgeCasesTest.__ex_unit_setup_0/1
       test/unit/system_edge_cases_test.exs:2: DSPEx.SystemEdgeCasesTest.__ex_unit__/2



  7) test concurrent edge cases edge case in program composition under load (DSPEx.SystemEdgeCasesTest)
     test/unit/system_edge_cases_test.exs:629
     ** (MatchError) no match of right hand side value: {:error, {:already_started, #PID<0.540.0>}}
     stacktrace:
       test/unit/system_edge_cases_test.exs:10: DSPEx.SystemEdgeCasesTest.__ex_unit_setup_0/1
       test/unit/system_edge_cases_test.exs:2: DSPEx.SystemEdgeCasesTest.__ex_unit__/2



  8) test error message consistency missing field errors are descriptive (DSPEx.SystemEdgeCasesTest)
     test/unit/system_edge_cases_test.exs:402
     ** (MatchError) no match of right hand side value: {:error, {:already_started, #PID<0.540.0>}}
     stacktrace:
       test/unit/system_edge_cases_test.exs:10: DSPEx.SystemEdgeCasesTest.__ex_unit_setup_0/1
       test/unit/system_edge_cases_test.exs:2: DSPEx.SystemEdgeCasesTest.__ex_unit__/2



  9) test error message consistency type mismatch errors are helpful (DSPEx.SystemEdgeCasesTest)
     test/unit/system_edge_cases_test.exs:421
     ** (MatchError) no match of right hand side value: {:error, {:already_started, #PID<0.540.0>}}
     stacktrace:
       test/unit/system_edge_cases_test.exs:10: DSPEx.SystemEdgeCasesTest.__ex_unit_setup_0/1
       test/unit/system_edge_cases_test.exs:2: DSPEx.SystemEdgeCasesTest.__ex_unit__/2



 10) test memory and resource edge cases large example collections don't cause memory leaks (DSPEx.SystemEdgeCasesTest)
     test/unit/system_edge_cases_test.exs:657
     ** (MatchError) no match of right hand side value: {:error, {:already_started, #PID<0.540.0>}}
     stacktrace:
       test/unit/system_edge_cases_test.exs:10: DSPEx.SystemEdgeCasesTest.__ex_unit_setup_0/1
       test/unit/system_edge_cases_test.exs:2: DSPEx.SystemEdgeCasesTest.__ex_unit__/2

    warning: variable "metric_fn" is unused (if the variable is not meant to be used, prefix it with an underscore)
    │
 22 │     def compile(student, teacher, trainset, metric_fn, opts \\ []) do
    │                                             ~~~~~~~~~
    │
    └─ test/unit/teleprompter_advanced_test.exs:22:45: DSPEx.TeleprompterAdvancedTest.MockTeleprompter.compile/5

    warning: variable "teacher" is unused (if the variable is not meant to be used, prefix it with an underscore)
    │
 22 │     def compile(student, teacher, trainset, metric_fn, opts \\ []) do
    │                          ~~~~~~~
    │
    └─ test/unit/teleprompter_advanced_test.exs:22:26: DSPEx.TeleprompterAdvancedTest.MockTeleprompter.compile/5

    warning: variable "trainset" is unused (if the variable is not meant to be used, prefix it with an underscore)
    │
 22 │     def compile(student, teacher, trainset, metric_fn, opts \\ []) do
    │                                   ~~~~~~~~
    │
    └─ test/unit/teleprompter_advanced_test.exs:22:35: DSPEx.TeleprompterAdvancedTest.MockTeleprompter.compile/5

warning: pattern matching on 0.0 is equivalent to matching only on +0.0 from Erlang/OTP 27+. Instead you must match on +0.0 or -0.0
└─ test/unit/teleprompter_advanced_test.exs: DSPEx.TeleprompterAdvancedTest."test helper functions exact_match/1 creates correct metric function"/1

warning: pattern matching on 0.0 is equivalent to matching only on +0.0 from Erlang/OTP 27+. Instead you must match on +0.0 or -0.0
└─ test/unit/teleprompter_advanced_test.exs: DSPEx.TeleprompterAdvancedTest."test helper functions contains_match/1 creates correct metric function"/1

warning: pattern matching on 0.0 is equivalent to matching only on +0.0 from Erlang/OTP 27+. Instead you must match on +0.0 or -0.0
└─ test/unit/teleprompter_advanced_test.exs: DSPEx.TeleprompterAdvancedTest."test helper functions metric functions handle missing fields gracefully"/1

warning: pattern matching on 0.0 is equivalent to matching only on +0.0 from Erlang/OTP 27+. Instead you must match on +0.0 or -0.0
└─ test/unit/teleprompter_advanced_test.exs: DSPEx.TeleprompterAdvancedTest."test helper functions metric functions handle missing fields gracefully"/1

warning: pattern matching on 0.0 is equivalent to matching only on +0.0 from Erlang/OTP 27+. Instead you must match on +0.0 or -0.0
└─ test/unit/teleprompter_advanced_test.exs: DSPEx.TeleprompterAdvancedTest."test helper functions metric functions handle non-string values"/1

warning: pattern matching on 0.0 is equivalent to matching only on +0.0 from Erlang/OTP 27+. Instead you must match on +0.0 or -0.0
└─ test/unit/teleprompter_advanced_test.exs: DSPEx.TeleprompterAdvancedTest."test edge cases and error handling metric functions handle edge cases"/1

🔵🔵🔵    warning: variable "program" is unused (if the variable is not meant to be used, prefix it with an underscore)
    │
 24 │     def forward(program, inputs, _opts \\ []) do
    │                 ~~~~~~~
    │
    └─ test/unit/optimized_program_advanced_test.exs:24:17: DSPEx.OptimizedProgramAdvancedTest.TestProgramWithDemos.forward/3

    warning: this clause for forward/2 cannot match because a previous clause at line 20 always matches
    │
 24 │     def forward(program, inputs, _opts \\ []) do
    │         ~
    │
    └─ test/unit/optimized_program_advanced_test.exs:24:9

     warning: variable "updated" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 319 │       updated = OptimizedProgram.add_demos(optimized, [])
     │       ~~~~~~~
     │
     └─ test/unit/optimized_program_advanced_test.exs:319:7: DSPEx.OptimizedProgramAdvancedTest."test edge cases and error handling metadata is immutable across operations"/1

🔵🔵🔵     warning: DSPEx.OptimizedProgram.update_program/2 is undefined or private
     │
 216 │       updated = OptimizedProgram.update_program(optimized, new_program)
     │                                  ~
     │
     └─ test/unit/optimized_program_advanced_test.exs:216:34: DSPEx.OptimizedProgramAdvancedTest."test metadata tracking and management update_program/2 preserves demos and metadata"/1

     warning: unknown key .module in expression:

         info.module

     the given type does not have the given key:

         dynamic(%{
           demo_count: integer(),
           has_demos: boolean(),
           name: binary(),
           signature: term(),
           type: :custom or :optimized or :predict
         })

     where "info" was given the type:

         # type: dynamic(%{
           demo_count: integer(),
           has_demos: boolean(),
           name: binary(),
           signature: term(),
           type: :custom or :optimized or :predict
         })
         # from: test/unit/optimized_program_advanced_test.exs:352:12
         info = DSPEx.Program.safe_program_info(optimized)

     typing violation found at:
     │
 356 │       assert info.module == OptimizedProgram
     │                   ~~~~~~
     │
     └─ test/unit/optimized_program_advanced_test.exs:356:19: DSPEx.OptimizedProgramAdvancedTest."test Program behavior integration safe_program_info/1 extracts safe information"/1

--max-failures reached, aborting test suite
Finished in 0.9 seconds (0.9s async, 0.00s sync)
82 tests, 10 failures, 72 excluded
