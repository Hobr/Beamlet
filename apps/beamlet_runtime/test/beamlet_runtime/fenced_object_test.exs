defmodule BeamletRuntime.FencedObjectTest do
  use ExUnit.Case, async: false
  alias Beamlet.{Definition, Identity}
  alias BeamletRuntime.Coordinator
  alias BeamletRuntime.Handlers.FencedObject
  alias BeamletRuntime.Object.Store
  alias BeamletRuntime.Storage.{Error, SQLite}
  alias Ecto.Adapters.SQL

  setup do
    directory = Path.join(System.tmp_dir!(), "beamlet-fenced-#{Ecto.UUID.generate()}")
    authority_path = Path.join(directory, "authority.db")
    resource_path = Path.join(directory, "objects.db")
    authority = start_repo(SQLite, authority_path)
    resource = start_repo(Store, resource_path)
    :ok = SQLite.migrate(authority)
    assert {:ok, :ok} = Store.migrate(resource, "objects")
    service = Store.new(resource, "objects", "account")
    assert {:ok, _} = Store.create_object(service, "object", "initial")

    c =
      Coordinator.new(
        repo: authority,
        collection: "collection",
        actor: "local",
        handlers: [{FencedObject, %{service: service}}],
        ttl: 1000
      )

    on_exit(fn -> File.rm_rf!(directory) end)

    %{
      c: c,
      service: service,
      resource: resource,
      resource_path: resource_path,
      authority_path: authority_path
    }
  end

  defp start_repo(module, path),
    do:
      start_supervised!(
        Supervisor.child_spec({module, database: path, pool_size: 1},
          id: make_ref(),
          restart: :temporary
        )
      )

  defp request,
    do: %{
      "service" => "objects",
      "account" => "account",
      "object" => "object",
      "content" => "new",
      "expected_version" => 0
    }

  defp submit(c, key) do
    {:ok, identity} = Identity.new(c.collection, "agent", key)

    {:ok, definition} =
      Definition.new(%{
        operation: "object.fenced_replace_if_version.v1",
        input: request(),
        policy: :retry_once
      })

    {:ok, commit} = Coordinator.submit(c, identity, definition)
    commit.facts.intent.id
  end

  defp grant(c, id) do
    {:ok, prepared} = Coordinator.prepare(c, id)
    e = prepared.facts.intent.current_execution_id
    {:ok, claimed} = Coordinator.claim(c, id, e, "worker", Ecto.UUID.generate(), 0)
    {:claimed, token} = claimed.reply

    {:ok, authorized} =
      Coordinator.authorize(c, token, %{
        "object_service" => "objects",
        "object_account" => "account"
      })

    {:ok, grant} = Coordinator.grant(authorized)
    grant
  end

  test "committed invocation wins over fencing and returns its original Success", %{
    c: c,
    service: service
  } do
    id = submit(c, "written")
    g = grant(c, id)
    assert {:success, body} = FencedObject.invoke(g, %{service: service})
    assert {:ok, fenced} = Coordinator.fence(c, id, g.token.execution_id)
    assert fenced.facts.intent.outcome.value == body
    assert fenced.facts.intent.executions[g.token.execution_id].result.kind == :success
    assert {:success, ^body} = FencedObject.invoke(g, %{service: service})
    assert {:ok, %{"version" => 1}} = Store.read_object(service, "object")
  end

  test "independent SQL connections serialize fence versus invocation", %{
    c: c,
    service: service,
    resource_path: path
  } do
    other = %{service | repo: start_repo(Store, path)}

    for n <- 1..12 do
      id = submit(c, "race-#{n}")
      g = grant(c, id)

      tasks = [
        Task.async(fn -> Store.fence(service, g.token, request()) end),
        Task.async(fn -> Store.invoke_fenced(other, g.token, request()) end)
      ]

      [fence, invoke] = Enum.map(tasks, &Task.await/1)

      case {fence, invoke} do
        {{:ok, %{kind: :not_executed} = proof}, {:error, :object_execution_fenced}} ->
          assert {:ok, ^proof} = Store.read_fenced_receipt(other, g.token, request())

          assert {:uncertain, :object_execution_fenced} =
                   FencedObject.invoke(g, %{service: other})

        {{:ok, %{kind: :success, receipt: receipt}}, {:ok, receipt}} ->
          assert {:ok, %{kind: :success, receipt: ^receipt}} =
                   Store.read_fenced_receipt(other, g.token, request())

        unexpected ->
          flunk("invalid race result: #{inspect(unexpected)}")
      end
    end
  end

  test "resource commit survives lost reply and full Authority/resource restart", %{
    c: c,
    service: service,
    authority_path: authority_path,
    resource_path: resource_path
  } do
    id = submit(c, "lost")
    g = grant(c, id)
    assert {:ok, proof} = Store.fence(service, g.token, request())
    Supervisor.stop(service.repo)
    Supervisor.stop(c.repo)
    resource = start_repo(Store, resource_path)
    assert {:ok, :ok} = Store.migrate(resource, "objects")
    service = Store.new(resource, "objects", "account")
    authority = start_repo(SQLite, authority_path)
    :ok = SQLite.migrate(authority)
    c = %{c | repo: authority, handlers: [{FencedObject, %{service: service}}]}
    assert {:ok, queried} = Coordinator.query(c, id, g.token.execution_id)
    e = queried.facts.intent.executions[g.token.execution_id]
    assert e.result.exclusion.evidence_ref == proof.evidence_ref
    assert {:ok, duplicate} = Coordinator.fence(c, id, g.token.execution_id)
    assert duplicate.facts == queried.facts
    assert {:uncertain, :object_execution_fenced} = FencedObject.invoke(g, %{service: service})
  end

  test "resource exclusion survives Authority report-commit failure", %{c: c, service: service} do
    id = submit(c, "authority-offline")
    g = grant(c, id)
    SQL.query!(c.repo, "PRAGMA query_only=ON", [])

    try do
      assert {:error, %Error{kind: :unavailable}} = Coordinator.fence(c, id, g.token.execution_id)

      assert {:ok, %{kind: :not_executed}} =
               Store.read_fenced_receipt(service, g.token, request())

      assert {:ok, before} = Coordinator.read(c, id)
      assert before.intent.executions[g.token.execution_id].result == nil
      assert {:uncertain, :object_execution_fenced} = FencedObject.invoke(g, %{service: service})
    after
      SQL.query!(c.repo, "PRAGMA query_only=OFF", [])
    end

    assert {:ok, recovered} = Coordinator.query(c, id, g.token.execution_id)
    assert recovered.facts.intent.executions[g.token.execution_id].result.kind == :not_executed
  end

  test "fence insert rollback leaves the original grant executable", %{c: c, service: service} do
    id = submit(c, "insert-failure")
    g = grant(c, id)

    SQL.query!(
      service.repo,
      "CREATE TRIGGER reject_fence BEFORE INSERT ON object_fences BEGIN SELECT RAISE(ABORT, 'injected fence failure'); END",
      []
    )

    assert {:error, :object_commit_indeterminate} = Coordinator.fence(c, id, g.token.execution_id)

    assert {:error, :object_receipt_not_found} =
             Store.read_fenced_receipt(service, g.token, request())

    SQL.query!(service.repo, "DROP TRIGGER reject_fence", [])
    assert {:success, _} = FencedObject.invoke(g, %{service: service})
  end

  test "readonly exclusion failure neither fabricates proof nor blocks a later invocation", %{
    c: c,
    service: service
  } do
    id = submit(c, "readonly")
    g = grant(c, id)
    SQL.query!(service.repo, "PRAGMA query_only=ON", [])

    try do
      assert {:error, :object_commit_indeterminate} =
               Coordinator.fence(c, id, g.token.execution_id)

      assert {:ok, missing} = Coordinator.query(c, id, g.token.execution_id)
      assert missing.facts.intent.executions[g.token.execution_id].result == nil
    after
      SQL.query!(service.repo, "PRAGMA query_only=OFF", [])
    end

    assert {:success, _} = FencedObject.invoke(g, %{service: service})
  end

  test "permanent exclusion rejects changed requests and substituted authorizations", %{
    c: c,
    service: service
  } do
    g = grant(c, submit(c, "scope"))
    assert {:ok, proof} = Store.fence(service, g.token, request())
    assert {:ok, ^proof} = Store.fence(service, g.token, request())

    assert {:error, :object_request_conflict} =
             Store.fence(service, g.token, %{request() | "content" => "changed"})

    next = %{g.token | execution_id: "next"}

    assert {:error, :object_request_conflict} =
             Store.invoke_fenced(service, next, %{request() | "content" => "changed"})

    assert {:error, :object_request_conflict} =
             Store.fence(service, next, %{request() | "expected_version" => 1})

    assert {:error, :object_authorization_conflict} =
             Store.invoke_fenced(service, %{g.token | incarnation: "other"}, request())

    assert {:error, :object_authorization_conflict} =
             Store.read_fenced_receipt(service, %{g.token | generation: 2}, request())

    assert {:error, :invalid_object_authorization} =
             Store.fence(service, %{g.token | generation: 0}, request())

    assert {:error, :object_scope_mismatch} =
             Store.fence(service, g.token, %{request() | "account" => "other"})

    for statement <- [
          "UPDATE object_fences SET evidence_ref='changed'",
          "DELETE FROM object_fences"
        ] do
      assert {:error, _} = SQL.query(service.repo, statement, [])
    end

    assert {:ok, ^proof} = Store.read_fenced_receipt(service, g.token, request())
  end

  test "fencing after cancellation preserves the original Outcome and excludes only that execution",
       %{c: c, service: service} do
    id = submit(c, "cancel")
    g = grant(c, id)
    {:ok, cancelled} = Coordinator.cancel(c, id, "stop")
    assert {:ok, excluded} = Coordinator.fence(c, id, g.token.execution_id)
    assert excluded.facts.intent.outcome == cancelled.facts.intent.outcome
    assert excluded.facts.intent.executions[g.token.execution_id].result.kind == :not_executed
    assert {:uncertain, :object_execution_fenced} = FencedObject.invoke(g, %{service: service})
    sibling = grant(c, submit(c, "sibling"))
    assert {:success, _} = FencedObject.invoke(sibling, %{service: service})
  end

  test "same-named replacement database cannot inherit an original exclusion protocol", %{
    c: c,
    service: service
  } do
    id = submit(c, "instance")
    g = grant(c, id)
    path = Path.join(System.tmp_dir!(), "beamlet-replacement-#{Ecto.UUID.generate()}.db")

    on_exit(fn ->
      File.rm(path)
      File.rm(path <> "-wal")
      File.rm(path <> "-shm")
    end)

    repo = start_repo(Store, path)
    assert {:ok, :ok} = Store.migrate(repo, "objects")
    replacement = Store.new(repo, "objects", "account")
    c = %{c | handlers: [{FencedObject, %{service: replacement}}]}
    assert {:error, :object_resource_mismatch} = Coordinator.fence(c, id, g.token.execution_id)

    assert {:uncertain, :object_resource_mismatch} =
             FencedObject.invoke(g, %{service: replacement})

    assert {:success, _} = FencedObject.invoke(g, %{service: service})
  end

  test "capability and original authorization are required before resource fencing", %{
    c: c,
    service: service
  } do
    id = submit(c, "prepared")
    {:ok, p} = Coordinator.prepare(c, id)

    assert {:error, :authorization_required} =
             Coordinator.fence(c, id, p.facts.intent.current_execution_id)

    alias BeamletRuntime.Handlers.SharedObject
    c = %{c | handlers: [{SharedObject, %{service: service}}]}
    {:ok, identity} = Identity.new(c.collection, "agent", "legacy")

    {:ok, definition} =
      Definition.new(%{operation: "object.replace_if_version.v1", input: request()})

    {:ok, commit} = Coordinator.submit(c, identity, definition)
    g = grant(c, commit.facts.intent.id)

    assert {:error, :fencing_not_supported} =
             Coordinator.fence(c, g.token.intent_id, g.token.execution_id)

    assert {:ok, %{"version" => 0}} = Store.read_object(service, "object")
  end

  test "resource exclusion blocks an old grant and permits a new execution without idempotency",
       %{c: c, service: service} do
    id = submit(c, "fenced")
    old = grant(c, id)
    refute Map.has_key?(old.binding, "idempotency")
    assert {:ok, missing} = Coordinator.query(c, id, old.token.execution_id)
    assert missing.facts.intent.executions[old.token.execution_id].result == nil
    assert {:ok, fenced} = Coordinator.fence(c, id, old.token.execution_id)
    old_execution = fenced.facts.intent.executions[old.token.execution_id]
    assert old_execution.result.kind == :not_executed
    assert old_execution.result.exclusion.authorization == old.token
    assert {:uncertain, :object_execution_fenced} = FencedObject.invoke(old, %{service: service})
    assert {:ok, recovered} = Coordinator.recover(c, id)
    assert recovered.facts.intent.current_execution_id != old.token.execution_id
    next = grant(c, id)
    assert next.intent.executions[next.token.execution_id].replacement.basis == :not_executed
    assert {:success, body} = FencedObject.invoke(next, %{service: service})
    assert {:ok, completed} = Coordinator.query(c, id, next.token.execution_id)
    assert completed.facts.intent.outcome.value == body
    assert {:ok, again} = Coordinator.query(c, id, old.token.execution_id)
    assert again.facts.intent.outcome == completed.facts.intent.outcome
    assert again.facts.intent.executions[old.token.execution_id].result == old_execution.result
    assert {:ok, %{"version" => 1, "content" => "new"}} = Store.read_object(service, "object")
  end
end
