defmodule Beamlet.Storage.ContractSuite do
  @moduledoc false
  # One storage contract, two real databases. Every test body below is inserted
  # verbatim into both adapter modules, so an assertion cannot drift between
  # SQLite and PostgreSQL; only `Beamlet.Storage.ContractFixture` differs.
  #
  # The executor journal is deliberately SQLite-only (executor-local evidence) and
  # is exercised by `record_transactions_test.exs`; this suite covers the authority
  # dataset, which must behave identically on both adapters.

  defmacro __using__(backend: backend) do
    quote bind_quoted: [backend: backend] do
      use ExUnit.Case, async: false

      # Excluded by default (see test_helper.exs): the PostgreSQL half requires an
      # isolated cluster, and its absence must never be reported as a pass.
      if backend == :postgres, do: @moduletag(:postgres_db)

      alias Beamlet.Storage.{
        AgentRecords,
        Artifacts,
        Codec,
        Dataset,
        ExecutorJournalRepo,
        OperationRecords,
        Transaction
      }

      alias Beamlet.Storage.ContractFixture, as: Fixture
      alias Ecto.Adapters.SQL

      @errors ~w(invalid_data limit conflict stale_generation schema_unsupported
                 artifact_missing storage_unavailable storage_outcome_unknown)a

      @backend backend

      setup do
        fixture = Fixture.open(@backend)
        on_exit(fn -> Fixture.close(fixture) end)
        {:ok, fixture: fixture}
      end

      defp sql(fixture, statement, params \\ []), do: Fixture.sql(fixture, statement, params)

      defp raw_connection(fixture), do: Fixture.raw_connection(fixture)
      defp run_raw(conn, statement), do: Fixture.run_raw(conn, statement)
      defp close_raw(conn), do: Fixture.close_raw(conn)

      # `repo.stop/0` is called from the test process more than once per fixture, so
      # a second stop must be tolerated rather than retried.
      defp stop_repo(%{repo: repo}) do
        try do
          repo.stop()
        catch
          _, _ -> :ok
        end
      end

      # A private connection is needed while the Repo is stopped, so it can mutate
      # installation metadata without going through the guarded pool.
      defp raw(fixture) do
        database =
          if fixture.backend == :sqlite, do: fixture.opts[:database], else: fixture.database

        {:ok, conn} = raw_connection(Map.put(fixture, :database, database))
        conn
      end

      defp event(type, payload \\ %{}) do
        %{id: Ecto.UUID.generate(), type: type, payload: payload}
      end

      defp command(params) do
        scope_id = Ecto.UUID.generate()

        %{scope_id: scope_id, command_id: Ecto.UUID.generate(), params: params}
      end

      defp create_attrs(authority_id, overrides \\ %{}) do
        id = Ecto.UUID.generate()

        Map.merge(
          %{
            command: command(%{"op" => "create_agent", "agent_id" => id}),
            id: id,
            authority_id: authority_id,
            definition: %{"provider" => "native", "profile" => "default"},
            generation: 0,
            checkpoint: %{
              id: Ecto.UUID.generate(),
              data: %{"messages" => [], "continuation" => "await_input"},
              safe_to_fork: true
            },
            event: event("agent.created", %{"alias" => nil})
          },
          overrides
        )
      end

      defp attempt_attrs do
        %{
          attempt_id: Ecto.UUID.generate(),
          executor_id: Ecto.UUID.generate(),
          executor_boot_id: Ecto.UUID.generate(),
          budget: %{"milliseconds" => 5000}
        }
      end

      defp prepare(fixture, overrides \\ %{}) do
        id = Ecto.UUID.generate()

        attrs =
          Map.merge(
            %{
              operation: %{
                id: id,
                description: %{
                  "kind" => "tool_call",
                  "protocol_version" => 1,
                  "payload" => %{"tool" => "echo"}
                }
              },
              attempt: attempt_attrs(),
              event: event("operation.prepared")
            },
            overrides
          )

        {OperationRecords.prepare(fixture.repo, attrs), attrs}
      end

      ## 1. Per-connection durability settings

      test "every physical connection enforces full synchronous durability", %{fixture: fixture} do
        settings = Fixture.settings(fixture)

        assert settings.connections == fixture.pool_size,
               "expected #{fixture.pool_size} connections, got #{settings.connections}"

        assert length(settings.per_connection) == fixture.pool_size

        for entry <- settings.per_connection, {key, expected} <- settings.required do
          actual = entry[key]

          assert actual == expected,
                 "#{inspect(key)} is #{inspect(actual)}, expected #{inspect(expected)}"
        end
      end

      ## 2. Schema shape and installation identity

      test "installation creates the same authority schema and one metadata row", %{
        fixture: fixture
      } do
        expected =
          ~w(agents artifacts checkpoints commands events execution_evidence executions
             operations schema_migrations storage_metadata)

        assert Fixture.tables(fixture) == expected

        assert [[dataset_id, "authority", 1, backup]] =
                 sql(
                   fixture,
                   "SELECT dataset_id, role, format_version, restored_backup FROM storage_metadata"
                 ).rows

        assert dataset_id == fixture.authority_id
        # SQLite stores BOOLEAN as 0/1; PostgreSQL returns false.
        assert backup in [false, 0]

        assert [[1]] == sql(fixture, "SELECT COUNT(*) FROM schema_migrations").rows

        # Loading and opening created facts only in this dataset: no business rows.
        for table <- ~w(agents checkpoints events operations executions commands artifacts) do
          assert [[0]] == sql(fixture, "SELECT COUNT(*) FROM #{table}").rows
        end

        refute Process.whereis(ExecutorJournalRepo)
      end

      ## 5b. Close/reopen and format refusal (both adapters)

      test "a dataset with committed facts reopens and reads them back", %{fixture: fixture} do
        attrs = create_attrs(fixture.authority_id)
        {:ok, created} = AgentRecords.create_agent(fixture.repo, attrs)
        :ok = stop_repo(fixture)

        assert {:ok, pid} = Dataset.open(fixture.repo, fixture.opts)
        assert is_pid(pid)

        assert {:ok, %{"agent" => agent}} = AgentRecords.fetch(fixture.repo, created["agent_id"])
        assert agent["id"] == created["agent_id"]
      end

      test "reopening refuses a newer format version", %{fixture: fixture} do
        :ok = stop_repo(fixture)
        conn = raw(fixture)
        :ok = run_raw(conn, "UPDATE storage_metadata SET format_version = 2")
        :ok = close_raw(conn)

        assert {:error, :schema_unsupported} = Dataset.open(fixture.repo, fixture.opts)
      end

      test "reopening refuses an explicit restored-backup marker", %{fixture: fixture} do
        :ok = stop_repo(fixture)
        conn = raw(fixture)
        :ok = run_raw(conn, "UPDATE storage_metadata SET restored_backup = TRUE")
        :ok = close_raw(conn)

        assert {:error, :restored_backup} = Dataset.open(fixture.repo, fixture.opts)
      end

      ## 6. Multi-table atomicity

      test "a failing step rolls back every table of the transaction", %{fixture: fixture} do
        committed = create_attrs(fixture.authority_id)
        {:ok, first} = AgentRecords.create_agent(fixture.repo, committed)

        # A colliding checkpoint id fails late, after the Agent row is staged.
        dup = create_attrs(fixture.authority_id, %{checkpoint: committed.checkpoint})
        assert {:error, :conflict} = AgentRecords.create_agent(fixture.repo, dup)

        assert [[1]] == sql(fixture, "SELECT COUNT(*) FROM agents").rows
        assert [[1]] == sql(fixture, "SELECT COUNT(*) FROM commands").rows
        assert [[1]] == sql(fixture, "SELECT COUNT(*) FROM checkpoints").rows
        assert {:ok, _} = AgentRecords.fetch(fixture.repo, first["agent_id"])

        # No sibling fact from the rolled-back write set is visible.
        assert {:error, :conflict} = AgentRecords.fetch(fixture.repo, dup.id)
      end

      ## 7. Command idempotence and CAS under real concurrency

      test "concurrent identical commands commit one fact; the loser conflicts", %{
        fixture: fixture
      } do
        attrs = create_attrs(fixture.authority_id)

        results =
          1..4
          |> Enum.map(fn _ ->
            Task.async(fn -> AgentRecords.create_agent(fixture.repo, attrs) end)
          end)
          |> Enum.map(&Task.await(&1, 20_000))

        # A single-connection adapter replays the stored response; a pooled adapter
        # may instead surface the unique-constraint conflict. Both are one fact.
        assert Enum.all?(results, &(match?({:ok, _}, &1) or &1 == {:error, :conflict}))

        assert {:ok, response} = Enum.find(results, &match?({:ok, _}, &1))
        assert {:ok, ^response} = AgentRecords.create_agent(fixture.repo, attrs)

        assert [[1]] == sql(fixture, "SELECT COUNT(*) FROM agents").rows
        assert [[1]] == sql(fixture, "SELECT COUNT(*) FROM commands").rows
        assert [[1]] == sql(fixture, "SELECT COUNT(*) FROM events").rows

        # Different parameters under the same command identity is a conflict.
        changed = put_in(attrs, [:command, :params], %{"op" => "create_agent", "other" => true})
        assert {:error, :conflict} = AgentRecords.create_agent(fixture.repo, changed)
      end

      test "concurrent dispatch claims have exactly one winner", %{fixture: fixture} do
        {{:ok, prepared}, attrs} = prepare(fixture)

        claim = %{
          operation_id: prepared["operation_id"],
          attempt_id: attrs.attempt.attempt_id,
          expected_version: 0
        }

        results =
          1..4
          |> Enum.map(fn _ ->
            Task.async(fn -> OperationRecords.claim_dispatch(fixture.repo, claim) end)
          end)
          |> Enum.map(&Task.await(&1, 20_000))

        assert Enum.count(results, &match?({:ok, _}, &1)) == 1
        assert Enum.count(results, &match?({:error, :conflict}, &1)) == 3

        assert {:ok, fetched} = OperationRecords.fetch(fixture.repo, prepared["operation_id"])
        assert fetched["attempt"]["dispatch_state"] == "send_claimed"
        assert fetched["attempt"]["lock_version"] == 1
      end

      ## 8. Receipt idempotence and accepted-result immutability

      test "evidence and accepted Results are idempotent and never overwritten", %{
        fixture: fixture
      } do
        {{:ok, prepared}, attrs} = prepare(fixture)

        evidence = %{
          id: Ecto.UUID.generate(),
          operation_id: prepared["operation_id"],
          attempt_id: attrs.attempt.attempt_id,
          executor_id: attrs.attempt.executor_id,
          evidence_id: Ecto.UUID.generate(),
          content: %{"status" => "success", "output" => %{"stdout" => "done"}}
        }

        assert {:ok, first} = OperationRecords.record_evidence(fixture.repo, evidence)
        assert {:ok, ^first} = OperationRecords.record_evidence(fixture.repo, evidence)

        conflicting = %{evidence | content: %{"status" => "failed"}}
        assert {:error, :conflict} = OperationRecords.record_evidence(fixture.repo, conflicting)
        assert [[1]] == sql(fixture, "SELECT COUNT(*) FROM execution_evidence").rows

        bytes = :crypto.strong_rand_bytes(64)

        artifact = %{
          id: Ecto.UUID.generate(),
          content: bytes,
          digest: Codec.hash(bytes),
          size: byte_size(bytes),
          media_type: "application/octet-stream",
          recorded_at: DateTime.utc_now()
        }

        accept = %{
          operation_id: prepared["operation_id"],
          expected_version: 0,
          result: %{"status" => "success", "output" => %{"stdout" => "done"}},
          event: event("result.accepted", %{"operation_id" => prepared["operation_id"]})
        }

        assert {:ok, _} =
                 Transaction.write(fixture.repo, fn -> Artifacts.put(fixture.repo, artifact) end)

        assert {:ok, accepted} =
                 OperationRecords.accept_result(
                   fixture.repo,
                   Map.put(accept, :artifact_ids, [artifact.id])
                 )

        assert {:ok, ^accepted} =
                 OperationRecords.accept_result(
                   fixture.repo,
                   Map.put(accept, :artifact_ids, [artifact.id])
                 )

        assert {:error, :conflict} =
                 OperationRecords.accept_result(fixture.repo, %{
                   accept
                   | result: %{"status" => "uncertain"}
                 })

        assert {:ok, fetched} = OperationRecords.fetch(fixture.repo, prepared["operation_id"])
        assert fetched["operation"]["accepted_result"] == accept.result
      end

      ## 9. Safe error mapping and unknown outcome

      test "errors are taxonomy atoms with no SQL, connection or secret detail", %{
        fixture: fixture
      } do
        for bad <- [
              %{id: "not-a-uuid"},
              %{definition: %{"credentials" => %{"k" => "v"}}},
              %{definition: %{"nested" => %{"credentials" => %{"k" => "v"}}}}
            ] do
          attrs =
            create_attrs(fixture.authority_id)
            |> Map.merge(bad)
            |> then(fn attrs ->
              Map.put(attrs, :command, command(%{"op" => "create_agent", "agent_id" => attrs.id}))
            end)

          assert {:error, reason} = AgentRecords.create_agent(fixture.repo, attrs)
          assert reason in @errors
          refute inspect(reason) =~ "SELECT"
        end

        # A driver-level failure inside a write transaction is outcome-unknown, not
        # "absent": the caller must reconcile by stable identity.
        assert {:error, :storage_outcome_unknown} = Fixture.driver_failure(fixture)

        assert [[0]] == sql(fixture, "SELECT COUNT(*) FROM agents").rows
      end

      ## 10. Raw objects and structured credentials

      test "raw objects, secrets and unknown fields are rejected at the write entry", %{
        fixture: fixture
      } do
        pid = Ecto.UUID.generate()

        for definition <- [
              %{"live" => self()},
              %{"ref" => make_ref()},
              %{"atom" => :not_persisted},
              %{"tuple" => {1, 2}},
              %{"struct" => DateTime.utc_now()},
              %{"bin" => <<0xFF>>},
              %{"credentials" => %{"password" => "x"}},
              %{"authorization" => "Bearer abc"},
              deep_payload()
            ] do
          attrs =
            create_attrs(fixture.authority_id, %{
              id: pid,
              command: command(%{"op" => "create_agent", "agent_id" => pid}),
              definition: definition
            })

          assert {:error, reason} = AgentRecords.create_agent(fixture.repo, attrs)
          assert reason in [:invalid_data, :limit]
        end

        assert [[0]] == sql(fixture, "SELECT COUNT(*) FROM agents").rows

        # Operation descriptions reject live objects and unknown envelope fields.
        for description <- [
              %{"kind" => "x", "protocol_version" => 1, "payload" => %{"p" => self()}},
              %{"kind" => "x", "protocol_version" => 0, "payload" => %{}},
              %{"kind" => "x", "protocol_version" => 1},
              %{"kind" => "x", "protocol_version" => 1, "payload" => %{}, "credentials" => %{}}
            ] do
          attrs =
            Map.merge(
              %{attempt: nil, event: event("operation.prepared")},
              %{operation: Map.merge(%{id: Ecto.UUID.generate()}, %{description: description})}
            )

          assert {:error, reason} = OperationRecords.prepare(fixture.repo, attrs)
          assert reason in [:invalid_data, :limit]
        end

        assert [[0]] == sql(fixture, "SELECT COUNT(*) FROM operations").rows
      end

      ## 11. Page and transaction budget bounds

      test "page and payload budgets are explicit errors, never truncation", %{fixture: fixture} do
        {:ok, created} =
          AgentRecords.create_agent(fixture.repo, create_attrs(fixture.authority_id))

        agent_id = created["agent_id"]

        assert {:ok, %{"events" => [event], "next_cursor" => 1}} =
                 AgentRecords.history_page(fixture.repo, agent_id, limit: 1)

        assert event["seq"] == 1

        assert {:error, :invalid_data} =
                 AgentRecords.history_page(fixture.repo, agent_id, limit: 0)

        assert {:error, :limit} = AgentRecords.history_page(fixture.repo, agent_id, limit: 501)

        assert {:error, :invalid_data} =
                 AgentRecords.history_page(fixture.repo, agent_id, bogus: 1)

        assert {:error, :invalid_data} = AgentRecords.history_page(fixture.repo, "nope")

        oversized = %{
          "kind" => "tool_call",
          "protocol_version" => 1,
          "payload" => %{"blob" => String.duplicate("x", 1_048_577)}
        }

        attrs = %{
          operation: %{id: Ecto.UUID.generate(), description: oversized},
          attempt: nil,
          event: event("operation.prepared")
        }

        assert {:error, :limit} = OperationRecords.prepare(fixture.repo, attrs)
        assert [[0]] == sql(fixture, "SELECT COUNT(*) FROM operations").rows

        # Cross-table reference integrity is enforced inside one transaction.
        assert {:error, :artifact_missing} =
                 OperationRecords.accept_result(fixture.repo, %{
                   operation_id:
                     prepare(fixture) |> elem(0) |> elem(1) |> Map.fetch!("operation_id"),
                   expected_version: 0,
                   result: %{"status" => "success"},
                   artifact_ids: [Ecto.UUID.generate()],
                   event: event("result.accepted")
                 })
      end

      defp deep_payload do
        Enum.reduce(1..40, "leaf", fn _, acc -> %{"n" => acc} end)
      end
    end
  end
end

defmodule Beamlet.Storage.SQLiteContractTest do
  use Beamlet.Storage.ContractSuite, backend: :sqlite
end

defmodule Beamlet.Storage.PostgresContractTest do
  use Beamlet.Storage.ContractSuite, backend: :postgres

  alias Beamlet.Storage.ContractFixture

  test "a connection whose synchronous_commit was downgraded is rejected by the guard", %{
    fixture: fixture
  } do
    assert {:raised, message} = ContractFixture.reject_downgraded(fixture)
    assert message =~ "unsupported storage connection settings"
  end
end
