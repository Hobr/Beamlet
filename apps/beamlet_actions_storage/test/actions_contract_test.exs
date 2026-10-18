for adapter <- [:sqlite, :postgres] do
  defmodule Module.concat(Beamlet.Actions.Storage, "#{adapter}ContractTest") do
    use ExUnit.Case, async: false
    alias Beamlet.Actions.Storage.{Codec, DispatchScopes, OperationRecords, Profiles, Records}
    alias Beamlet.Storage.{Dataset, Transaction}
    alias Ecto.Adapters.SQL
    @adapter adapter
    @repo if(adapter == :sqlite,
            do: Beamlet.Actions.Storage.SQLiteAuthorityRepo,
            else: Beamlet.Actions.Storage.PostgresAuthorityRepo
          )
    if adapter == :postgres, do: @moduletag(:postgres_db)

    setup do
      dir =
        Path.join(
          System.tmp_dir!(),
          "actions-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(dir)

      admin =
        if @adapter == :postgres do
          [
            socket_dir: System.fetch_env!("BEAMLET_PG_SOCKET_DIR"),
            port: String.to_integer(System.get_env("BEAMLET_PG_PORT", "5432")),
            username: System.get_env("BEAMLET_PG_USER"),
            database: "postgres"
          ]
        end

      database =
        if admin,
          do: "actions_#{System.system_time(:nanosecond)}_#{System.unique_integer([:positive])}",
          else: Path.join(dir, "authority.db")

      if admin do
        {:ok, conn} = Postgrex.start_link(admin)
        Postgrex.query!(conn, "CREATE DATABASE " <> database, [])
        GenServer.stop(conn)
      end

      opts =
        Keyword.merge(admin || [],
          database: database,
          dataset_id: Ecto.UUID.generate(),
          descriptor: Profiles.authority()
        )

      opts =
        if @adapter == :sqlite,
          do: Keyword.put(opts, :peer_database, Path.join(dir, "peer.db")),
          else: opts

      assert {:ok, _} = Dataset.initialize(@repo, opts)

      on_exit(fn ->
        try do
          if Process.whereis(@repo), do: @repo.stop()
        catch
          :exit, _ -> :ok
        end

        if admin do
          {:ok, conn} = Postgrex.start_link(admin)
          Postgrex.query!(conn, "DROP DATABASE " <> database <> " WITH (FORCE)", [])
          GenServer.stop(conn)
        end

        File.rm_rf!(dir)
      end)

      %{opts: opts}
    end

    defp input(scope \\ nil) do
      %{
        operation: %{
          id: Ecto.UUID.generate(),
          description: %{
            "kind" => "example.echo",
            "protocol_version" => 1,
            "payload" => %{"text" => "hello"}
          },
          dispatch_scope_id: scope,
          dispatch_epoch: if(scope, do: 0)
        },
        attempt: %{
          attempt_id: Ecto.UUID.generate(),
          executor_id: Ecto.UUID.generate(),
          executor_boot_id: Ecto.UUID.generate(),
          budget: %{}
        }
      }
    end

    defp claim(input),
      do: %{
        operation_id: input.operation.id,
        attempt_id: input.attempt.attempt_id,
        expected_version: 0
      }

    test "neutral tables, immutable identity replay, bounded canonical bytes and restart", %{
      opts: opts
    } do
      assert Profiles.authority().profile == "actions-authority"
      assert Enum.map(Profiles.authority().migrations, & &1.id) == [1, 100]

      assert Profiles.authority().components == [
               %{name: "foundation", version: 1},
               %{name: "actions-authority", version: 1}
             ]

      assert Profiles.journal().profile == "actions-journal"
      assert Enum.map(Profiles.journal().migrations, & &1.id) == [1, 200]

      tables =
        if @adapter == :sqlite,
          do: SQL.query!(@repo, "SELECT name FROM sqlite_master WHERE type='table'", []).rows,
          else:
            SQL.query!(
              @repo,
              "SELECT table_name FROM information_schema.tables WHERE table_schema=current_schema()",
              []
            ).rows

      assert Enum.sort(List.flatten(tables)) ==
               ~w(artifacts dispatch_scopes execution_evidence executions operation_events operations schema_migrations storage_metadata)

      attrs = input()
      assert {:ok, prepared} = OperationRecords.prepare(@repo, attrs)
      assert {:ok, ^prepared} = OperationRecords.prepare(@repo, attrs)

      assert {:error, :conflict} =
               OperationRecords.prepare(
                 @repo,
                 put_in(attrs.operation.description["payload"], %{"changed" => true})
               )

      assert {:error, :invalid_data} =
               OperationRecords.prepare(
                 @repo,
                 put_in(attrs.operation[:owner_agent_id], Ecto.UUID.generate())
               )

      assert {:ok, "{\"a\":1.0,\"b\":1}"} = Codec.encode(%{"b" => 1, "a" => 1.0})

      assert Codec.digest(attrs.operation.description, :operation) ==
               Beamlet.Storage.Codec.digest(attrs.operation.description, 1_048_576)

      assert {:error, :limit} =
               Codec.encode(%{"x" => String.duplicate("x", 1_048_576)}, :operation)

      @repo.stop()
      assert {:ok, _} = Dataset.open(@repo, opts)
      assert {:ok, stored} = OperationRecords.fetch(@repo, attrs.operation.id)
      assert stored["attempt"]["dispatch_state"] == "prepared"
    end

    test "independent preparation rejects domain fields, changed boot and dangling content", %{
      opts: opts
    } do
      attrs = input()

      for {key, value} <- [
            role: "model",
            step_id: "unowned-step",
            sources: [%{"type" => "accepted_result", "reference" => %{}}]
          ] do
        assert {:error, :invalid_data} =
                 OperationRecords.prepare(@repo, put_in(attrs.operation[key], value))
      end

      assert {:error, :conflict} = OperationRecords.fetch(@repo, attrs.operation.id)
      assert {:ok, original} = OperationRecords.prepare(@repo, attrs)
      assert {:ok, ^original} = OperationRecords.prepare(@repo, attrs)

      assert {:error, :conflict} =
               OperationRecords.prepare(
                 @repo,
                 put_in(attrs.attempt.executor_boot_id, Ecto.UUID.generate())
               )

      assert {:error, :artifact_missing} =
               OperationRecords.accept_result(@repo, %{
                 operation_id: attrs.operation.id,
                 expected_version: 0,
                 result: %{"artifact_id" => Ecto.UUID.generate()}
               })

      SQL.query!(@repo, "UPDATE operations SET description = 'malformed' WHERE id=$1", [
        attrs.operation.id
      ])

      assert {:error, :invalid_data} = OperationRecords.fetch(@repo, attrs.operation.id)
      @repo.stop()
      assert {:ok, _} = Dataset.open(@repo, opts)
      assert {:error, :invalid_data} = OperationRecords.fetch(@repo, attrs.operation.id)
    end

    test "write facades classify corrupt stored JSON without hiding programmer errors" do
      attrs = input()
      assert {:ok, _} = OperationRecords.prepare(@repo, attrs)

      SQL.query!(@repo, "UPDATE operations SET description = 'malformed' WHERE id=$1", [
        attrs.operation.id
      ])

      assert {:error, :invalid_data} = OperationRecords.prepare(@repo, attrs)
      assert {:error, :invalid_data} = OperationRecords.claim_dispatch(@repo, claim(attrs))

      assert {:error, :invalid_data} =
               OperationRecords.accept_result(@repo, %{
                 operation_id: attrs.operation.id,
                 expected_version: 0,
                 result: %{"ok" => true}
               })

      SQL.query!(@repo, "UPDATE executions SET budget = 'malformed' WHERE attempt_id=$1", [
        attrs.attempt.attempt_id
      ])

      assert {:error, :invalid_data} =
               OperationRecords.record_evidence(@repo, %{
                 id: Ecto.UUID.generate(),
                 operation_id: attrs.operation.id,
                 attempt_id: attrs.attempt.attempt_id,
                 executor_id: attrs.attempt.executor_id,
                 evidence_id: Ecto.UUID.generate(),
                 content: %{}
               })

      assert_raise ArgumentError, "unrelated programmer error", fn ->
        Records.transact(@repo, fn ->
          raise ArgumentError, "unrelated programmer error"
        end)
      end
    end

    test "participants validate and roll back all writes on outer failure" do
      attrs = input()

      assert {:error, :transaction_required} =
               OperationRecords.prepare_in_transaction(@repo, attrs)

      assert {:error, :abort} =
               Transaction.write(@repo, fn ->
                 assert {:error, :invalid_data} =
                          OperationRecords.prepare_in_transaction(@repo, %{})

                 assert {:ok, _} = OperationRecords.prepare_in_transaction(@repo, attrs)
                 @repo.rollback(:abort)
               end)

      assert {:error, :conflict} = OperationRecords.fetch(@repo, attrs.operation.id)
    end

    test "epoch invalidation, explicit pending reauthorization, claim-first and acceptance replay" do
      id = Ecto.UUID.generate()
      assert {:ok, _} = DispatchScopes.create(@repo, %{id: id})
      attrs = input(id)
      assert {:ok, prepared} = OperationRecords.prepare(@repo, attrs)
      assert {:ok, _} = DispatchScopes.rotate(@repo, %{id: id, expected_epoch: 0})
      assert {:error, :stale_epoch} = OperationRecords.claim_dispatch(@repo, claim(attrs))

      auth = %{
        scope_id: id,
        from_epoch: 0,
        to_epoch: 1,
        operation_id: attrs.operation.id,
        attempt_id: attrs.attempt.attempt_id,
        description_digest: prepared["description_digest"],
        expected_version: 0,
        attempt_version: 0
      }

      assert {:error, :abort} =
               Transaction.write(@repo, fn ->
                 assert {:ok, _} = DispatchScopes.reauthorize_in_transaction(@repo, auth)
                 @repo.rollback(:abort)
               end)

      assert {:ok, {:ok, _}} =
               Transaction.write(@repo, fn ->
                 DispatchScopes.reauthorize_in_transaction(@repo, auth)
               end)

      old_binding = %{
        description_digest: prepared["description_digest"],
        lock_version: 0,
        dispatch_scope_id: id,
        dispatch_epoch: 0
      }

      assert {:error, :conflict} =
               OperationRecords.claim_dispatch(
                 @repo,
                 Map.put(claim(attrs), :expected_operation, old_binding)
               )

      assert {:ok, _} = OperationRecords.claim_dispatch(@repo, claim(attrs))
      assert {:ok, _} = DispatchScopes.rotate(@repo, %{id: id, expected_epoch: 1})

      assert {:ok, {:error, :conflict}} =
               Transaction.write(@repo, fn ->
                 DispatchScopes.reauthorize_in_transaction(@repo, %{
                   auth
                   | from_epoch: 1,
                     to_epoch: 2,
                     expected_version: 1
                 })
               end)

      evidence = %{
        id: Ecto.UUID.generate(),
        operation_id: attrs.operation.id,
        attempt_id: attrs.attempt.attempt_id,
        executor_id: attrs.attempt.executor_id,
        evidence_id: Ecto.UUID.generate(),
        content: %{"late" => true}
      }

      assert {:ok, original} = OperationRecords.record_evidence(@repo, evidence)
      assert {:ok, ^original} = OperationRecords.record_evidence(@repo, evidence)

      assert {:error, :conflict} =
               OperationRecords.record_evidence(@repo, %{evidence | content: %{}})

      accept = %{
        operation_id: attrs.operation.id,
        expected_version: 1,
        evidence_id: evidence.id,
        result: %{"ok" => true}
      }

      assert {:ok, result} = OperationRecords.accept_result(@repo, accept)
      assert {:ok, ^result} = OperationRecords.accept_result(@repo, accept)
      assert {:error, :conflict} = OperationRecords.accept_result(@repo, %{accept | result: %{}})
    end

    if adapter == :postgres do
      defp wait_for_locks(count, deadline) do
        [[waiting]] =
          SQL.query!(
            @repo,
            "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock'",
            []
          ).rows

        cond do
          waiting >= count ->
            :ok

          System.monotonic_time(:millisecond) > deadline ->
            flunk("expected #{count} blocked transactions, saw #{waiting}")

          true ->
            wait_for_locks(count, deadline)
        end
      end

      test "claim acquires scope SHARE before operation UPDATE; rotation waits for claim commit" do
        id = Ecto.UUID.generate()
        {:ok, _} = DispatchScopes.create(@repo, %{id: id})
        attrs = input(id)
        {:ok, _} = OperationRecords.prepare(@repo, attrs)
        parent = self()

        holder =
          Task.async(fn ->
            Transaction.write(@repo, fn ->
              SQL.query!(@repo, "SELECT id FROM operations WHERE id=$1 FOR UPDATE", [
                attrs.operation.id
              ])

              send(parent, :operation_locked)

              receive do
                :release -> :ok
              end
            end)
          end)

        assert_receive :operation_locked
        claimant = Task.async(fn -> OperationRecords.claim_dispatch(@repo, claim(attrs)) end)
        deadline = System.monotonic_time(:millisecond) + 5000
        wait_for_locks(1, deadline)
        rotator = Task.async(fn -> DispatchScopes.rotate(@repo, %{id: id, expected_epoch: 0}) end)
        wait_for_locks(2, deadline)
        send(holder.pid, :release)
        assert {:ok, :ok} = Task.await(holder)
        assert {:ok, _} = Task.await(claimant)
        assert {:ok, _} = Task.await(rotator)
      end

      test "rotation holds scope before claim and old epoch refuses after commit" do
        id = Ecto.UUID.generate()
        {:ok, _} = DispatchScopes.create(@repo, %{id: id})
        attrs = input(id)
        {:ok, _} = OperationRecords.prepare(@repo, attrs)
        parent = self()

        rotator =
          Task.async(fn ->
            Transaction.write(@repo, fn ->
              assert {:ok, _} =
                       DispatchScopes.rotate_in_transaction(@repo, %{id: id, expected_epoch: 0})

              send(parent, :rotated)

              receive do
                :release -> :ok
              end
            end)
          end)

        assert_receive :rotated
        claimant = Task.async(fn -> OperationRecords.claim_dispatch(@repo, claim(attrs)) end)
        wait_for_locks(1, System.monotonic_time(:millisecond) + 5000)
        send(rotator.pid, :release)
        assert {:ok, :ok} = Task.await(rotator)
        assert {:error, :stale_epoch} = Task.await(claimant)
      end
    end
  end
end
