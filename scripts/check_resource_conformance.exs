# Run at the repository root: mix run scripts/check_resource_conformance.exs
# Checks selected full SQL/resource histories against unmodified Quint projections.
defmodule BeamletResourceConformance do
  alias Beamlet.{Definition, Identity, Judgment, Report}
  alias BeamletRuntime.Coordinator
  alias BeamletRuntime.Handlers.FencedObject
  alias BeamletRuntime.Object.Store
  alias BeamletRuntime.Storage.SQLite

  @root Path.expand("..", __DIR__)
  def run do
    directory = Path.join(System.tmp_dir!(), "beamlet-resource-oracle-#{Ecto.UUID.generate()}")
    File.mkdir_p!(directory)
    File.cp_r!(Path.join(@root, "model/quint"), Path.join(directory, "model"))
    source = Path.join(directory, "oracle.qnt")
    trace = Path.join(directory, "oracle.itf.json")
    File.write!(source, oracle())
    invoke!(["typecheck", source])

    invoke!([
      "run",
      source,
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
      "--out-itf",
      trace
    ])

    states =
      trace
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("states")
      |> List.last()
      |> Map.fetch!("rows")
      |> decode()

    Enum.each([false, true], fn cancelled -> compare_trace!(directory, states, cancelled) end)

    IO.puts(
      "Quint/SQLite/resource conformance: 2 histories, 30 checkpoints passed (lost exclusion reply, full restart, replacement, resource commit, cancellation, late report, duplicate acknowledgements). Oracle: #{trace}"
    )
  end

  defp start(module, path) do
    {:ok, repo} = module.start_link(database: path, pool_size: 1)
    repo
  end

  defp compare_trace!(directory, rows, cancel) do
    suffix = if cancel, do: "cancelled", else: "success"
    authority_path = Path.join(directory, suffix <> "-authority.db")
    resource_path = Path.join(directory, suffix <> "-objects.db")
    authority = start(SQLite, authority_path)
    :ok = SQLite.migrate(authority)
    resource = start(Store, resource_path)
    {:ok, :ok} = Store.migrate(resource, "objects")
    service = Store.new(resource, "objects", "account")
    {:ok, _} = Store.create_object(service, "object", "initial")

    c =
      Coordinator.new(
        repo: authority,
        collection: "collection",
        actor: "local",
        handlers: [{FencedObject, %{service: service}}],
        ttl: 60_000
      )

    request = %{
      "service" => "objects",
      "account" => "account",
      "object" => "object",
      "expected_version" => 0,
      "content" => "new"
    }

    {:ok, definition} =
      Definition.new(%{
        operation: "object.fenced_replace_if_version.v1",
        input: request,
        policy: :retry_once
      })

    {:ok, identity} = Identity.new(c.collection, "agent", "key")
    {:ok, commit} = Coordinator.submit(c, identity, definition)
    id = commit.facts.intent.id
    check!(rows, 0, cancel, c, id, service)
    command!(c, id, {:create_execution, "1"})
    check!(rows, 1, cancel, c, id, service)
    old = claim!(c, id, "1")
    check!(rows, 2, cancel, c, id, service)
    g1 = authorize!(c, old)
    check!(rows, 3, cancel, c, id, service)
    {:ok, proof} = Store.fence(service, old, request)
    check!(rows, 4, cancel, c, id, service)
    # The exclusion response has not reached Authority. Both databases restart.
    Supervisor.stop(resource)
    Supervisor.stop(authority)
    resource = start(Store, resource_path)
    {:ok, :ok} = Store.migrate(resource, "objects")
    service = Store.new(resource, "objects", "account")
    authority = start(SQLite, authority_path)
    :ok = SQLite.migrate(authority)
    c = %{c | repo: authority, handlers: [{FencedObject, %{service: service}}]}
    {:ok, ^proof} = Store.read_fenced_receipt(service, old, request)
    {:uncertain, :object_execution_fenced} = FencedObject.invoke(g1, %{service: service})
    check!(rows, 5, cancel, c, id, service)
    {:ok, _} = Coordinator.query(c, id, "1")
    check!(rows, 6, cancel, c, id, service)
    command!(c, id, {:replace_execution, "1", "2", "verified exclusion"})
    check!(rows, 7, cancel, c, id, service)
    next = claim!(c, id, "2")
    check!(rows, 8, cancel, c, id, service)
    g2 = authorize!(c, next)
    check!(rows, 9, cancel, c, id, service)
    {:success, body} = FencedObject.invoke(g2, %{service: service})
    check!(rows, 10, cancel, c, id, service)
    if cancel, do: Coordinator.cancel(c, id, "stop")
    check!(rows, 11, cancel, c, id, service)

    report = %Report{
      id: "success",
      token: next,
      operation: definition.operation,
      kind: :success,
      body: body
    }

    {:ok, _} = Coordinator.worker_report(c, report)
    check!(rows, 12, cancel, c, id, service)
    {:ok, _} = Coordinator.query(c, id, "1")
    check!(rows, 13, cancel, c, id, service)
    {:ok, _} = Coordinator.worker_report(c, report)
    check!(rows, 14, cancel, c, id, service)
    Supervisor.stop(resource)
    Supervisor.stop(authority)
  end

  defp command!(c, id, command) do
    {:ok, commit} = SQLite.command(c.repo, c.collection, id, command, c.actor)
    commit
  end

  defp claim!(c, id, execution) do
    {:ok, %{reply: {:claimed, token}}} =
      Coordinator.claim(c, id, execution, "worker", "session", 0)

    token
  end

  defp authorize!(c, token) do
    {:ok, commit} =
      Coordinator.authorize(c, token, %{
        "object_service" => "objects",
        "object_account" => "account"
      })

    {:ok, grant} = Coordinator.grant(commit)
    grant
  end

  defp check!(rows, index, cancel, c, id, service) do
    {:ok, facts} = Coordinator.read(c, id)
    intent = facts.intent
    {:ok, object} = Store.read_object(service, "object")
    row = Enum.find(rows, &(&1["index"] == index and &1["cancel"] == cancel))

    actual = %{
      "phase" => Atom.to_string(intent.phase),
      "current" => intent.current_execution_id || "none",
      "old" => phase(intent, "1"),
      "next" => phase(intent, "2"),
      "oldKnowledge" => knowledge(intent, "1"),
      "nextKnowledge" => knowledge(intent, "2"),
      "revision" => intent.judgment_revision,
      "reports" => length(Judgment.reports(intent)),
      "conflictsFree" => Judgment.no_conflicts?(intent),
      "outcome" => if(intent.outcome, do: Atom.to_string(intent.outcome.kind), else: "none"),
      "version" => object["version"],
      "excluded" => excluded?(service, intent)
    }

    if actual != Map.take(row, Map.keys(actual)),
      do:
        raise(
          "SQL/resource trace mismatch at #{index}: #{inspect(row)} actual: #{inspect(actual)}"
        )
  end

  defp excluded?(service, intent) do
    case intent.executions["1"] do
      %{authorization: token} when not is_nil(token) ->
        match?(
          {:ok, %{kind: :not_executed}},
          Store.read_fenced_receipt(service, token, intent.definition.input)
        )

      _ ->
        false
    end
  end

  defp phase(intent, id),
    do: if(intent.executions[id], do: Atom.to_string(intent.executions[id].phase), else: "absent")

  defp knowledge(intent, id) do
    result = intent.executions[id] && intent.executions[id].result
    if result, do: Atom.to_string(result.kind), else: "none"
  end

  defp invoke!(args) do
    {output, status} = System.cmd("quint", args, stderr_to_stdout: true)
    if status != 0, do: raise("Quint failed: #{String.slice(output, 0, 4000)}")
  end

  defp decode(%{"#bigint" => n}), do: String.to_integer(n)
  defp decode(%{"#list" => xs}), do: Enum.map(xs, &decode/1)
  defp decode(x) when is_map(x), do: Map.new(x, fn {k, v} -> {k, decode(v)} end)
  defp decode(x) when is_list(x), do: Enum.map(x, &decode/1)
  defp decode(x), do: x

  defp oracle do
    """
    module oracle {
      import beamletCore(WORKERS=Set(1,2),EXECUTIONS=Set(1,2),REPORT_IDS=Set(1,2,3,4),
        CLOCK_VALUES=0.to(6),MAX_INCARNATION=2,MAX_GENERATION=3,TTL=2,ALLOW_REPEAT=false,CAN_FENCE=true).* from "./model/beamletCore"
      pure val t1:Token={exec:1,worker:1,incarnation:1,generation:1}
      pure val t2:Token={exec:2,worker:1,incarnation:1,generation:1}
      pure val exclusion:Report={id:3,exec:1,kind:NotExecuted,value:0,origin:ByQuery}
      pure val success:Report={id:4,exec:2,kind:Success,value:0,origin:ByWorker(t2)}
      pure val a=applyCreate(initialLedger,1)
      pure val b=applyClaim(a,1,1,1,0)
      pure val c=applyAuthorize(b,t1,0)
      pure val d=applyReport(c,exclusion)
      pure val e=applyReplace(d,1,2)
      pure val f=applyClaim(e,2,1,1,0)
      pure val g=applyAuthorize(f,t2,0)
      pure def phaseName(a:Attempt):str=if(not(a.exists)) "absent" else match a.phase {
        | Prepared=>"prepared" | StartAuthorized=>"start_authorized" | Waiting=>"waiting" | Unknown=>"unknown" | Resolved=>"resolved" }
      pure def knowledgeName(a:Attempt):str=match a.knowledge {
        | NoKnowledge=>"none" | SuccessKnown=>"success" | FailureKnown=>"failure" | NotExecutedKnown=>"not_executed" }
      type Row={index:int,cancel:bool,phase:str,current:str,old:str,next:str,oldKnowledge:str,nextKnowledge:str,
        revision:int,reports:int,conflictsFree:bool,outcome:str,version:int,excluded:bool}
      pure def row(index:int,cancel:bool,l:Ledger):Row={
        index:index,cancel:cancel,phase:if(l.phase==Open) "open" else "closed",
        current:if(l.current==NoCurrent) "none" else if(l.current==Current(1)) "1" else "2",
        old:phaseName(l.attempts.get(1)),next:phaseName(l.attempts.get(2)),
        oldKnowledge:knowledgeName(l.attempts.get(1)),nextKnowledge:knowledgeName(l.attempts.get(2)),
        revision:l.revision,reports:l.reports.size(),conflictsFree:noConflicts(l),
        outcome:if(l.outcomes.length()==0) "none" else if(l.outcomes.head().kind==OutcomeCancelled) "cancelled" else "succeeded",
        version:if(index>=10) 1 else 0,excluded:index>=4}
      pure def history(cancel:bool):List[Row]={
        val h=if(cancel) applyCommit(g,{kind:OutcomeCancelled,value:0,exec:NoCurrent}) else g
        val i=recordAndMaybeCommit(h,success)
        List(row(0,cancel,initialLedger),row(1,cancel,a),row(2,cancel,b),row(3,cancel,c),
          row(4,cancel,c),row(5,cancel,c),row(6,cancel,d),row(7,cancel,e),row(8,cancel,f),row(9,cancel,g),
          row(10,cancel,g),row(11,cancel,h),row(12,cancel,i),row(13,cancel,i),row(14,cancel,i))
      }
      var rows:List[Row]
      action oracleInit=all {init,rows'=history(false).concat(history(true))}
      action oracleStep=all {authority'=authority,workers'=workers,network'=network,external'=external,clock'=clock,rows'=rows}
    }
    """
  end
end

BeamletResourceConformance.run()
