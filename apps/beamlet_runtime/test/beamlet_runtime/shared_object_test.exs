defmodule BeamletRuntime.SharedObjectTest do
  use ExUnit.Case, async: false
  alias Beamlet.{Definition, Identity}
  alias BeamletRuntime.{Coordinator, Scheduler, Worker}
  alias BeamletRuntime.Handlers.SharedObject
  alias BeamletRuntime.Object.Store
  alias BeamletRuntime.Storage.{Commit, SQLite}
  alias Ecto.Adapters.SQL

  setup do
    directory =
      Path.join(System.tmp_dir!(), "beamlet-object-#{System.unique_integer([:positive])}")

    authority_path = Path.join(directory, "authority.db")
    resource_path = Path.join(directory, "objects.db")
    {authority_child, authority} = repo(SQLite, authority_path)
    {resource_child, resource} = repo(Store, resource_path)
    :ok = SQLite.migrate(authority)
    assert {:ok, :ok} = Store.migrate(resource, "object-service")
    service = Store.new(resource, "object-service", "account")
    assert {:ok, %{"version" => 0}} = Store.create_object(service, "shared", "initial")
    c = coordinator(authority, service)
    on_exit(fn -> File.rm_rf!(directory) end)

    %{
      c: c,
      service: service,
      resource: resource,
      resource_path: resource_path,
      resource_child: resource_child,
      authority: authority,
      authority_path: authority_path,
      authority_child: authority_child
    }
  end

  defp repo(module, path) do
    child = make_ref()

    {child,
     start_supervised!(Supervisor.child_spec({module, database: path, pool_size: 1}, id: child))}
  end

  defp coordinator(repo, service),
    do:
      Coordinator.new(
        repo: repo,
        collection: "collection",
        actor: "trusted-local",
        handlers: [{SharedObject, %{service: service}}],
        ttl: 1000
      )

  defp input(content \\ "new", expected \\ 0, object \\ "shared"),
    do: %{
      "service" => "object-service",
      "account" => "account",
      "object" => object,
      "expected_version" => expected,
      "content" => content
    }

  defp submit(c, key, request \\ input(), policy \\ :stop_on_failure) do
    {:ok, identity} = Identity.new(c.collection, "agent", key)

    {:ok, definition} =
      Definition.new(%{operation: "object.replace_if_version.v1", input: request, policy: policy})

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
           environment: %{"object_service" => "object-service", "object_account" => "account"}},
          id: make_ref()
        )
      )

  defp grant(c, w, id) do
    assert {:ok, prepared} = Coordinator.prepare(c, id)
    execution = prepared.facts.intent.current_execution_id
    {worker_id, incarnation} = Worker.session(w)

    assert {:ok, %Commit{reply: {:claimed, token}}} =
             Coordinator.claim(c, id, execution, worker_id, incarnation, 0)

    assert {:ok, authorized} =
             Coordinator.authorize(c, token, %{
               "object_service" => "object-service",
               "object_account" => "account"
             })

    assert {:ok, grant} = Coordinator.grant(authorized)
    grant
  end

  defp facts(c, id) do
    assert {:ok, facts} = Coordinator.read(c, id)
    facts
  end

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

  test "two independent requests at version zero produce one write and immutable applied/mismatch receipts",
       %{service: service} do
    first = input("first")
    second = input("second")
    assert {:ok, won} = Store.replace(service, "collection", "a", first)
    assert won.body["applied"]
    assert won.body["version"] == 1
    assert {:ok, lost} = Store.replace(service, "collection", "b", second)
    assert lost.body["applied"] == false
    assert lost.body["reason"] == "version_mismatch"
    assert lost.body["version"] == 1
    assert {:ok, %{"version" => 1, "content" => "first"}} = Store.read_object(service, "shared")
    assert {:ok, ^won} = Store.replace(service, "collection", "a", first)
    assert {:ok, ^lost} = Store.replace(service, "collection", "b", second)

    assert {:error, :object_request_conflict} =
             Store.replace(service, "collection", "a", input("changed"))

    assert {:ok, ^won} = Store.read_receipt(service, "collection", "a", first)
  end

  test "two Runtime Intents competing for one version both Succeed with their own receipts", %{
    c: c,
    service: service
  } do
    ids = [submit(c, "first", input("first")), submit(c, "second", input("second"))]
    assert {:ok, _page} = Scheduler.scan_once(c, [worker(c), worker(c)])
    eventually(fn -> Enum.all?(ids, &(facts(c, &1).intent.outcome != nil)) end)
    outcomes = Enum.map(ids, &facts(c, &1).intent.outcome)
    assert Enum.all?(outcomes, &(&1.kind == :succeeded))
    assert Enum.sort(Enum.map(outcomes, & &1.value["applied"])) == [false, true]
    winner = Enum.find(ids, &facts(c, &1).intent.outcome.value["applied"])
    expected = facts(c, winner).intent.definition.input["content"]
    assert {:ok, %{"version" => 1, "content" => ^expected}} = Store.read_object(service, "shared")

    for id <- ids do
      f = facts(c, id)
      e = f.intent.executions[f.intent.current_execution_id]
      assert e.binding["idempotency"]["key"] == id

      assert {:ok, receipt} =
               Store.read_receipt(service, c.collection, id, f.intent.definition.input)

      assert f.intent.outcome.value == receipt.body
      assert {:ok, queried} = Coordinator.query(c, id, e.id)
      assert queried.facts.intent.outcome == f.intent.outcome
      assert {:ok, duplicate} = Coordinator.query(c, id, e.id)
      assert duplicate.facts.revision == queried.facts.revision
    end
  end

  test "lost resource response is recovered by query after Worker loss without another write", %{
    c: c,
    service: service
  } do
    id = submit(c, "lost")
    w = worker(c)
    g = grant(c, w, id)
    assert {:success, body} = SharedObject.invoke(g, %{service: service})
    GenServer.stop(w)
    assert facts(c, id).intent.outcome == nil
    assert {:ok, commit} = Coordinator.query(c, id, g.token.execution_id)
    assert commit.facts.intent.outcome.value == body
    assert {:success, ^body} = SharedObject.invoke(g, %{service: service})
    assert {:ok, %{"version" => 1, "content" => "new"}} = Store.read_object(service, "shared")
  end

  test "missing receipt is NotFound even when another request wrote identical content", %{
    c: c,
    service: service
  } do
    id = submit(c, "missing", input("same"), :retry_once)
    g = grant(c, worker(c), id)
    assert {:ok, _receipt} = Store.replace(service, c.collection, "other-intent", input("same"))
    assert {:ok, commit} = Coordinator.query(c, id, g.token.execution_id)
    execution = commit.facts.intent.executions[g.token.execution_id]
    assert execution.result == nil
    assert execution.exclusion == nil
    assert Enum.map(execution.reports, & &1.kind) == [:not_found]
    assert commit.facts.intent.outcome == nil
    assert {:ok, %{"version" => 1, "content" => "same"}} = Store.read_object(service, "shared")
    assert {:ok, duplicate} = Coordinator.query(c, id, g.token.execution_id)
    assert duplicate.facts.revision == commit.facts.revision
  end

  test "independent Repos serialize concurrent CAS and duplicate scoped keys", %{
    service: service,
    resource_path: path
  } do
    {_child, peer_repo} = repo(Store, path)
    assert {:ok, :ok} = Store.migrate(peer_repo, service.identity)
    peer = Store.new(peer_repo, service.identity, service.account)

    tasks =
      for {instance, id} <- [{service, "a"}, {peer, "b"}],
          do: Task.async(fn -> Store.replace(instance, "collection", id, input(id)) end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.all?(results, &match?({:ok, _}, &1))
    applied = Enum.map(results, fn {:ok, receipt} -> receipt.body["applied"] end)
    assert Enum.sort(applied) == [false, true]

    tasks =
      for instance <- [service, peer, service, peer],
          do:
            Task.async(fn -> Store.replace(instance, "collection", "same", input("third", 1)) end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert length(Enum.uniq(results)) == 1
    assert {:ok, %{"version" => 2, "content" => "third"}} = Store.read_object(service, "shared")
  end

  test "resource update rolls back if receipt insertion fails", %{
    service: service,
    resource: resource
  } do
    SQL.query!(
      resource,
      "CREATE TRIGGER fail_receipt BEFORE INSERT ON object_receipts BEGIN SELECT RAISE(ABORT, 'fault injection'); END",
      []
    )

    assert {:error, :object_commit_indeterminate} =
             Store.replace(service, "collection", "a", input())

    assert {:ok, %{"version" => 0, "content" => "initial"}} = Store.read_object(service, "shared")

    assert {:error, :object_receipt_not_found} =
             Store.read_receipt(service, "collection", "a", input())

    SQL.query!(resource, "DROP TRIGGER fail_receipt", [])
    assert {:ok, receipt} = Store.replace(service, "collection", "a", input())
    assert receipt.body["applied"]
    assert receipt.body["version"] == 1
  end

  test "mismatch receipt remains original after later versions; replay never overwrites another write",
       %{service: service} do
    assert {:ok, first} = Store.replace(service, "collection", "a", input("one"))
    assert {:ok, mismatch} = Store.replace(service, "collection", "b", input("lost"))
    assert {:ok, third} = Store.replace(service, "collection", "c", input("two", 1))
    assert third.body["version"] == 2
    assert {:ok, ^first} = Store.replace(service, "collection", "a", input("one"))
    assert {:ok, ^mismatch} = Store.replace(service, "collection", "b", input("lost"))
    assert {:ok, ^mismatch} = Store.read_receipt(service, "collection", "b", input("lost"))
    assert {:ok, %{"version" => 2, "content" => "two"}} = Store.read_object(service, "shared")
  end

  test "safe replacement preserves original request key and original receipt", %{
    c: c,
    service: service
  } do
    id = submit(c, "retry", input(), :retry_once)
    old = grant(c, worker(c), id)
    assert {:success, body} = SharedObject.invoke(old, %{service: service})

    eventually(fn ->
      case Coordinator.expire(c, id, old.token.execution_id) do
        {:ok, expired} ->
          expired.facts.intent.executions[old.token.execution_id].phase == :unknown

        _not_yet ->
          false
      end
    end)

    assert {:ok, replaced} = Coordinator.recover(c, id)
    next_id = replaced.facts.intent.current_execution_id
    assert next_id != old.token.execution_id
    assert :started = Worker.run(worker(c), id, next_id)
    eventually(fn -> facts(c, id).intent.outcome != nil end)
    f = facts(c, id)
    assert f.intent.outcome.value == body
    assert f.intent.outcome.execution_id == next_id
    assert map_size(f.intent.executions) == 2
    assert f.intent.executions[next_id].binding["idempotency"] == old.binding["idempotency"]
    assert {:ok, %{"version" => 1, "content" => "new"}} = Store.read_object(service, "shared")
  end

  test "full Authority and resource restart retains identity, receipt and query association", %{
    c: c,
    service: service,
    resource_child: resource_child,
    authority_child: authority_child,
    resource_path: resource_path,
    authority_path: authority_path
  } do
    id = submit(c, "restart")
    w = worker(c)
    g = grant(c, w, id)
    assert {:success, body} = SharedObject.invoke(g, %{service: service})
    GenServer.stop(w)
    stop_supervised!(resource_child)
    stop_supervised!(authority_child)
    {_child, authority} = repo(SQLite, authority_path)
    {_child, resource} = repo(Store, resource_path)
    :ok = SQLite.migrate(authority)
    assert {:ok, :ok} = Store.migrate(resource, service.identity)
    restored = Store.new(resource, service.identity, service.account)
    assert restored.instance == service.instance
    active = coordinator(authority, restored)
    assert {:error, :foreign_incarnation} = Worker.deliver(worker(active), g)
    assert {:ok, recovered} = Coordinator.query(active, id, g.token.execution_id)
    assert recovered.facts.intent.outcome.value == body
    assert {:ok, %{"version" => 1, "content" => "new"}} = Store.read_object(restored, "shared")
  end

  test "same-named new resource DB and changed account cannot inherit saved guarantees", %{
    c: c,
    service: service,
    resource_path: path
  } do
    id = submit(c, "binding")
    g = grant(c, worker(c), id)
    {_child, empty_repo} = repo(Store, path <> ".new")
    assert {:ok, :ok} = Store.migrate(empty_repo, service.identity)
    empty = Store.new(empty_repo, service.identity, service.account)
    assert {:ok, _object} = Store.create_object(empty, "shared", "initial")
    assert empty.instance != service.instance
    assert {:uncertain, :object_resource_mismatch} = SharedObject.invoke(g, %{service: empty})

    assert {:error, :object_resource_mismatch} =
             Coordinator.query(coordinator(c.repo, empty), id, g.token.execution_id)

    wrong_account = Store.new(service.repo, service.identity, "other-account")

    assert {:uncertain, :unsupported_object_definition} =
             SharedObject.invoke(g, %{service: wrong_account})

    assert facts(c, id).intent.outcome == nil
    assert {:ok, %{"version" => 0, "content" => "initial"}} = Store.read_object(empty, "shared")
  end

  test "wrong environment refuses authorization and cancellation preserves late receipt evidence",
       %{c: c, service: service} do
    id = submit(c, "environment")
    assert {:ok, prepared} = Coordinator.prepare(c, id)
    e = prepared.facts.intent.current_execution_id
    {w, incarnation} = Worker.session(worker(c))

    assert {:ok, %Commit{reply: {:claimed, token}}} =
             Coordinator.claim(c, id, e, w, incarnation, 0)

    assert {:error, :object_resource_mismatch} =
             Coordinator.authorize(c, token, %{
               "object_service" => "object-service",
               "object_account" => "wrong"
             })

    assert facts(c, id).intent.executions[e].authorization == nil

    assert {:ok, auth} =
             Coordinator.authorize(c, token, %{
               "object_service" => "object-service",
               "object_account" => "account"
             })

    {:ok, g} = Coordinator.grant(auth)
    assert {:ok, cancelled} = Coordinator.cancel(c, id, "stop")
    assert {:success, _body} = SharedObject.invoke(g, %{service: service})
    assert {:ok, late} = Coordinator.query(c, id, e)
    assert late.facts.intent.outcome == cancelled.facts.intent.outcome
    assert late.facts.intent.outcome.kind == :cancelled
    assert Enum.any?(late.facts.intent.executions[e].reports, &(&1.kind == :success))
  end

  test "missing object and resource outage stay uncertain without Failure", %{
    c: c,
    service: service
  } do
    id = submit(c, "missing-object", input("new", 0, "missing"))
    g = grant(c, worker(c), id)
    assert {:uncertain, :object_not_found} = SharedObject.invoke(g, %{service: service})
    assert {:ok, query} = Coordinator.query(c, id, g.token.execution_id)
    assert query.facts.intent.outcome == nil
    assert query.facts.intent.executions[g.token.execution_id].result == nil
    offline = %{service | repo: :missing_object_repo}
    assert {:uncertain, :object_store_unavailable} = SharedObject.invoke(g, %{service: offline})

    assert {:error, :object_store_unavailable} =
             Coordinator.query(coordinator(c.repo, offline), id, g.token.execution_id)

    assert facts(c, id).intent.outcome == nil
  end

  test "initialization never resets content, and scope separates accounts, objects and collections",
       %{service: service} do
    assert {:ok, _receipt} = Store.replace(service, "collection", "same", input("one"))

    assert {:ok, %{"version" => 1, "content" => "one"}} =
             Store.create_object(service, "shared", "initial")

    assert {:error, :object_definition_conflict} = Store.create_object(service, "shared", "reset")
    other = Store.new(service.repo, service.identity, "other")
    assert {:ok, _object} = Store.create_object(other, "shared", "other-initial")
    assert {:ok, _object} = Store.create_object(service, "different", "different-initial")

    assert {:ok, a} =
             Store.replace(other, "collection", "same", %{input("other") | "account" => "other"})

    assert a.body["applied"]

    assert {:ok, b} =
             Store.replace(service, "collection", "same", input("different", 0, "different"))

    assert b.body["applied"]
    assert {:ok, c} = Store.replace(service, "other-collection", "same", input("two", 1))
    assert c.body["version"] == 2
    assert {:ok, %{"version" => 1, "content" => "other"}} = Store.read_object(other, "shared")

    assert {:ok, %{"version" => 1, "content" => "different"}} =
             Store.read_object(service, "different")
  end

  test "changed expected version under a used key conflicts before inspecting current state", %{
    service: service
  } do
    original = input("one")
    assert {:ok, receipt} = Store.replace(service, "collection", "key", original)

    assert {:error, :object_request_conflict} =
             Store.replace(service, "collection", "key", input("two", 1))

    assert {:error, :object_request_conflict} =
             Store.read_receipt(service, "collection", "key", input("two", 1))

    assert {:ok, ^receipt} = Store.replace(service, "collection", "key", original)
    assert {:ok, %{"version" => 1, "content" => "one"}} = Store.read_object(service, "shared")
  end

  test "actual readonly resource fault never becomes a Failure and original grant can be queried after recovery",
       %{c: c, service: service, resource: resource} do
    id = submit(c, "readonly")
    g = grant(c, worker(c), id)
    SQL.query!(resource, "PRAGMA query_only=ON", [])

    try do
      assert {:uncertain, :object_commit_indeterminate} =
               SharedObject.invoke(g, %{service: service})

      assert {:ok, %{"version" => 0, "content" => "initial"}} =
               Store.read_object(service, "shared")

      assert {:ok, checked} = Coordinator.query(c, id, g.token.execution_id)
      assert checked.facts.intent.outcome == nil
      assert checked.facts.intent.executions[g.token.execution_id].result == nil
    after
      SQL.query!(resource, "PRAGMA query_only=OFF", [])
    end

    assert {:success, body} = SharedObject.invoke(g, %{service: service})
    assert {:ok, completed} = Coordinator.query(c, id, g.token.execution_id)
    assert completed.facts.intent.outcome.value == body
  end

  test "receipt history cannot be updated or deleted and version exhaustion makes no write", %{
    service: service,
    resource: resource
  } do
    assert {:ok, receipt} = Store.replace(service, "collection", "a", input())

    assert_raise Exqlite.Error, fn ->
      SQL.query!(resource, "DELETE FROM object_receipts WHERE intent_id=?", ["a"])
    end

    assert_raise Exqlite.Error, fn ->
      SQL.query!(resource, "UPDATE object_receipts SET version=2 WHERE intent_id=?", ["a"])
    end

    assert {:ok, ^receipt} = Store.read_receipt(service, "collection", "a", input())
    # Explicit fault fixture positions the otherwise impractically distant capacity boundary.
    SQL.query!(
      resource,
      "UPDATE resource_objects SET version=9007199254740991 WHERE object_ref=?",
      ["shared"]
    )

    assert {:error, :object_version_exhausted} =
             Store.replace(
               service,
               "collection",
               "limit",
               input("overflow", 9_007_199_254_740_991)
             )

    assert {:error, :object_receipt_not_found} =
             Store.read_receipt(
               service,
               "collection",
               "limit",
               input("overflow", 9_007_199_254_740_991)
             )

    assert {:ok, %{"version" => 9_007_199_254_740_991, "content" => "new"}} =
             Store.read_object(service, "shared")
  end

  test "restricted values and logically equal reordered maps retain exact request replay", %{
    service: service
  } do
    for {value, n} <-
          Enum.with_index([
            nil,
            false,
            9_007_199_254_740_991,
            %{"α" => [nil, true, %{"a" => "b"}]}
          ]) do
      object = Integer.to_string(n)
      assert {:ok, _initial} = Store.create_object(service, object, nil)
      request = input(value, 0, object)
      assert {:ok, receipt} = Store.replace(service, "collection", object, request)

      assert {:ok, ^receipt} =
               Store.replace(
                 service,
                 "collection",
                 object,
                 Map.new(Enum.reverse(Map.to_list(request)))
               )

      assert {:ok, %{"version" => 1, "content" => ^value}} = Store.read_object(service, object)
    end
  end

  test "schema validation rejects ambiguous input and unsupported result classes", %{
    c: c,
    service: service
  } do
    for bad <- [
          Map.put(input(), "extra", true),
          %{input() | "expected_version" => -1},
          %{input() | "expected_version" => 1.0},
          %{input() | "content" => self()}
        ] do
      assert {:error, _reason} = Store.replace(service, "collection", "invalid", bad)
    end

    assert {:error, :invalid_object_result} =
             SharedObject.validate_result("object.replace_if_version.v1", :failure, %{}, %{})

    assert {:error, :invalid_object_result} =
             SharedObject.validate_result(
               "object.replace_if_version.v1",
               :success,
               %{"applied" => false},
               %{}
             )

    assert {:error, :object_receipt_not_found} =
             Store.read_receipt(service, "collection", "invalid", input())

    assert_raise ArgumentError, fn -> Store.start_link(database: ":memory:") end
    {:ok, identity} = Identity.new(c.collection, "agent", "schema")

    {:ok, definition} =
      Definition.new(%{
        operation: "object.replace_if_version.v1",
        input: %{input() | "account" => "wrong"}
      })

    assert {:error, :unsupported_object_definition} = Coordinator.submit(c, identity, definition)
  end
end
