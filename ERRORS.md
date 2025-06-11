home@Desktop:~/p/g/n/ds_ex$ mix test --include integration_test

12:10:07.804 [info] Starting Foundation application...

12:10:07.825 [info] Configuration server initialized successfully in namespace :production

12:10:07.825 [info] Event store initialized successfully

12:10:07.826 [info] Telemetry service initialized successfully in namespace :production

12:10:07.826 [info] ConnectionManager started

12:10:07.830 [info] Foundation application started successfully

12:10:07.879 [debug] DSPEx config path is restricted - using fallback config only

12:10:07.883 [info] Initialized circuit breaker :dspex_client_gemini with config %{failure_threshold: 5, recovery_time: 30000}

12:10:07.883 [debug] Initialized circuit breaker for gemini

12:10:07.883 [info] Initialized circuit breaker :dspex_client_openai with config %{failure_threshold: 3, recovery_time: 15000}

12:10:07.883 [debug] Initialized circuit breaker for openai

12:10:07.883 [debug] Registering service :config_server in namespace :production

12:10:07.883 [info] Successfully registered service :config_server in namespace :production

12:10:07.883 [info] DSPEx telemetry setup complete

12:10:07.883 [debug] Registering service :telemetry_service in namespace :production

12:10:07.883 [info] Successfully registered service :telemetry_service in namespace :production
Running ExUnit with seed: 6265, max_cases: 48
Excluding tags: [:group_1, :group_2, :live_api, :integration, :end_to_end, :performance, :external_api, :phase2_features, :reproduction_test, :todo_optimize, :phase5a, :stress_test]
Including tags: [:integration_test]

     warning: variable "teacher_result" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 136 │       teacher_result = case Program.forward(teacher, sample_input) do
     │       ~~~~~~~~~~~~~~
     │
     └─ test/integration/teleprompter_workflow_advanced_test.exs:136:7: DSPEx.Integration.TeleprompterWorkflowAdvancedTest."test complete teleprompter workflow - SIMBA dependency student → teacher → optimized student pipeline validation"/1

    warning: unused alias Evaluate
    │
 11 │   alias DSPEx.{Teleprompter, Example, Predict, OptimizedProgram, Program, Evaluate}
    │   ~
    │
    └─ test/integration/teleprompter_workflow_advanced_test.exs:11:3

     warning: variable "opts" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 151 │       opts = [max_bootstrapped_demos: 2, quality_threshold: 0.5]
     │       ~~~~
     │
     └─ test/integration/simba_readiness_test.exs:151:7: DSPEx.Integration.SIMBAReadinessTest."test SIMBA interface compatibility validation all function signatures match SIMBA usage patterns exactly"/1

     warning: variable "optimized" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 229 │       assert {:ok, optimized} = result, "Should handle minimal trainset"
     │                    ~~~~~~~~~
     │
     └─ test/integration/simba_readiness_test.exs:229:20: DSPEx.Integration.SIMBAReadinessTest."test SIMBA interface compatibility validation handles edge cases that SIMBA might encounter"/1

     warning: variable "optimized_with_failures" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 293 │       assert {:ok, optimized_with_failures} = result_with_failures, "Should handle teacher failures gracefully"
     │                    ~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ test/integration/simba_readiness_test.exs:293:20: DSPEx.Integration.SIMBAReadinessTest."test SIMBA interface compatibility validation handles edge cases that SIMBA might encounter"/1

    warning: DSPEx.Teleprompter.validate_student/1 is undefined or private
    │
 63 │       assert :ok = Teleprompter.validate_student(student), "Student validation failed"
    │                                 ~
    │
    └─ test/integration/simba_readiness_test.exs:63:33: DSPEx.Integration.SIMBAReadinessTest."test SIMBA interface compatibility validation teleprompter behavior validation functions work correctly"/1

     warning: DSPEx.Teleprompter.validate_student/1 is undefined or private
     │
 128 │       assert :ok = Teleprompter.validate_student(student)
     │                                 ~
     │
     └─ test/integration/teleprompter_workflow_advanced_test.exs:128:33: DSPEx.Integration.TeleprompterWorkflowAdvancedTest."test complete teleprompter workflow - SIMBA dependency student → teacher → optimized student pipeline validation"/1

    warning: DSPEx.Teleprompter.validate_teacher/1 is undefined or private
    │
 64 │       assert :ok = Teleprompter.validate_teacher(teacher), "Teacher validation failed"
    │                                 ~
    │
    └─ test/integration/simba_readiness_test.exs:64:33: DSPEx.Integration.SIMBAReadinessTest."test SIMBA interface compatibility validation teleprompter behavior validation functions work correctly"/1

     warning: DSPEx.Teleprompter.validate_teacher/1 is undefined or private
     │
 129 │       assert :ok = Teleprompter.validate_teacher(teacher)
     │                                 ~
     │
     └─ test/integration/teleprompter_workflow_advanced_test.exs:129:33: DSPEx.Integration.TeleprompterWorkflowAdvancedTest."test complete teleprompter workflow - SIMBA dependency student → teacher → optimized student pipeline validation"/1

    warning: DSPEx.Teleprompter.validate_trainset/1 is undefined or private
    │
 65 │       assert :ok = Teleprompter.validate_trainset(trainset), "Trainset validation failed"
    │                                 ~
    │
    └─ test/integration/simba_readiness_test.exs:65:33: DSPEx.Integration.SIMBAReadinessTest."test SIMBA interface compatibility validation teleprompter behavior validation functions work correctly"/1

     warning: DSPEx.Teleprompter.validate_trainset/1 is undefined or private
     │
 130 │       assert :ok = Teleprompter.validate_trainset(trainset)
     │                                 ~
     │
     └─ test/integration/teleprompter_workflow_advanced_test.exs:130:33: DSPEx.Integration.TeleprompterWorkflowAdvancedTest."test complete teleprompter workflow - SIMBA dependency student → teacher → optimized student pipeline validation"/1

     warning: the following pattern will never match:

         %{type: :predict, name: :Predict, module: DSPEx.Predict, has_demos: false} = info

     because the right-hand side has type:

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
         # from: test/integration/simba_readiness_test.exs:368:12
         info = DSPEx.Program.safe_program_info(program)

     typing violation found at:
     │
 376 │       } = info, "Safe program info structure incorrect"
     │         ~
     │
     └─ test/integration/simba_readiness_test.exs:376:9: DSPEx.Integration.SIMBAReadinessTest."test program name and telemetry utilities safe program info extraction for telemetry"/1

.
12:10:08.902 [debug] MockClientManager started for provider test with opts: %{responses: :contextual, simulate_delays: false, failure_rate: 0.0, base_delay_ms: 50, max_delay_ms: 200}


  1) test complete teleprompter workflow - SIMBA dependency student → teacher → optimized student pipeline validation (DSPEx.Integration.TeleprompterWorkflowAdvancedTest)
     test/integration/teleprompter_workflow_advanced_test.exs:124
     ** (UndefinedFunctionError) function DSPEx.Teleprompter.validate_student/1 is undefined or private
     code: assert :ok = Teleprompter.validate_student(student)
     stacktrace:
       (dspex 0.1.0) DSPEx.Teleprompter.validate_student(%DSPEx.Predict{signature: DSPEx.Integration.TeleprompterWorkflowAdvancedTest.WorkflowSignature, client: :test_student, adapter: nil, demos: []})
       test/integration/teleprompter_workflow_advanced_test.exs:128: (test)



  2) test complete teleprompter workflow - SIMBA dependency BootstrapFewShot complete pipeline execution (DSPEx.Integration.TeleprompterWorkflowAdvancedTest)
     test/integration/teleprompter_workflow_advanced_test.exs:75
     ** (FunctionClauseError) no function clause matching in DSPEx.Teleprompter.BootstrapFewShot.compile/5

     The following arguments were given to DSPEx.Teleprompter.BootstrapFewShot.compile/5:

         # 1
         %DSPEx.Teleprompter.BootstrapFewShot{max_bootstrapped_demos: 3, max_labeled_demos: 8, quality_threshold: 0.6, max_concurrency: 10, timeout: 30000, teacher_retries: 2, progress_callback: nil}

         # 2
         %DSPEx.Predict{signature: DSPEx.Integration.TeleprompterWorkflowAdvancedTest.WorkflowSignature, client: :test_student, adapter: nil, demos: []}

         # 3
         %DSPEx.Predict{signature: DSPEx.Integration.TeleprompterWorkflowAdvancedTest.WorkflowSignature, client: :test_teacher, adapter: nil, demos: []}

         # 4
         [#DSPEx.Example<%{question: "What is 2+2?", answer: "4"}, inputs: [:question]>, #DSPEx.Example<%{question: "What is 3+3?", answer: "6"}, inputs: [:question]>, #DSPEx.Example<%{question: "What is the capital of France?", answer: "Paris"}, inputs: [:question]>, #DSPEx.Example<%{question: "Who wrote Romeo and Juliet?", answer: "William Shakespeare"}, inputs: [:question]>, #DSPEx.Example<%{question: "What is the largest planet?", answer: "Jupiter"}, inputs: [:question]>]

         # 5
         #Function<1.119635497/2 in DSPEx.Teleprompter.exact_match/1>

     Attempted function clauses (showing 1 out of 1):

         def compile(student, teacher, trainset, metric_fn, opts) when is_list(opts)

     code: result = BootstrapFewShot.compile(
     stacktrace:
       (dspex 0.1.0) lib/dspex/teleprompter/bootstrap_fewshot.ex:84: DSPEx.Teleprompter.BootstrapFewShot.compile/5
       test/integration/teleprompter_workflow_advanced_test.exs:87: (test)

...

  3) test SIMBA interface compatibility validation teleprompter behavior validation functions work correctly (DSPEx.Integration.SIMBAReadinessTest)
     test/integration/simba_readiness_test.exs:50
     ** (UndefinedFunctionError) function DSPEx.Teleprompter.validate_student/1 is undefined or private
     code: assert :ok = Teleprompter.validate_student(student), "Student validation failed"
     stacktrace:
       (dspex 0.1.0) DSPEx.Teleprompter.validate_student(%DSPEx.Predict{signature: SIMBACompatSignature, client: :test, adapter: nil, demos: []})
       test/integration/simba_readiness_test.exs:63: (test)

🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵.🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵

  4) test performance validation for SIMBA bootstrap generation completes within acceptable time (DSPEx.Integration.SIMBAReadinessTest)
     test/integration/simba_readiness_test.exs:656
     ** (MatchError) no match of right hand side value: {:error, :no_successful_bootstrap_candidates}
     code: {:ok, _optimized} = BootstrapFewShot.compile(
     stacktrace:
       test/integration/simba_readiness_test.exs:678: (test)

🔵🔵🔵🔵🔵🔵🔵🔵🔵🔵

  5) test client architecture validation client handles concurrent requests reliably (SIMBA load pattern) (DSPEx.Integration.SIMBAReadinessTest)
     test/integration/simba_readiness_test.exs:434
     All successful responses must have proper structure
     code: assert Enum.all?(successful_responses, fn response ->
     stacktrace:
       test/integration/simba_readiness_test.exs:463: (test)



  6) test program name and telemetry utilities safe program info extraction for telemetry (DSPEx.Integration.SIMBAReadinessTest)
     test/integration/simba_readiness_test.exs:364
     ** (MatchError) no match of right hand side value: %{name: "Predict", type: :predict, signature: SIMBACompatSignature, demo_count: 0, has_demos: false}
     code: } = info, "Safe program info structure incorrect"
     stacktrace:
       test/integration/simba_readiness_test.exs:376: (test)



  7) test SIMBA interface compatibility validation handles edge cases that SIMBA might encounter (DSPEx.Integration.SIMBAReadinessTest)
     test/integration/simba_readiness_test.exs:205
     ** (MatchError) no match of right hand side value: {:error, :no_successful_bootstrap_candidates}
     code: assert {:ok, optimized} = result, "Should handle minimal trainset"
     stacktrace:
       test/integration/simba_readiness_test.exs:229: (test)



  8) test performance validation for SIMBA memory usage remains stable during repeated optimizations (DSPEx.Integration.SIMBAReadinessTest)
     test/integration/simba_readiness_test.exs:698
     ** (MatchError) no match of right hand side value: {:error, :no_successful_bootstrap_candidates}
     code: Enum.each(1..10, fn i ->
     stacktrace:
       test/integration/simba_readiness_test.exs:720: anonymous fn/2 in DSPEx.Integration.SIMBAReadinessTest."test performance validation for SIMBA memory usage remains stable during repeated optimizations"/1
       (elixir 1.18.3) lib/enum.ex:992: anonymous fn/3 in Enum.each/2
       (elixir 1.18.3) lib/enum.ex:4507: Enum.reduce_range/5
       (elixir 1.18.3) lib/enum.ex:2550: Enum.each/2
       test/integration/simba_readiness_test.exs:716: (test)

🔵

  9) test performance validation for SIMBA concurrent optimization doesn't degrade individual performance (DSPEx.Integration.SIMBAReadinessTest)
     test/integration/simba_readiness_test.exs:743
     ** (MatchError) no match of right hand side value: {:error, :no_successful_bootstrap_candidates}
     code: {:ok, _single_result} = BootstrapFewShot.compile(student, teacher, trainset, metric_fn)
     stacktrace:
       test/integration/simba_readiness_test.exs:764: (test)

🔵🔵🔵..

 10) test SIMBA interface compatibility validation all function signatures match SIMBA usage patterns exactly (DSPEx.Integration.SIMBAReadinessTest)
     test/integration/simba_readiness_test.exs:140
     ** (MatchError) no match of right hand side value: {:error, :no_successful_bootstrap_candidates}
     code: assert {:ok, optimized_student} = result, "BootstrapFewShot compilation failed"
     stacktrace:
       test/integration/simba_readiness_test.exs:171: (test)

--max-failures reached, aborting test suite
Finished in 1.6 seconds (0.8s async, 0.8s sync)
1 doctest, 26 properties, 526 tests, 10 failures, 536 excluded
