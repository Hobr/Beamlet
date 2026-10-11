defmodule Beamlet.QuintChecks do
  @moduledoc false
  @root Path.expand("../..", __DIR__)
  @core "model/quint/beamletCore.qnt"
  @tests "model/quint/beamletCore_test.qnt"
  @conflicts "model/quint/beamletConflicts_test.qnt"
  @mutations "model/quint/beamletCore_mutations_test.qnt"
  @models ~w(beamletCore beamletCore_test beamletCore_mutations_test beamletReconciliation beamletConflicts beamletConflicts_test)
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

    for phase <- ~w(typecheck test simulate mutations),
        config.phase in ["all", phase] do
      config
      |> jobs(phase)
      |> Task.async_stream(
        fn job -> execute(job, executable, logs) end,
        max_concurrency: config.jobs,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.each(fn
        {:ok, {:ok, name}} -> Mix.shell().info("Passed #{phase}: #{name}")
        {:ok, {:error, message}} -> Mix.raise(message)
        {:exit, reason} -> Mix.raise("Quint worker exited: #{inspect(reason)}")
      end)
    end

    Mix.shell().info("Quint checks completed: #{config.phase}")
  end

  defp jobs(_config, "typecheck") do
    Enum.map(@models, &{:check, &1 <> ".typecheck", ["typecheck", "model/quint/#{&1}.qnt"]})
  end

  defp jobs(_config, "test") do
    Enum.map(~w(strictTests fencedTests repeatingTests), &test_job(@tests, &1)) ++
      [test_job(@conflicts, "conflictTests")]
  end

  defp jobs(_config, "mutations") do
    Enum.map(@core_mutations, &{:mutation, &1, @mutations}) ++
      Enum.map(@conflict_mutations, &{:mutation, &1, @conflicts})
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
              "commandSafety",
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

    core ++ prefixes ++ primitives ++ commands ++ conflicts
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

  defp execute(job, executable, logs) do
    try do
      case job do
        {:check, name, args} ->
          path = Path.join(logs, name <> ".log")
          status = invoke(executable, args, path)
          if status != 0, do: Mix.raise("Quint failed (exit #{status}); inspect #{path}")
          {:ok, name}

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

          status = invoke(executable, test_args, test_log)

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

          status = invoke(executable, args, log)
          validate_counterexample!(status, File.read!(log), trace)
          {:ok, main}
      end
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  defp invoke(executable, args, path) do
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
