# Run from apps/beamlet: mix run ../../scripts/check_domain_conformance.exs
# This oracle imports existing Quint logic; it does not duplicate its guards.
defmodule BeamletConformance do
  alias Beamlet.{Definition, Domain, Exclusion, Identity, Recovery, Report}
  alias Beamlet.Report.Source

  @root Path.expand("..", __DIR__)
  @context %{now: 0, actor: "authority"}
  @variants [
    {:worker, :pending, 0},
    {:worker, :success, 0},
    {:worker, :success, 1},
    {:worker, :failure, 0},
    {:worker, :failure, 1},
    {:query, :not_found, 0},
    {:query, :not_executed, 0},
    {:callback, :success, 0},
    {:callback, :failure, 0},
    {:query, :success, 0}
  ]

  def run do
    directory =
      Path.join(System.tmp_dir!(), "beamlet-conformance-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    File.cp_r!(Path.join(@root, "model/quint"), Path.join(directory, "model"))
    path = Path.join(directory, "oracle.qnt")
    trace = Path.join(directory, "oracle.itf.json")
    File.write!(path, oracle())
    invoke!(["typecheck", path])

    invoke!([
      "run",
      path,
      "--main",
      "oracle",
      "--init",
      "oracleInit",
      "--step",
      "oracleStep",
      "--max-samples",
      "1",
      "--max-steps",
      "0",
      "--backend",
      "rust",
      "--n-threads",
      "1",
      "--out-itf",
      trace
    ])

    document = trace |> File.read!() |> :json.decode()
    rows = document["states"] |> List.last() |> Map.fetch!("rows") |> decode()
    Enum.each(rows, &compare!/1)

    IO.puts(
      "Quint/Elixir conformance: #{length(rows)} ordered report cases passed. Oracle: #{trace}"
    )
  end

  defp invoke!(args) do
    {output, status} = System.cmd("quint", args, stderr_to_stdout: true)
    if status != 0, do: raise("Quint failed: #{String.slice(output, 0, 3000)}")
  end

  defp initial do
    {:ok, definition} =
      Definition.new(%{operation: "request.v1", input: nil, policy: :retry_once})

    {:ok, identity} = Identity.new("collection", "namespace", "key")
    {:ok, created} = Domain.new_intent("intent", identity, definition, @context)
    {:ok, prepared} = Domain.transition(created.intent, {:create_execution, "1"}, @context)
    {:ok, claimed} = Domain.transition(prepared.intent, {:claim, "1", "1", "1", 0, 2}, @context)
    {:claimed, token} = claimed.reply

    binding = %{
      "operation" => "request.v1",
      "handler" => "handler",
      "protocol" => "invoke.v1",
      "resource" => %{},
      "completion" => %{"protocol" => "callback.v1"},
      "query" => %{"protocol" => "query.v1"},
      "idempotency" => %{
        "protocol" => "dedupe.v1",
        "scope" => %{"account" => "account"},
        "key" => "key",
        "valid_through" => nil
      }
    }

    {:ok, authorized} = Domain.transition(claimed.intent, {:authorize, token, binding}, @context)
    {authorized.intent, token, binding}
  end

  defp compare!(row) do
    {intent, token, binding} = initial()

    {final, events} =
      Enum.with_index([row["a"], row["b"], row["c"]], 1)
      |> Enum.reduce({intent, 0}, fn {variant, position}, {state, count} ->
        id = if row["sameId"], do: "1", else: Integer.to_string(position)
        report = report(Enum.at(@variants, variant), id, token, binding)
        {:ok, transition} = Domain.transition(state, {:record_report, report}, @context)
        {transition.intent, count + length(transition.events)}
      end)

    execution = final.executions["1"]
    failure = Enum.find(execution.reports, &(&1.kind == :failure))

    actual = %{
      "knowledge" =>
        if(execution.result, do: Atom.to_string(execution.result.kind), else: "none"),
      "phase" => Atom.to_string(execution.phase),
      "conflict" => execution.conflict,
      "reports" => length(execution.reports),
      "events" => events,
      "succeeded" => final.outcome != nil,
      "safe" => match?({:ok, :not_executed}, Recovery.basis(execution, @context)),
      "failureEligible" => failure != nil and Recovery.failure_qualified?(final, failure)
    }

    expected = Map.take(row, Map.keys(actual))

    if actual != expected,
      do: raise("Conformance mismatch: #{inspect(row)} actual: #{inspect(actual)}")
  end

  defp report({:worker, kind, value}, id, token, _binding),
    do: %Report{id: id, token: token, operation: "request.v1", kind: kind, body: value}

  defp report({origin, kind, value}, id, token, binding) do
    key = if origin == :query, do: "query", else: "completion"

    source = %Source{
      kind: origin,
      collection: "collection",
      intent_id: "intent",
      execution_id: "1",
      binding: binding[key]
    }

    exclusion =
      if kind == :not_executed,
        do: %Exclusion{authorization: token, query_binding: binding[key], evidence_ref: "receipt"}

    %Report{
      id: id,
      source: source,
      operation: "request.v1",
      kind: kind,
      body: value,
      exclusion: exclusion
    }
  end

  defp decode(%{"#bigint" => value}), do: String.to_integer(value)
  defp decode(%{"#list" => values}), do: Enum.map(values, &decode/1)
  defp decode(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, decode(v)} end)
  defp decode(value) when is_list(value), do: Enum.map(value, &decode/1)
  defp decode(value), do: value

  defp oracle do
    """
    module oracle {
      import beamletExecution(WORKERS = Set(1,2), EXECUTIONS = Set(1,2), REPORT_IDS = Set(1,2,3,4),
        CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
        ALLOW_REPEAT = false, CAN_FENCE = false).* from "./model/beamletExecution"
      pure val token: Token = {exec: 1, worker: 1, incarnation: 1, generation: 1}
      pure val kinds = List(Pending, Success, Success, Failure, Failure, NotFound, NotExecuted, Success, Failure, Success)
      pure def reportAt(n: int, id: int): Report = {id: id, exec: 1, kind: kinds.nth(n),
        value: if (n == 2 or n == 4) 1 else 0,
        origin: if (n < 5) ByWorker(token) else if (n == 7 or n == 8) ByCallback(1) else ByQuery}
      pure val claimed = applyClaim(applyCreate(initialLedger, 1), 1, 1, 1, 0)
      pure val authorized = applyAuthorize(claimed, token, 0)
      pure val base = {...authorized, attempts: authorized.attempts.set(1,
        {...authorized.attempts.get(1), completion: CallbackBinding(1)})}
      pure def receive(l: Ledger, r: Report): Ledger =
        if (l.reports.contains(r)) l else recordAndMaybeCommit(l, r)
      type Row = {a: int, b: int, c: int, sameId: bool, knowledge: str, phase: str,
        conflict: bool, reports: int, events: int, succeeded: bool, safe: bool, failureEligible: bool}
      pure def row(a: int, b: int, c: int, sameId: bool): Row = {
        val l = receive(receive(receive(base, reportAt(a, 1)), reportAt(b, if (sameId) 1 else 2)),
          reportAt(c, if (sameId) 1 else 3))
        val attempt = l.attempts.get(1)
        {a: a, b: b, c: c, sameId: sameId,
          knowledge: if (attempt.knowledge == SuccessKnown) "success" else if (attempt.knowledge == FailureKnown) "failure"
            else if (attempt.knowledge == NotExecutedKnown) "not_executed" else "none",
          phase: if (attempt.phase == Waiting) "waiting" else if (attempt.phase == Resolved) "resolved" else "start_authorized",
          conflict: attempt.conflict, reports: l.reports.size(), events: l.history.length() - base.history.length(),
          succeeded: l.outcomes.length() > 0, safe: safeToReplace(l, 1),
          failureEligible: sourceEligible(l, {kind: OutcomeFailed, exec: Current(1), value: 0})
            or sourceEligible(l, {kind: OutcomeFailed, exec: Current(1), value: 1})}
      }
      var rows: List[Row]
      action oracleInit = all {init,
        rows' = 0.to(9).fold(List(), (xs, a) => xs.concat(0.to(9).fold(List(), (ys, b) =>
          ys.concat(0.to(9).fold(List(), (zs, c) => zs.append(row(a,b,c,false)).append(row(a,b,c,true))))))),
      }
      action oracleStep = all {authority' = authority, workers' = workers, network' = network,
        external' = external, clock' = clock, rows' = rows}
    }
    """
  end
end

BeamletConformance.run()
