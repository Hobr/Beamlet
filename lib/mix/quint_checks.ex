defmodule Mix.QuintChecks do
  @moduledoc false
  @root Path.expand("../..", __DIR__)
  @core "model/quint/beamletCore.qnt"
  @tests "model/quint/beamletCore_test.qnt"
  @conflicts "model/quint/beamletConflicts_test.qnt"
  @mutations "model/quint/beamletCore_mutations_test.qnt"
  @models ~w(beamletCore beamletCore_test beamletCore_mutations_test beamletReconciliation beamletConflicts beamletConflicts_test beamletRules beamletRules_mutations_test beamletWithdrawals beamletWithdrawals_mutations_test beamletNormalUse beamletNormalUse_test beamletNormalUse_mutations_test beamletExecution beamletExecution_test beamletRecovery beamletMultiIntent beamletMultiIntent_test beamletMultiIntent_mutations_test beamletContinuation beamletContinuation_test beamletContinuation_mutations_test)
  @contract_models ~w(beamletClaim beamletClaim_test beamletResource beamletResource_test
    beamletHistory beamletHistory_test beamletTriple beamletTriple_test
    beamletSharedResource beamletSharedResource_test beamletContract_mutations_test)
  @contract_mutations ~w(claimReplayAllocatesNewGeneration claimReplyChangesOwner claimOldSessionReceivesToken resourceUsesChangedDefaultAccount resourceAuthorizesWrongDevice resourceRewritesSavedTarget historyStateWithoutCommitGroup historyReusesCommittedSequence historyDuplicateReportCreatesGroup tripleRestartLosesThirdSlot tripleTwoResultsCompleteRound tripleRestartChangesSubmissionKey sharedBothWritesSameVersion sharedBorrowsOtherReceipt sharedCurrentContentProvesCompletion)
  @continuation_mutations ~w(continuationSendBeforeCommit continuationReplayChangesKey
    continuationLostDecision continuationConsumesWrongIntent continuationLaterResultReplacesDecision
    continuationReplayChangesDefinition)
  @multi_mutations ~w(multiCrossIntentReport multiCrossIntentGrant multiSharedIdempotencyContext
    multiSiblingHistoryErased multiPrematureToolJoin multiJoinByNotificationCount
    multiCallbackCorrelationCollision multiLostDependencyManifest)
  @normal_mutations ~w(normalWrongResultValue normalDefinitionOverwritten normalCallbackBindingLost
    normalExpiredIdempotencyRetry normalSuccessNotAtomic normalContextChanged normalFailureNotAtomic normalExtendedIdempotencyWindow)
  @withdrawal_mutations ~w(withdrawalResurrectsOldTreatment withdrawalOverstepsScope withdrawalWithoutRevision
    uncheckedWithdrawalBasis withdrawalCreatesOutcome withdrawalDeletesEvidence
    withdrawalReplayRetargetsNewDisposition commandIdentitySplitByOperationKind withdrawalReplyBeforeCommit)
  @rule_mutations ~w(ruleVersionIgnored ruleConditionsFromOtherVersion automaticRequestVersionRefreshed
    historicalRuleReinterpreted replayBlockedByRuleRetirement retirementClearsDisposition retirementBumpsJudgmentRevision)
  @core_mutations ~w(duplicateOutcome overwriteOutcome reviveExpiredLease negativeQueryRetry
    incarnationInheritance grantAfterClosure pendingRegression unknownFailure earlyReceipt oldSuccessFailure
    unauthorizedReconciliation unregisteredReconciliation staleReconciliation permanentReconciliation
    silentlyRefreshedCommand replayExecutedAgain overwrittenCommand replayWithLatestResult
    earlyCommandReply replayRejectedAsStale rejectedCommandExecutedAgain rejectionContextOverwritten
    resultReadPermissionIgnored cachedResultRequiresSubmitPermission permissionDenialStoredAsDomainRejection
    rejectionReplyBeforeStorage dispositionWithoutRevision heartbeatBumpsJudgmentRevision evidenceWithoutRevision judgmentRevisionReset)
  @conflict_mutations ~w(incompleteConflictCoverage uncheckedConflictBasis erasedConflictHistory
    terminalBeforeConflictResolution permanentConflictDisposition earlyConflictReply deletedConflictReport
    excludedAllUsesCachedKnowledge excludedAllCreatesOutcome implicitSupersession wrongSupersessionTarget
    overbroadSupersession supersessionRewritesOldDecision supersessionLinksNotCommitted)

  def run(config) do
    executable = System.find_executable("quint") || Mix.raise("Quint 0.32.0 is required on PATH")
    suffix = "#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}"
    logs = Path.expand(config.log_dir || Path.join(System.tmp_dir!(), "beamlet-quint-#{suffix}"))
    File.mkdir_p!(logs)
    Mix.shell().info("Quint logs: #{logs}")

    prepare_run_log(logs, executable, config)
    Mix.shell().info("Rust simulation budget: #{config.jobs} jobs × #{config.threads} threads")

    if config.phase in ["all", "simulate"] and
         config.jobs * config.threads > System.schedulers_online() do
      Mix.shell().info(
        "Warning: simulation thread budget exceeds online schedulers; benchmark before increasing concurrency"
      )
    end

    timed(logs, "run", config.phase, "total", fn ->
      for phase <- ~w(typecheck test simulate mutations),
          config.phase in ["all", phase] do
        timed(logs, "phase", phase, phase, fn ->
          config
          |> jobs(phase)
          |> Task.async_stream(
            fn job -> execute(job, executable, logs, config.threads) end,
            max_concurrency: config.jobs,
            timeout: :infinity,
            ordered: false
          )
          |> Enum.each(fn
            {:ok, {:ok, name, elapsed}} ->
              record_timing(logs, "job", phase, name, "passed", elapsed)
              Mix.shell().info("Passed #{phase}: #{name} (#{elapsed} ms)")

            {:ok, {:error, name, message, elapsed}} ->
              record_timing(logs, "job", phase, name, "failed", elapsed)
              Mix.raise(message)

            {:exit, reason} ->
              Mix.raise("Quint worker exited: #{inspect(reason)}")
          end)
        end)
      end
    end)

    Mix.shell().info("Quint checks completed: #{config.phase}")
  end

  defp prepare_run_log(logs, executable, config) do
    {version, status} = System.cmd(executable, ["--version"], stderr_to_stdout: true)
    if status != 0, do: Mix.raise("Cannot read Quint version (exit #{status}): #{version}")

    info = [
      quint_version: String.trim(version),
      backend: "rust",
      online_schedulers: System.schedulers_online(),
      jobs: config.jobs,
      threads: config.threads,
      mutation_threads: 1,
      samples: config.samples,
      directed_samples: config.directed_samples,
      max_steps: 100,
      seed: 42,
      phase: config.phase
    ]

    File.write!(
      Path.join(logs, "run-info.txt"),
      Enum.map_join(info, "\n", fn {key, value} -> "#{key}=#{value}" end) <> "\n"
    )

    File.write!(Path.join(logs, "timings.tsv"), "scope\tphase\tname\tstatus\telapsed_ms\n")
  end

  defp timed(logs, scope, phase, name, fun) do
    started = System.monotonic_time(:millisecond)

    try do
      result = fun.()
      elapsed = System.monotonic_time(:millisecond) - started
      record_timing(logs, scope, phase, name, "passed", elapsed)
      Mix.shell().info("Completed #{scope}: #{name} (#{elapsed} ms)")
      result
    rescue
      error ->
        elapsed = System.monotonic_time(:millisecond) - started
        record_timing(logs, scope, phase, name, "failed", elapsed)
        reraise error, __STACKTRACE__
    end
  end

  # Only the supervising process writes this file; concurrent tasks return durations.
  defp record_timing(logs, scope, phase, name, status, elapsed) do
    File.write!(
      Path.join(logs, "timings.tsv"),
      "#{scope}\t#{phase}\t#{name}\t#{status}\t#{elapsed}\n",
      [:append]
    )
  end

  defp jobs(_config, "typecheck") do
    Enum.map(
      @models ++ @contract_models,
      &{:check, &1 <> ".typecheck", ["typecheck", "model/quint/#{&1}.qnt"]}
    )
  end

  defp jobs(_config, "test") do
    Enum.map(~w(strictTests fencedTests repeatingTests), &test_job(@tests, &1)) ++
      [
        test_job(@conflicts, "conflictTests"),
        test_job("model/quint/beamletNormalUse_test.qnt", "normalUseTests"),
        test_job("model/quint/beamletExecution_test.qnt", "executionProjectionTests"),
        test_job("model/quint/beamletMultiIntent_test.qnt", "multiIntentTests"),
        test_job("model/quint/beamletContinuation_test.qnt", "continuationTests"),
        test_job("model/quint/beamletClaim_test.qnt", "claimTests"),
        test_job("model/quint/beamletResource_test.qnt", "resourceTests"),
        test_job("model/quint/beamletHistory_test.qnt", "historyTests"),
        test_job("model/quint/beamletTriple_test.qnt", "tripleTests"),
        test_job("model/quint/beamletSharedResource_test.qnt", "sharedResourceTests")
      ]
  end

  defp jobs(_config, "mutations") do
    Enum.map(
      @contract_mutations,
      &{:mutation, &1, "model/quint/beamletContract_mutations_test.qnt"}
    ) ++
      Enum.map(
        @continuation_mutations,
        &{:mutation, &1, "model/quint/beamletContinuation_mutations_test.qnt"}
      ) ++
      Enum.map(
        @multi_mutations,
        &{:mutation, &1, "model/quint/beamletMultiIntent_mutations_test.qnt"}
      ) ++
      Enum.map(
        @normal_mutations,
        &{:mutation, &1, "model/quint/beamletNormalUse_mutations_test.qnt"}
      ) ++
      Enum.map(@core_mutations, &{:mutation, &1, @mutations}) ++
      Enum.map(@conflict_mutations, &{:mutation, &1, @conflicts}) ++
      Enum.map(@rule_mutations, &{:mutation, &1, "model/quint/beamletRules_mutations_test.qnt"}) ++
      Enum.map(
        @withdrawal_mutations,
        &{:mutation, &1, "model/quint/beamletWithdrawals_mutations_test.qnt"}
      )
  end

  defp jobs(config, "simulate") do
    core =
      for main <- ~w(beamletCoreAnalysis repeatAllowed fenced),
          do: simulation(main, @core, main, "init", "step", "commandSafety", config.samples)

    prefixes =
      for {main, init} <- [
            {"strictTests", "preparedInit"},
            {"strictTests", "grantedInit"},
            {"fencedTests", "grantHeldInit"},
            {"repeatingTests", "replacementInit"},
            {"repeatingTests", "oldSuccessCurrentFailureInit"}
          ],
          do:
            simulation(
              "#{main}-#{init}",
              @tests,
              main,
              init,
              "step",
              if(main in ~w(strictTests fencedTests), do: "safety", else: "commandSafety"),
              config.directed_samples
            )

    reconciliation = "model/quint/beamletReconciliation.qnt"

    primitives = [
      simulation(
        "reconciliation-init",
        reconciliation,
        "beamletReconciliation",
        "init",
        "reconciliationStep",
        "commandSafety",
        config.directed_samples
      ),
      simulation(
        "reconciliation-directed",
        @tests,
        "repeatingTests",
        "oldSuccessCurrentFailureInit",
        "reconciliationStep",
        "commandSafety",
        config.directed_samples,
        ~w(manualDecisionReached automaticDecisionReached exclusionDecisionReached adoptionDecisionReached)
      )
    ]

    commands =
      [
        simulation(
          "commands-init",
          reconciliation,
          "beamletReconciliation",
          "init",
          "commandStep",
          "commandSafety",
          config.directed_samples
        )
      ] ++
        for init <- ~w(oldSuccessCurrentFailureInit committedExclusionInit rejectedStaleInit),
            do:
              simulation(
                "commands-#{init}",
                @tests,
                "repeatingTests",
                init,
                "commandStep",
                "commandSafety",
                config.directed_samples,
                ~w(commandCommittedReached commandReplayReached staleCommandRejectedReached commandIdentityConflictReached rejectedCommandStoredReached readonlyReplayReached resultReadDeniedReached)
              )

    conflicts =
      for init <-
            ~w(conflictInit queriedConflictInit bothConflictsInit resolvedConflictInit allExcludedInit partiallySupersededInit),
          do:
            simulation(
              "conflicts-#{init}",
              "model/quint/beamletConflicts.qnt",
              "beamletConflicts",
              init,
              "conflictStep",
              "conflictSafety",
              config.directed_samples,
              ~w(conflictDispositionWitness conflictSuccessWitness conflictFailureWitness allExcludedWitness supersessionWitness)
            )

    rules =
      for init <- ~w(automaticRulePendingInit automaticRuleCommittedInit retiredRuleRejectedInit),
          do:
            simulation(
              "rules-#{init}",
              "model/quint/beamletRules.qnt",
              "beamletRules",
              init,
              "ruleVersionStep",
              "commandSafety",
              config.directed_samples,
              ~w(pinnedV1Witness pinnedV2Witness commandReplayReached rejectedCommandStoredReached)
            )

    retirements =
      for init <-
            ~w(ordinaryRetirementInit retirementBeforeDecisionInit retirementAfterClosureInit),
          do:
            simulation(
              "retirement-#{init}",
              "model/quint/beamletRules.qnt",
              "beamletRules",
              init,
              "retirementStep",
              "commandSafety",
              config.directed_samples,
              ~w(retiredDispositionUsedWitness retirementBindingPreservedWitness commandReplayReached rejectedCommandStoredReached)
            )

    withdrawals =
      for init <-
            ~w(withdrawalPendingInit withdrawnInit partiallyWithdrawnInit renewedWithdrawalInit),
          do:
            simulation(
              "withdrawals-#{init}",
              "model/quint/beamletWithdrawals.qnt",
              "beamletWithdrawals",
              init,
              "step",
              "safety",
              config.directed_samples,
              ~w(withdrawalWitness renewedJudgmentWitness commandReplayWitness conflictFailureWitness withdrawalOriginalReplayWitness crossKindIdentityConflictWitness)
            )

    normal =
      for init <- ~w(normalInit callbackRunningInit callbackReleasedInit retryPendingInit),
          do:
            simulation(
              "normal-#{init}",
              "model/quint/beamletNormalUse.qnt",
              "normalUseAnalysis",
              init,
              "normalStep",
              "normalSafety",
              config.directed_samples,
              ~w(submittedWitness reusedWitness callbackWitness releasedCompletionWitness readWitness retryWitness failureAtomicWitness discoveryWitness succeededReached failedReached waitingReached)
            )

    execution = [
      simulation(
        "execution-core",
        "model/quint/beamletExecution.qnt",
        "executionAnalysis",
        "init",
        "step",
        "safety",
        config.samples
      )
    ]

    recovery =
      for init <-
            ~w(init callbackRunningInit callbackReleasedInit retryPendingInit retryAuthorizedInit),
          do:
            simulation(
              "recovery-#{init}",
              "model/quint/beamletRecovery.qnt",
              "recoveryAnalysis",
              init,
              "step",
              "safety",
              config.directed_samples,
              ~w(recoveryCompletionWitness callbackRedeliveryWitness policyStopWitness succeededReached
                failedReached workerRestartReached coordinatorRestartReached messageLossReached expiryReached clockBackwardReached retryWitness)
            )

    projections =
      for init <- ~w(normalInit callbackReleasedInit retryPendingInit),
          do:
            simulation(
              "projection-#{init}",
              "model/quint/beamletExecution_test.qnt",
              "executionProjectionTests",
              init,
              "recoveryStep",
              "projectionSafety",
              config.directed_samples
            )

    multi_witnesses =
      ~w(bothInvokedWitness bothClosedWitness sharedWorkerWitness joinedWitness
      independentWitness partialJoinWitness recoveredJoinWitness releasedCompletionWitness unknownIsolationWitness)

    multi_intent =
      [
        simulation(
          "multi-independentInit",
          "model/quint/beamletMultiIntent.qnt",
          "multiIntentAnalysis",
          "independentInit",
          "healthyStep",
          "safety",
          config.samples,
          multi_witnesses
        )
      ] ++
        for {init, step} <- [
              {"joinedInit", "healthyStep"},
              {"releasedPairInit", "step"},
              {"unknownPairInit", "healthyStep"},
              {"retryPairInit", "step"},
              {"emptyInit", "step"}
            ],
            do:
              simulation(
                "multi-#{init}",
                "model/quint/beamletMultiIntent.qnt",
                "multiIntentAnalysis",
                init,
                step,
                "safety",
                config.directed_samples,
                multi_witnesses
              )

    continuation_witnesses =
      ~w(decisionWitness partialDecisionWitness manifestWitness partialSubmissionWitness
        successorSubmittedWitness recoveredManifestWitness recoveredReadWitness
        recoveredSuccessorWitness successorCompletedWitness)

    continuation =
      for {init, step, samples} <- [
            {"init", "healthyStep", config.samples},
            {"partialInit", "healthyStep", config.directed_samples},
            {"decidedInit", "step", config.directed_samples},
            {"submittedInit", "step", config.directed_samples},
            {"closedInit", "step", config.directed_samples}
          ],
          do:
            simulation(
              "continuation-#{init}",
              "model/quint/beamletContinuation.qnt",
              "continuationAnalysis",
              init,
              step,
              "safety",
              samples,
              continuation_witnesses
            )

    contracts =
      for {file, main, init, step, witnesses} <- [
            {"Claim", "claimAnalysis", "init", "healthyStep",
             ~w(allocatedWitness deliveredWitness calledWitness)},
            {"Claim", "claimAnalysis", "lostInit", "healthyStep",
             ~w(replayWitness deliveredWitness calledWitness)},
            {"Claim", "claimAnalysis", "lostInit", "step",
             ~w(replayWitness deliveredWitness calledWitness)},
            {"Resource", "resourceAnalysis", "init", "healthyStep",
             ~w(boundWitness calledWitness completedWitness)},
            {"Resource", "resourceAnalysis", "alternateInit", "healthyStep",
             ~w(migratedWorkerWitness completedWitness)},
            {"Resource", "resourceAnalysis", "boundInit", "step",
             ~w(calledWitness changedWitness completedWitness)},
            {"History", "historyAnalysis", "init", "healthyStep",
             ~w(committedWitness outcomeWitness duplicateWitness)},
            {"History", "historyAnalysis", "runningInit", "step",
             ~w(outcomeWitness rollbackWitness duplicateWitness)},
            {"Triple", "tripleAnalysis", "init", "healthyStep",
             ~w(invokedWitness twoCompletedWitness joinedWitness)},
            {"Triple", "tripleAnalysis", "restartedInit", "healthyStep",
             ~w(recoveredReadWitness joinedWitness)},
            {"Triple", "tripleAnalysis", "restartedInit", "step",
             ~w(recoveredReadWitness joinedWitness)},
            {"SharedResource", "sharedResourceAnalysis", "runningInit", "healthyStep",
             ~w(appliedWitness mismatchWitness replayWitness recoveryWitness closedWitness)},
            {"SharedResource", "sharedResourceAnalysis", "appliedInit", "step",
             ~w(mismatchWitness replayWitness recoveryWitness closedWitness)}
          ],
          do:
            simulation(
              "contract-#{file}-#{init}-#{step}",
              "model/quint/beamlet#{file}.qnt",
              main,
              init,
              step,
              "safety",
              config.directed_samples,
              witnesses
            )

    core ++
      prefixes ++
      primitives ++
      commands ++
      conflicts ++
      rules ++
      retirements ++
      withdrawals ++
      normal ++
      execution ++ recovery ++ projections ++ multi_intent ++ continuation ++ contracts
  end

  defp test_job(file, main),
    do:
      {:check, main <> ".test",
       ["test", file, "--main", main, "--seed", "42", "--max-samples", "1"]}

  defp simulation(name, file, main, init, step, invariant, samples, witnesses \\ []) do
    args = [
      "run",
      file,
      "--main",
      main,
      "--init",
      init,
      "--step",
      step,
      "--invariant",
      invariant,
      "--max-samples",
      to_string(samples),
      "--max-steps",
      "100",
      "--seed",
      "42",
      "--verbosity",
      "1"
    ]

    {:check, name <> ".run",
     args ++ if(witnesses == [], do: [], else: ["--witnesses" | witnesses])}
  end

  defp execute(job, executable, logs, threads) do
    started = System.monotonic_time(:millisecond)

    try do
      case job do
        {:check, name, args} ->
          path = Path.join(logs, name <> ".log")
          status = invoke(executable, args, path, threads)
          if status != 0, do: Mix.raise("Quint failed (exit #{status}); inspect #{path}")
          {:ok, name, System.monotonic_time(:millisecond) - started}

        {:mutation, main, file} ->
          test_log = Path.join(logs, main <> ".test.log")

          test_args = [
            "test",
            file,
            "--main",
            main,
            "--match",
            "mutationCaughtTest",
            "--seed",
            "42",
            "--max-samples",
            "1"
          ]

          status = invoke(executable, test_args, test_log, threads)

          if status != 0,
            do: Mix.raise("Mutation scenario failed (exit #{status}); inspect #{test_log}")

          log = Path.join(logs, main <> ".counterexample.log")
          trace = Path.join(logs, main <> ".itf.json")
          # A reused log directory must not let an old trace satisfy this run.
          case File.rm(trace) do
            :ok -> :ok
            {:error, :enoent} -> :ok
            {:error, reason} -> Mix.raise("Cannot clear old trace #{trace}: #{inspect(reason)}")
          end

          args = [
            "run",
            file,
            "--main",
            main,
            "--init",
            "mutantInit",
            "--step",
            "mutantStep",
            "--invariant",
            "mutantInvariant",
            "--max-samples",
            "1",
            "--max-steps",
            "1",
            "--seed",
            "42",
            "--verbosity",
            "1",
            "--out-itf",
            trace
          ]

          status = invoke(executable, args, log, 1)
          validate_counterexample!(status, File.read!(log), trace)
          {:ok, main, System.monotonic_time(:millisecond) - started}
      end
    rescue
      error ->
        {:error, elem(job, 1), Exception.message(error),
         System.monotonic_time(:millisecond) - started}
    end
  end

  defp invoke(executable, args, path, threads) do
    args =
      case hd(args) do
        "run" -> args ++ ["--backend", "rust", "--n-threads", to_string(threads)]
        "test" -> args ++ ["--backend", "rust"]
        _ -> args
      end

    File.open!(path, [:write], fn device ->
      {_stream, status} =
        System.cmd(executable, args,
          cd: @root,
          stderr_to_stdout: true,
          into: IO.stream(device, :line)
        )

      status
    end)
  end

  def validate_counterexample!(status, output, trace) do
    unless status == 1 and String.contains?(output, "Invariant violated") and
             File.regular?(trace) and File.stat!(trace).size > 0 do
      Mix.raise("Expected invariant counterexample missing (exit #{status}); inspect #{trace}")
    end

    :ok
  end
end
