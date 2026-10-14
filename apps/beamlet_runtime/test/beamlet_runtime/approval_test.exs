defmodule BeamletRuntime.ApprovalTest do
  use ExUnit.Case, async: false
  alias Beamlet.{Definition, Identity}
  alias BeamletRuntime.Approval.Store
  alias BeamletRuntime.{Coordinator, Scheduler, Worker}
  alias BeamletRuntime.Handlers.Approval
  alias BeamletRuntime.Storage.{Commit, SQLite}

  setup do
    directory =
      Path.join(System.tmp_dir!(), "beamlet-approval-#{System.unique_integer([:positive])}")

    authority_path = Path.join(directory, "authority.db")
    resource_path = Path.join(directory, "approvals.db")
    {:ok, authority} = SQLite.start_link(database: authority_path, pool_size: 1)
    {:ok, resource} = Store.start_link(database: resource_path, pool_size: 1)
    Process.unlink(authority)
    Process.unlink(resource)
    :ok = SQLite.migrate(authority)
    assert {:ok, :ok} = Store.migrate(resource, "approval-service")
    service = Store.new(resource, "approval-service")
    c = coordinator(authority, service)

    on_exit(fn ->
      for repo <- [authority, resource], Process.alive?(repo), do: Supervisor.stop(repo)
      File.rm_rf!(directory)
    end)

    %{
      c: c,
      service: service,
      resource: resource,
      resource_path: resource_path,
      authority_path: authority_path,
      authority: authority
    }
  end

  defp coordinator(repo, service),
    do:
      Coordinator.new(
        repo: repo,
        collection: "collection",
        actor: "local-runtime",
        handlers: [{Approval, %{service: service}}],
        ttl: 1000
      )

  defp input(subject \\ %{"text" => "请批准"}),
    do: %{"service" => "approval-service", "subject" => subject, "responders" => ["reviewer"]}

  defp submit(c, key \\ "approval", policy \\ :stop_on_failure) do
    {:ok, identity} = Identity.new(c.collection, "agent", key)

    {:ok, definition} =
      Definition.new(%{operation: "human.approval.v1", input: input(), policy: policy})

    assert {:ok, commit} = Coordinator.submit(c, identity, definition)
    commit.facts.intent.id
  end

  defp worker(c),
    do:
      start_supervised!(
        Supervisor.child_spec(
          {Worker,
           coordinator: c,
           id: Ecto.UUID.generate(),
           environment: %{"approval_service" => "approval-service"}},
          id: make_ref()
        )
      )

  defp facts(c, id) do
    assert {:ok, facts} = Coordinator.read(c, id)
    facts
  end

  defp execution(c, id) do
    intent = facts(c, id).intent
    intent.executions[intent.current_execution_id]
  end

  defp awaiting(c, id), do: eventually(fn -> execution(c, id).phase == :waiting end)

  defp eventually(fun, attempts \\ 200) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("expected persisted progress")

      true ->
        receive do
        after
          5 -> :ok
        end

        eventually(fun, attempts - 1)
    end
  end

  defp grant(c, w, id) do
    assert {:ok, prepared} = Coordinator.prepare(c, id)
    e = prepared.facts.intent.current_execution_id
    {worker_id, incarnation} = Worker.session(w)

    assert {:ok, %Commit{reply: {:claimed, token}}} =
             Coordinator.claim(c, id, e, worker_id, incarnation, 0)

    assert {:ok, authorized} =
             Coordinator.authorize(c, token, %{"approval_service" => "approval-service"})

    assert {:ok, grant} = Coordinator.grant(authorized)
    grant
  end

  test "approval Pending releases Worker; query accepts approved or denied as Success", %{
    c: c,
    service: service
  } do
    for decision <- ["approved", "denied"] do
      id = submit(c, decision)
      w = worker(c)
      assert {:ok, _page} = Scheduler.scan_once(c, [w])
      awaiting(c, id)
      saved = execution(c, id)
      assert saved.binding["completion"]["approval_ref"] == id
      assert {:ok, %{decision: nil}} = Store.read(service, c.collection, id)
      GenServer.stop(w)
      assert {:ok, decided} = Store.decide(service, c.collection, id, "reviewer", decision)
      assert {:ok, commit} = Coordinator.query(c, id, saved.id)
      assert commit.facts.intent.outcome.kind == :succeeded

      assert commit.facts.intent.outcome.value == %{
               "decision" => decision,
               "approval_ref" => id,
               "decision_ref" => decided.decision_ref
             }
    end
  end

  test "creation response loss recovers through original query without another approval", %{
    c: c,
    service: service
  } do
    id = submit(c)
    g = grant(c, worker(c), id)
    assert {:pending, %{"approval_ref" => ^id}} = Approval.invoke(g, %{service: service})
    # External resource committed; deliberately discard the Worker response.
    assert execution(c, id).phase == :start_authorized
    assert facts(c, id).intent.outcome == nil
    assert {:ok, decided} = Store.decide(service, c.collection, id, "reviewer", "denied")
    assert {:ok, commit} = Coordinator.query(c, id, g.token.execution_id)
    assert commit.facts.intent.outcome.value["decision_ref"] == decided.decision_ref
    assert {:success, body} = Approval.invoke(g, %{service: service})
    assert body == commit.facts.intent.outcome.value
  end

  test "early decision/query precedes Pending without regressing resolved state", %{
    c: c,
    service: service
  } do
    id = submit(c)
    g = grant(c, worker(c), id)
    assert {:ok, _created} = Store.create(service, c.collection, id, input())
    assert {:ok, _decided} = Store.decide(service, c.collection, id, "reviewer", "approved")
    assert {:ok, _commit} = Coordinator.query(c, id, g.token.execution_id)

    pending = %Beamlet.Report{
      id: "late-pending",
      token: g.token,
      operation: "human.approval.v1",
      kind: :pending,
      body: %{"approval_ref" => id}
    }

    assert {:ok, stored} = Coordinator.worker_report(c, pending)
    assert stored.facts.intent.executions[g.token.execution_id].phase == :resolved
    assert stored.facts.intent.outcome.kind == :succeeded
    assert length(stored.facts.intent.executions[g.token.execution_id].reports) == 2
  end

  test "unauthorized responders and changed decisions do not overwrite durable receipt", %{
    service: service
  } do
    assert {:ok, _created} = Store.create(service, "collection", "id", input())

    assert {:error, :responder_not_authorized} =
             Store.decide(service, "collection", "id", "intruder", "approved")

    assert {:ok, %{decision: nil}} = Store.read(service, "collection", "id")
    assert {:ok, original} = Store.decide(service, "collection", "id", "reviewer", "denied")
    assert {:ok, ^original} = Store.decide(service, "collection", "id", "reviewer", "denied")

    assert {:error, :approval_already_decided} =
             Store.decide(service, "collection", "id", "reviewer", "approved")

    assert {:ok, ^original} = Store.read(service, "collection", "id")
  end

  test "same resource key deduplicates creation but changed request is rejected", %{
    service: service
  } do
    assert {:ok, original} = Store.create(service, "collection", "id", input())
    assert {:ok, ^original} = Store.create(service, "collection", "id", input())

    assert {:error, :approval_request_conflict} =
             Store.create(service, "collection", "id", input("changed"))

    assert {:ok, ^original} = Store.read(service, "collection", "id")
    assert {:ok, _different_scope} = Store.create(service, "other", "id", input("other"))
  end

  test "approve/deny competition serializes at resource with one immutable decision", %{
    service: service
  } do
    {:ok, _created} = Store.create(service, "collection", "id", input())

    tasks =
      for decision <- ["approved", "denied"],
          do:
            Task.async(fn -> Store.decide(service, "collection", "id", "reviewer", decision) end)

    replies = Task.await_many(tasks)
    assert Enum.count(replies, &match?({:ok, _receipt}, &1)) == 1
    assert Enum.count(replies, &(&1 == {:error, :approval_already_decided})) == 1
    assert {:ok, receipt} = Store.read(service, "collection", "id")
    assert Enum.member?(replies, {:ok, receipt})
  end

  test "query observations are stable; missing/pending are not negative execution proof", %{
    c: c,
    service: service
  } do
    id = submit(c)
    g = grant(c, worker(c), id)
    assert {:ok, missing} = Coordinator.query(c, id, g.token.execution_id)
    assert missing.facts.intent.outcome == nil
    assert execution(c, id).exclusion == nil
    assert execution(c, id).phase == :start_authorized
    assert {:ok, same} = Coordinator.query(c, id, g.token.execution_id)
    assert same.events == []
    assert same.facts.revision == missing.facts.revision
    {:ok, _created} = Store.create(service, c.collection, id, input())
    assert {:ok, pending} = Coordinator.query(c, id, g.token.execution_id)
    assert pending.facts.intent.outcome == nil
    refute execution(c, id).conflict
    assert {:ok, _decided} = Store.decide(service, c.collection, id, "reviewer", "approved")
    assert {:ok, complete} = Coordinator.query(c, id, g.token.execution_id)
    assert {:ok, replay} = Coordinator.query(c, id, g.token.execution_id)
    assert replay.facts.revision == complete.facts.revision
    assert replay.events == []
    refute execution(c, id).conflict
  end

  test "persistent service identity prevents accidentally substituting another account", %{
    resource: resource,
    service: service
  } do
    assert {:error, :approval_service_mismatch} = Store.migrate(resource, "different-service")
    wrong = %{service | identity: "different-service"}
    assert {:error, :approval_service_mismatch} = Store.read(wrong, "collection", "id")

    assert {:error, :approval_service_mismatch} =
             Store.create(service, "collection", "id", %{
               input()
               | "service" => "different-service"
             })
  end

  test "resource Repo and Worker restart preserve original waiting association and decision", %{
    c: c,
    service: service,
    resource: resource,
    resource_path: path,
    authority: authority
  } do
    id = submit(c)
    w = worker(c)
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    awaiting(c, id)
    original_binding = execution(c, id).binding
    GenServer.stop(w)
    Supervisor.stop(resource)
    assert {:error, :approval_service_unavailable} = Coordinator.query(c, id, execution(c, id).id)
    assert facts(c, id).intent.outcome == nil
    {:ok, restarted} = Store.start_link(database: path, pool_size: 1)
    Process.unlink(restarted)
    on_exit(fn -> if Process.alive?(restarted), do: Supervisor.stop(restarted) end)
    assert {:ok, :ok} = Store.migrate(restarted, service.identity)
    fresh_service = Store.new(restarted, service.identity)
    fresh = coordinator(authority, fresh_service)
    assert {:ok, _decided} = Store.decide(fresh_service, c.collection, id, "reviewer", "denied")
    assert {:ok, _page} = Scheduler.scan_once(fresh, [worker(fresh)])
    assert facts(fresh, id).intent.outcome.value["decision"] == "denied"
    assert execution(fresh, id).binding == original_binding
    assert map_size(facts(fresh, id).intent.executions) == 1
  end

  test "all execution and database processes can restart and settle the original approval", %{
    c: c,
    service: service,
    authority: authority,
    resource: resource,
    authority_path: authority_path,
    resource_path: resource_path
  } do
    id = submit(c)
    w = worker(c)
    assert {:ok, _page} = Scheduler.scan_once(c, [w])
    awaiting(c, id)
    binding = execution(c, id).binding
    {:ok, original} = Store.decide(service, c.collection, id, "reviewer", "approved")
    GenServer.stop(w)
    Supervisor.stop(authority)
    Supervisor.stop(resource)
    {:ok, new_authority} = SQLite.start_link(database: authority_path, pool_size: 1)
    {:ok, new_resource} = Store.start_link(database: resource_path, pool_size: 1)
    Process.unlink(new_authority)
    Process.unlink(new_resource)

    on_exit(fn ->
      for repo <- [new_authority, new_resource], Process.alive?(repo), do: Supervisor.stop(repo)
    end)

    fresh_service = Store.new(new_resource, service.identity)
    assert fresh_service.instance == service.instance
    fresh = coordinator(new_authority, fresh_service)
    assert {:ok, _page} = Scheduler.scan_once(fresh, [worker(fresh)])
    intent = facts(fresh, id).intent
    assert intent.outcome.value["decision_ref"] == original.decision_ref
    assert execution(fresh, id).binding == binding
    assert map_size(intent.executions) == 1
    assert submit(fresh) == id
  end

  test "cancel does not stop external approval; late decision is preserved without replacing Outcome",
       %{c: c, service: service} do
    id = submit(c)
    assert {:ok, _page} = Scheduler.scan_once(c, [worker(c)])
    awaiting(c, id)
    e = execution(c, id).id
    assert {:ok, _cancelled} = Coordinator.cancel(c, id, "user cancelled")
    assert {:ok, _decision} = Store.decide(service, c.collection, id, "reviewer", "approved")
    assert {:ok, late} = Coordinator.query(c, id, e)
    assert late.facts.intent.outcome.kind == :cancelled
    assert Enum.any?(late.facts.intent.executions[e].reports, &(&1.kind == :success))
  end

  test "safe replacement reuses original approval creation key and existing decision", %{
    c: c,
    service: service
  } do
    id = submit(c, "retry", :retry_once)
    fast = %{c | ttl: 100}
    g = grant(fast, worker(fast), id)
    assert {:pending, _body} = Approval.invoke(g, %{service: service})

    eventually(fn ->
      match?({:ok, _commit}, Coordinator.expire(fast, id, g.token.execution_id))
    end)

    assert {:ok, replaced} = Coordinator.recover(fast, id)
    next = replaced.facts.intent.current_execution_id
    refute next == g.token.execution_id
    assert {:ok, receipt} = Store.decide(service, c.collection, id, "reviewer", "approved")
    w = worker(fast)
    assert :started = Worker.run(w, id, next)
    eventually(fn -> facts(fast, id).intent.outcome != nil end)
    intent = facts(fast, id).intent
    assert intent.outcome.execution_id == next
    assert intent.outcome.value["decision_ref"] == receipt.decision_ref
    assert intent.executions[next].binding["idempotency"] == g.binding["idempotency"]
    assert {:ok, ^receipt} = Store.read(service, c.collection, id)
    assert map_size(intent.executions) == 2
  end

  test "independent resource Repos deduplicate concurrent requests using SQL protection", %{
    service: service,
    resource_path: path
  } do
    {:ok, second} = Store.start_link(database: path, pool_size: 1, busy_timeout: 1000)
    Process.unlink(second)
    on_exit(fn -> if Process.alive?(second), do: Supervisor.stop(second) end)
    other = Store.new(second, service.identity)

    tasks =
      for configured <- [service, other],
          do: Task.async(fn -> Store.create(configured, "collection", "same", input()) end)

    assert [{:ok, first}, {:ok, same}] = Task.await_many(tasks)
    assert first == same
    assert {:ok, receipt} = Store.decide(other, "collection", "same", "reviewer", "approved")
    assert {:ok, ^receipt} = Store.read(service, "collection", "same")
  end

  test "resource service mismatch is uncertainty, not a guessed Failure", %{
    c: c,
    service: service
  } do
    id = submit(c)
    g = grant(c, worker(c), id)
    wrong = %{service | identity: "other-service"}
    assert {:uncertain, :approval_service_mismatch} = Approval.invoke(g, %{service: wrong})

    assert {:error, :approval_service_mismatch} =
             Coordinator.query(
               %{c | handlers: [{Approval, %{service: wrong}}]},
               id,
               g.token.execution_id
             )

    assert facts(c, id).intent.outcome == nil
    assert execution(c, id).reports == []
  end

  test "same-named new resource database cannot inherit a saved grant or deduplication guarantee",
       %{c: c, service: service, resource_path: path} do
    id = submit(c)
    g = grant(c, worker(c), id)
    {:ok, replacement} = Store.start_link(database: path <> ".replacement", pool_size: 1)
    Process.unlink(replacement)
    on_exit(fn -> if Process.alive?(replacement), do: Supervisor.stop(replacement) end)
    assert {:ok, :ok} = Store.migrate(replacement, service.identity)
    fresh_service = Store.new(replacement, service.identity)
    refute fresh_service.instance == service.instance

    assert {:uncertain, :approval_service_mismatch} =
             Approval.invoke(g, %{service: fresh_service})

    assert {:error, :approval_service_mismatch} =
             Store.read(%{service | repo: replacement}, c.collection, id)

    assert {:error, :approval_service_mismatch} =
             Coordinator.query(
               %{c | handlers: [{Approval, %{service: fresh_service}}]},
               id,
               g.token.execution_id
             )

    assert {:error, :approval_resource_mismatch} =
             Approval.validate_binding(
               g.intent,
               g.binding,
               %{"approval_service" => service.identity},
               %{service: fresh_service}
             )

    assert facts(c, id).intent.outcome == nil
    assert {:error, :approval_not_found} = Store.read(fresh_service, c.collection, id)
  end

  test "shared Worker isolates colliding local Execution IDs and recovers each caller slot independently",
       %{c: c, service: service} do
    first = submit(c, "slot-a")
    second = submit(c, "slot-b")

    for id <- [first, second] do
      assert {:ok, _commit} =
               SQLite.command(
                 c.repo,
                 c.collection,
                 id,
                 {:create_execution, "same-local-id"},
                 c.actor
               )
    end

    w = worker(c)
    first_grant = grant(c, w, first)
    second_grant = grant(c, w, second)
    assert first_grant.token.execution_id == second_grant.token.execution_id

    assert {:error, :grant_scope_mismatch} =
             Worker.deliver(w, %{first_grant | intent: second_grant.intent})

    assert :started = Worker.deliver(w, first_grant)
    assert :started = Worker.deliver(w, second_grant)
    awaiting(c, first)
    awaiting(c, second)
    before_second = facts(c, second)
    assert {:ok, _decision} = Store.decide(service, c.collection, first, "reviewer", "approved")
    assert {:ok, completed} = Coordinator.query(c, first, first_grant.token.execution_id)
    assert completed.facts.intent.outcome.value["approval_ref"] == first
    assert facts(c, second) == before_second
    GenServer.stop(w)
    fresh = worker(c)
    assert {:error, :foreign_incarnation} = Worker.deliver(fresh, first_grant)
    assert {:error, :foreign_incarnation} = Worker.deliver(fresh, second_grant)

    # Rebuild caller slots using their original stable submission identities, not notification counts.
    assert submit(c, "slot-a") == first
    assert submit(c, "slot-b") == second
    assert facts(c, first).intent.outcome != nil
    assert facts(c, second).intent.outcome == nil
    assert {:ok, _decision} = Store.decide(service, c.collection, second, "reviewer", "denied")
    assert {:ok, _page} = Scheduler.scan_once(c, [fresh])
    assert facts(c, second).intent.outcome.value["approval_ref"] == second
    assert facts(c, second).intent.outcome.value["decision"] == "denied"
    assert facts(c, first).intent.outcome == completed.facts.intent.outcome
    assert map_size(facts(c, first).intent.executions) == 1
    assert map_size(facts(c, second).intent.executions) == 1
  end

  test "operation schemas reject ambiguous inputs, runtime objects and unsupported results", %{
    c: c,
    service: service
  } do
    for invalid <- [
          %{"subject" => "missing"},
          %{input() | "responders" => []},
          %{input() | "responders" => ["reviewer", "reviewer"]},
          input(self())
        ] do
      {:ok, identity} = Identity.new(c.collection, "agent", Ecto.UUID.generate())
      assert {:error, _reason} = Store.validate_request(invalid)

      case Definition.new(%{operation: "human.approval.v1", input: invalid}) do
        {:ok, definition} ->
          assert {:error, _reason} = Coordinator.submit(c, identity, definition)

        {:error, _reason} ->
          :ok
      end
    end

    assert {:error, :invalid_approval_result} =
             Approval.validate_result("human.approval.v1", :success, %{"decision" => "denied"}, %{
               service: service
             })

    assert {:error, :invalid_approval_result} =
             Approval.validate_result("human.approval.v1", :failure, "timeout", %{
               service: service
             })

    assert_raise ArgumentError, fn -> Store.start_link(database: ":memory:") end
  end
end
