Code.require_file("../../support/contract_fixture.ex", __DIR__)

defmodule Beamlet.Agent.Storage.Contract do
  @moduledoc false
  defmacro __using__(backend: backend) do
    [
      support(backend),
      preparation_tests(),
      extra_tests(),
      profile_tests(),
      invalid_data_tests(),
      lifecycle_tests(),
      rollback_tests(),
      control_tests(),
      execution_tests(),
      request_tests(),
      concurrency_tests(),
      review_tests(),
      continuation_tests()
    ]
  end

  defp support(backend) do
    quote do
      use ExUnit.Case, async: false

      alias Beamlet.Actions.Storage.OperationRecords, as: ActionsOperations
      alias Beamlet.Actions.Storage.Schema.OperationEvent
      alias Beamlet.Agent.Storage.AgentRecords
      alias Beamlet.Agent.Storage.Codec
      alias Beamlet.Agent.Storage.ContractFixture
      alias Beamlet.Agent.Storage.History
      alias Beamlet.Agent.Storage.OperationRecords
      alias Beamlet.Agent.Storage.Read
      alias Beamlet.Agent.Storage.Schema.Agent
      alias Beamlet.Agent.Storage.Schema.Command
      alias Beamlet.Agent.Storage.Schema.Event
      alias Beamlet.Agent.Storage.Schema.Operation

      @backend unquote(backend)
      alias Beamlet.Storage.Dataset

      test "installed facts and exact format3 manifest survive reopen", %{fixture: f, repo: repo} do
        tables =
          ~w(agents agent_events agent_operations checkpoints operations executions execution_evidence operation_events dispatch_scopes commands artifacts storage_metadata schema_migrations)

        tables =
          if @backend == :postgres, do: ["agent_operation_projections" | tables], else: tables

        assert ContractFixture.tables(f) == Enum.sort(tables)

        assert ContractFixture.sql(
                 f,
                 "SELECT dataset_id, profile, format_version FROM storage_metadata"
               ).rows == [[f.authority_id, "agent-authority", 3]]

        assert Enum.sort(ContractFixture.sql(f, "SELECT version FROM schema_migrations").rows) ==
                 [[1], [100], [300]]

        {pos, _, _} = create(f)
        repo.stop()
        assert {:ok, _} = Dataset.open(repo, f.opts)
        assert {:ok, %{"agent" => agent}} = AgentRecords.fetch(repo, pos.agent_id)
        assert agent["id"] == pos.agent_id
      end

      test "durable connections and safe driver failure", %{fixture: f} do
        settings = ContractFixture.settings(f)
        assert settings.connections == f.pool_size
        assert Enum.all?(settings.per_connection, &(&1 == settings.required))
        assert {:error, :storage_outcome_unknown} = ContractFixture.driver_failure(f)
      end

      test "wrong identity, newer format and restored backup refuse reopen", %{
        fixture: f,
        repo: repo
      } do
        repo.stop()

        assert {:error, :dataset_mismatch} =
                 Dataset.open(repo, Keyword.put(f.opts, :dataset_id, Ecto.UUID.generate()))

        assert {:ok, _} = Dataset.open(repo, f.opts)
        ContractFixture.sql(f, "UPDATE storage_metadata SET format_version = 4")
        repo.stop()
        assert {:error, :schema_unsupported} = Dataset.open(repo, f.opts)

        {:ok, raw} =
          ContractFixture.raw_connection(%{backend: @backend, database: f.opts[:database]})

        ContractFixture.run_raw(
          raw,
          "UPDATE storage_metadata SET format_version = 3, restored_backup = TRUE"
        )

        ContractFixture.close_raw(raw)
        assert {:error, :restored_backup} = Dataset.open(repo, f.opts)
      end

      setup do
        fixture = ContractFixture.open(@backend)
        on_exit(fn -> ContractFixture.close(fixture) end)
        {:ok, fixture: fixture, repo: fixture.repo}
      end

      defp create(fixture) do
        attrs = %{
          id: Ecto.UUID.generate(),
          command_id: Ecto.UUID.generate(),
          authority_id: fixture.authority_id,
          definition: %{"version" => 1}
        }

        assert {:ok, response} = AgentRecords.create_agent(fixture.repo, attrs)
        assert {:ok, ^response} = AgentRecords.create_agent(fixture.repo, attrs)

        assert {:ok, ^response} =
                 AgentRecords.command_response(fixture.repo, attrs.id, attrs.command_id)

        assert {:error, :conflict} =
                 AgentRecords.create_agent(fixture.repo, %{attrs | definition: %{"version" => 2}})

        pos = %{agent_id: attrs.id, generation: 0, lock_version: 0}

        input = %{
          command_id: Ecto.UUID.generate(),
          position: pos,
          turn_id: Ecto.UUID.generate(),
          input: %{"text" => "original input"}
        }

        assert {:ok, accepted} = AgentRecords.accept_input(fixture.repo, input)
        {Map.put(pos, :lock_version, 1), input.turn_id, accepted}
      end

      defp member(pos, turn, ordinal) do
        %{
          operation: %{
            id: Ecto.UUID.generate(),
            owner_agent_id: pos.agent_id,
            turn_id: turn,
            step_id: "step-1",
            role: "tool",
            ordinal: ordinal,
            tool_call_id: "call-#{ordinal}",
            sources: [],
            description: %{
              "kind" => "tool_call",
              "protocol_version" => 1,
              "payload" => %{"arguments" => %{"text" => "request body"}}
            }
          },
          attempt: %{
            attempt_id: Ecto.UUID.generate(),
            executor_id: Ecto.UUID.generate(),
            executor_boot_id: Ecto.UUID.generate(),
            budget: %{}
          }
        }
      end

      defp batch(pos, turn, members) do
        %{
          command_id: Ecto.UUID.generate(),
          position: pos,
          turn_id: turn,
          operations: members,
          orchestration: %{"mode" => "all"}
        }
      end
    end
  end

  defp preparation_tests do
    quote do
      test "atomic prepare, independent concurrent accept and reference consume", %{
        fixture: f,
        repo: repo
      } do
        {pos, turn, input} = create(f)
        [input_event] = input["events"]
        {:ok, digest} = Codec.digest(input_event["payload"], :event)
        first = member(pos, turn, 0)

        first =
          put_in(first, [:operation, :sources], [
            %{"type" => "input", "event_id" => input_event["id"], "seq" => 2, "digest" => digest}
          ])

        attrs = batch(pos, turn, [first, member(pos, turn, 1)])
        assert {:ok, prepared} = AgentRecords.prepare_operations(repo, attrs)
        assert prepared["through_seq"] == 4
        assert {:ok, ^prepared} = AgentRecords.prepare_operations(repo, attrs)

        refs =
          prepared["operations"]
          |> Enum.map(fn op ->
            Task.async(fn ->
              args = %{
                operation_id: op["operation_id"],
                expected_version: 0,
                result: %{"status" => "success", "output" => "reply body"}
              }

              assert {:ok, result} = ActionsOperations.accept_result(repo, args)
              assert {:ok, ^result} = ActionsOperations.accept_result(repo, args)

              assert {:error, :conflict} =
                       ActionsOperations.accept_result(repo, %{
                         args
                         | result: %{"status" => "other"}
                       })

              %{
                "operation_id" => op["operation_id"],
                "accepted_digest" => result["accepted_digest"],
                "consumption_kind" => "tool_result"
              }
            end)
          end)
          |> Enum.map(&Task.await(&1, 10_000))

        assert {:ok, agent} = AgentRecords.fetch(repo, pos.agent_id)
        assert agent["agent"]["lock_version"] == 2

        consume = %{
          command_id: Ecto.UUID.generate(),
          position: %{pos | lock_version: 2},
          turn_id: turn,
          accepted_refs: refs,
          join: %{}
        }

        assert {:ok, consumed} = AgentRecords.consume_results(repo, consume)
        assert consumed["through_seq"] == 6
        assert {:ok, ^consumed} = AgentRecords.consume_results(repo, consume)

        assert {:error, :conflict} =
                 AgentRecords.consume_results(repo, %{
                   consume
                   | command_id: Ecto.UUID.generate(),
                     position: %{pos | lock_version: 3}
                 })

        assert {:ok, page} = History.event_page(repo, pos.agent_id, through_seq: 6)
        assert Enum.map(page["events"], & &1["seq"]) == Enum.to_list(1..6)
        refute inspect(page["events"]) =~ "request body"
        refute inspect(page["events"]) =~ "reply body"

        for op <- prepared["operations"] do
          assert {:ok, first} = History.operation_event(repo, op["operation_id"], 1)
          assert {:ok, second} = History.operation_event(repo, op["operation_id"], 2)
          own = %{"events" => [first, second]}
          assert Enum.map(own["events"], & &1["seq"]) == [1, 2]
          assert {:ok, body} = OperationRecords.fetch(repo, op["operation_id"])
          assert body["operation"]["accepted_result"]["output"] == "reply body"
        end
      end
    end
  end

  defp rollback_tests do
    quote do
      test "prepare failure after first member rolls back all work", %{fixture: f, repo: repo} do
        {pos, turn, _} = create(f)
        a = member(pos, turn, 0)
        b = member(pos, turn, 1)
        # A duplicate attempt primary key fails after the first Operation and attempt.
        b = put_in(b, [:attempt, :attempt_id], a.attempt.attempt_id)

        assert {:error, :conflict} =
                 AgentRecords.prepare_operations(repo, batch(pos, turn, [a, b]))

        assert repo.aggregate(Operation, :count) == 0
        assert repo.aggregate(Event, :count) == 2
        assert {:ok, state} = AgentRecords.fetch(repo, pos.agent_id)
        assert state["agent"]["lock_version"] == 1
      end

      test "forged digest, foreign turn, owner and stale generation reject atomically", %{
        fixture: f,
        repo: repo
      } do
        {pos, turn, _} = create(f)

        assert {:ok, prepared} =
                 AgentRecords.prepare_operations(repo, batch(pos, turn, [member(pos, turn, 0)]))

        [op] = prepared["operations"]

        assert {:ok, result} =
                 ActionsOperations.accept_result(repo, %{
                   operation_id: op["operation_id"],
                   expected_version: 0,
                   result: %{"status" => "success"}
                 })

        ref = %{
          "operation_id" => op["operation_id"],
          "accepted_digest" => result["accepted_digest"],
          "consumption_kind" => "tool_result"
        }

        attrs = %{
          command_id: Ecto.UUID.generate(),
          position: %{pos | lock_version: 2},
          turn_id: turn,
          accepted_refs: [ref],
          join: %{}
        }

        bad =
          put_in(attrs, [:accepted_refs], [
            %{ref | "accepted_digest" => String.duplicate("0", 64)}
          ])

        assert {:error, :conflict} = AgentRecords.consume_results(repo, bad)

        assert {:error, :conflict} =
                 AgentRecords.consume_results(repo, %{attrs | turn_id: Ecto.UUID.generate()})

        {foreign, foreign_turn, _} = create(f)

        assert {:error, :conflict} =
                 AgentRecords.consume_results(repo, %{
                   attrs
                   | position: foreign,
                     turn_id: foreign_turn
                 })

        assert {:ok, _} =
                 AgentRecords.restore(repo, %{
                   command_id: Ecto.UUID.generate(),
                   position: attrs.position
                 })

        assert {:error, :stale_generation} = AgentRecords.consume_results(repo, attrs)
        current = %{attrs.position | generation: 1, lock_version: 3}

        assert {:error, :conflict} =
                 AgentRecords.consume_results(repo, %{attrs | position: current})

        assert repo.aggregate(Event, :count) == 6
        assert repo.aggregate(OperationEvent, :count) == 2
      end
    end
  end

  defp control_tests do
    quote do
      test "checkpoint is optional, positioned and body-free", %{fixture: f, repo: repo} do
        {pos, _turn, _} = create(f)
        assert {:ok, %{"checkpoint" => nil}} = History.checkpoint_at(repo, pos.agent_id, 2)

        cp = %{
          command_id: Ecto.UUID.generate(),
          position: pos,
          id: Ecto.UUID.generate(),
          through_seq: 2,
          reducer_version: 1,
          projection: %{"pending" => [], "input_refs" => [2]},
          continuation: "await_input",
          safe_to_fork: true
        }

        assert {:error, :invalid_data} =
                 AgentRecords.checkpoint(repo, %{cp | projection: %{"messages" => []}})

        assert {:error, :conflict} = AgentRecords.checkpoint(repo, %{cp | through_seq: 3})
        assert {:ok, _} = AgentRecords.checkpoint(repo, cp)
        assert {:ok, %{"checkpoint" => checkpoint}} = History.checkpoint_at(repo, pos.agent_id, 2)
        assert checkpoint["through_seq"] == 2
        assert checkpoint["reducer_version"] == 1
        assert {:ok, page} = History.event_page(repo, pos.agent_id, limit: 1, through_seq: 2)
        assert page["next_cursor"] == 1
        assert {:error, :limit} = History.event_page(repo, pos.agent_id, limit: 501)
        # Corrupt cache content cannot prevent reading events or Operation bodies.
        ContractFixture.sql(f, "UPDATE checkpoints SET data = 'invalid' WHERE id = $1", [cp.id])
        assert {:ok, %{"checkpoint" => nil}} = History.checkpoint_at(repo, pos.agent_id, 2)
        assert {:ok, events} = History.event_page(repo, pos.agent_id)
        assert List.last(events["events"])["payload"] == %{"text" => "original input"}
      end

      test "competing controls yield one committed continuous position", %{fixture: f, repo: repo} do
        {pos, turn, _} = create(f)

        results =
          for _ <- 1..4 do
            Task.async(fn ->
              AgentRecords.advance(repo, %{
                command_id: Ecto.UUID.generate(),
                position: pos,
                turn_id: turn,
                type: "turn.interrupted",
                payload: %{"reason" => "explicit"}
              })
            end)
          end
          |> Enum.map(&Task.await(&1, 10_000))

        assert Enum.count(results, &match?({:ok, _}, &1)) == 1
        assert {:ok, page} = History.event_page(repo, pos.agent_id)
        assert Enum.map(page["events"], & &1["seq"]) == [1, 2, 3]
      end
    end
  end

  defp execution_tests do
    quote do
      test "claim is single-use, evidence replay checks identity, and dangling artifacts reject",
           %{fixture: f, repo: repo} do
        {pos, turn, _} = create(f)
        m = member(pos, turn, 0)
        assert {:ok, _} = AgentRecords.prepare_operations(repo, batch(pos, turn, [m]))

        claim = %{
          operation_id: m.operation.id,
          attempt_id: m.attempt.attempt_id,
          expected_version: 0
        }

        results =
          for _ <- 1..4, do: Task.async(fn -> ActionsOperations.claim_dispatch(repo, claim) end)

        assert Enum.count(Enum.map(results, &Task.await/1), &match?({:ok, _}, &1)) == 1

        evidence = %{
          id: Ecto.UUID.generate(),
          operation_id: m.operation.id,
          attempt_id: m.attempt.attempt_id,
          executor_id: m.attempt.executor_id,
          evidence_id: Ecto.UUID.generate(),
          content: %{"receipt" => "done"}
        }

        assert {:ok, receipt} = ActionsOperations.record_evidence(repo, evidence)
        assert {:ok, ^receipt} = ActionsOperations.record_evidence(repo, evidence)

        assert {:error, :conflict} =
                 ActionsOperations.record_evidence(repo, %{
                   evidence
                   | content: %{"receipt" => "different"}
                 })

        accept = %{
          operation_id: m.operation.id,
          expected_version: 0,
          result: %{"status" => "success"},
          evidence_id: evidence.id
        }

        assert {:error, :artifact_missing} =
                 ActionsOperations.accept_result(
                   repo,
                   Map.put(accept, :artifact_ids, [Ecto.UUID.generate()])
                 )

        assert {:ok, %{"operation" => %{"accepted_result" => nil}}} =
                 OperationRecords.fetch(repo, m.operation.id)

        assert {:ok, _} = ActionsOperations.accept_result(repo, accept)
        other = member(%{pos | lock_version: 2}, turn, 1)

        assert {:ok, _} =
                 AgentRecords.prepare_operations(
                   repo,
                   batch(%{pos | lock_version: 2}, turn, [other])
                 )

        assert {:ok, _} =
                 AgentRecords.restore(repo, %{
                   command_id: Ecto.UUID.generate(),
                   position: %{pos | lock_version: 3}
                 })

        assert {:error, :stale_epoch} =
                 ActionsOperations.claim_dispatch(repo, %{
                   claim
                   | operation_id: other.operation.id,
                     attempt_id: other.attempt.attempt_id
                 })
      end

      test "failure on second consumption event rolls back first event and Agent CAS", %{
        fixture: f,
        repo: repo
      } do
        {pos, turn, _} = create(f)

        assert {:ok, prepared} =
                 AgentRecords.prepare_operations(
                   repo,
                   batch(pos, turn, [member(pos, turn, 0), member(pos, turn, 1)])
                 )

        refs =
          Enum.map(prepared["operations"], fn op ->
            assert {:ok, accepted} =
                     ActionsOperations.accept_result(repo, %{
                       operation_id: op["operation_id"],
                       expected_version: 0,
                       result: %{"status" => "success"}
                     })

            %{
              "operation_id" => op["operation_id"],
              "accepted_digest" => accepted["accepted_digest"],
              "consumption_kind" => "tool_result"
            }
          end)

        ContractFixture.reject_consumption(f, 6)

        assert {:error, reason} =
                 AgentRecords.consume_results(repo, %{
                   command_id: Ecto.UUID.generate(),
                   position: %{pos | lock_version: 2},
                   turn_id: turn,
                   accepted_refs: refs,
                   join: %{}
                 })

        assert reason in [:conflict, :invalid_data, :storage_outcome_unknown]
        assert {:ok, page} = History.event_page(repo, pos.agent_id)
        assert Enum.map(page["events"], & &1["seq"]) == [1, 2, 3, 4]
        assert {:ok, state} = AgentRecords.fetch(repo, pos.agent_id)
        assert state["agent"]["lock_version"] == 2
      end
    end
  end

  defp request_tests do
    quote do
      test "fixed request rejects forged sources, body control and credentials without preparing work",
           %{fixture: f, repo: repo} do
        {pos, turn, input} = create(f)
        m = member(pos, turn, 0)
        [event] = input["events"]

        forged =
          put_in(m, [:operation, :sources], [
            %{
              "type" => "input",
              "event_id" => event["id"],
              "seq" => 2,
              "digest" => String.duplicate("0", 64)
            }
          ])

        assert {:error, :conflict} =
                 AgentRecords.prepare_operations(repo, batch(pos, turn, [forged]))

        secret =
          put_in(m, [:operation, :description, "payload"], %{"client_secret" => "never-store"})

        assert {:error, :invalid_data} =
                 AgentRecords.prepare_operations(repo, batch(pos, turn, [secret]))

        assert {:error, :invalid_data} =
                 AgentRecords.prepare_operations(repo, %{
                   batch(pos, turn, [m])
                   | orchestration: %{"nested" => %{"reply" => "body"}}
                 })

        assert repo.aggregate(Operation, :count) == 0
        assert {:ok, _} = AgentRecords.prepare_operations(repo, batch(pos, turn, [m]))

        {:ok, result} =
          ActionsOperations.accept_result(repo, %{
            operation_id: m.operation.id,
            expected_version: 0,
            result: %{"status" => "success"}
          })

        ref = %{
          "operation_id" => m.operation.id,
          "accepted_digest" => result["accepted_digest"],
          "consumption_kind" => "tool_result"
        }

        next =
          member(pos, turn, 1)
          |> put_in([:operation, :sources], [%{"type" => "accepted_result", "reference" => ref}])

        assert {:error, :conflict} =
                 AgentRecords.prepare_operations(
                   repo,
                   batch(%{pos | lock_version: 2}, turn, [next])
                 )

        assert {:error, :conflict} =
                 AgentRecords.consume_results(repo, %{
                   command_id: Ecto.UUID.generate(),
                   position: %{pos | lock_version: 2},
                   turn_id: turn,
                   accepted_refs: [%{ref | "consumption_kind" => "model_result"}],
                   join: %{}
                 })
      end
    end
  end

  defp concurrency_tests do
    quote do
      test "claim serializes with uncommitted activation and terminal acceptance", %{
        fixture: f,
        repo: repo
      } do
        for change <- [:restore, :accept] do
          {pos, turn, _} = create(f)
          m = member(pos, turn, 0)
          assert {:ok, _} = AgentRecords.prepare_operations(repo, batch(pos, turn, [m]))
          parent = self()

          writer =
            Task.async(fn -> hold_write(repo, parent, change, pos, m) end)

          assert_receive {:write_held, writer_pid}, 2000

          claimant =
            Task.async(fn ->
              ActionsOperations.claim_dispatch(repo, %{
                operation_id: m.operation.id,
                attempt_id: m.attempt.attempt_id,
                expected_version: 0
              })
            end)

          try do
            assert Task.yield(claimant, 100) == nil
          after
            send(writer_pid, :release_write)
          end

          assert {:ok, :ok} = Task.await(writer)
          expected = if change == :restore, do: :stale_epoch, else: :conflict
          assert {:error, ^expected} = Task.await(claimant)
        end
      end

      defp hold_write(repo, parent, change, pos, m) do
        repo.transaction(fn ->
          assert {:ok, _} = change_before_claim(repo, change, pos, m)
          send(parent, {:write_held, self()})
          receive do: (:release_write -> :ok)
        end)
      end

      defp change_before_claim(repo, :restore, pos, _m) do
        AgentRecords.restore(repo, %{
          command_id: Ecto.UUID.generate(),
          position: %{pos | lock_version: 2}
        })
      end

      defp change_before_claim(repo, :accept, _pos, m) do
        ActionsOperations.accept_result(repo, %{
          operation_id: m.operation.id,
          expected_version: 0,
          result: %{"status" => "uncertain"}
        })
      end
    end
  end

  defp review_tests do
    quote do
      test "accepted work cannot acquire first dispatch permission", %{fixture: f, repo: repo} do
        {pos, turn, _} = create(f)
        m = member(pos, turn, 0)
        attrs = batch(pos, turn, [m])
        assert {:ok, prepared} = AgentRecords.prepare_operations(repo, attrs)

        assert {:ok, _} =
                 ActionsOperations.accept_result(repo, %{
                   operation_id: m.operation.id,
                   expected_version: 0,
                   result: %{"status" => "uncertain"}
                 })

        assert {:ok, ^prepared} = AgentRecords.prepare_operations(repo, attrs)

        assert {:error, :conflict} =
                 ActionsOperations.claim_dispatch(repo, %{
                   operation_id: m.operation.id,
                   attempt_id: m.attempt.attempt_id,
                   expected_version: 0
                 })

        assert {:ok, %{"attempt" => %{"dispatch_state" => "prepared"}}} =
                 OperationRecords.fetch(repo, m.operation.id)
      end

      test "all control write entries reject foreign operations and missing artifacts", %{
        fixture: f,
        repo: repo
      } do
        {foreign, foreign_turn, _} = create(f)
        m = member(foreign, foreign_turn, 0)
        assert {:ok, _} = AgentRecords.prepare_operations(repo, batch(foreign, foreign_turn, [m]))
        {pos, turn, _} = create(f)

        for bad <- [%{"operation_id" => m.operation.id}, %{"artifact_id" => Ecto.UUID.generate()}] do
          assert {:error, reason} =
                   AgentRecords.advance(repo, %{
                     command_id: Ecto.UUID.generate(),
                     position: pos,
                     turn_id: turn,
                     type: "context.selected",
                     payload: %{"selected" => [bad]}
                   })

          assert reason in [:conflict, :artifact_missing]

          assert {:error, ^reason} =
                   AgentRecords.prepare_operations(
                     repo,
                     %{batch(pos, turn, [member(pos, turn, 0)]) | orchestration: bad}
                   )

          assert {:error, ^reason} =
                   AgentRecords.consume_results(repo, %{
                     command_id: Ecto.UUID.generate(),
                     position: pos,
                     turn_id: turn,
                     accepted_refs: [%{}],
                     join: bad
                   })
        end

        assert {:ok, state} = AgentRecords.fetch(repo, pos.agent_id)
        assert state["agent"]["lock_version"] == 1
        assert repo.aggregate(Operation, :count) == 1
      end

      test "turn pagination uses complete groups and first sequence cursor", %{
        fixture: f,
        repo: repo
      } do
        {pos, first, _} = create(f)
        second = Ecto.UUID.generate()

        assert {:ok, _} =
                 AgentRecords.accept_input(repo, %{
                   command_id: Ecto.UUID.generate(),
                   position: pos,
                   turn_id: second,
                   input: %{"text" => "second"}
                 })

        # A later control fact can still refer to the first turn.
        assert {:ok, _} =
                 AgentRecords.advance(repo, %{
                   command_id: Ecto.UUID.generate(),
                   position: %{pos | lock_version: 2},
                   turn_id: first,
                   type: "turn.interrupted",
                   payload: %{}
                 })

        assert {:ok, page} = History.turns(repo, pos.agent_id, limit: 1)
        assert [%{"turn_id" => ^first, "first_seq" => 2, "last_seq" => 4}] = page["turns"]
        assert page["next_cursor"] == 2
        assert {:ok, next} = History.turns(repo, pos.agent_id, limit: 1, after_first_seq: 2)
        assert [%{"turn_id" => ^second, "first_seq" => 3}] = next["turns"]
        assert {:ok, %{"turns" => []}} = History.turns(repo, pos.agent_id, after_first_seq: 3)
      end
    end
  end

  defp lifecycle_tests do
    quote do
      test "concurrent identical commands create exactly one Agent and replay the same response",
           %{fixture: f, repo: repo} do
        attrs = %{
          id: Ecto.UUID.generate(),
          command_id: Ecto.UUID.generate(),
          authority_id: f.authority_id,
          definition: %{}
        }

        tasks = for _ <- 1..4, do: Task.async(fn -> AgentRecords.create_agent(repo, attrs) end)
        results = Enum.map(tasks, &Task.await/1)
        assert Enum.all?(results, &(match?({:ok, _}, &1) or &1 == {:error, :conflict}))
        {:ok, response} = Enum.find(results, &match?({:ok, _}, &1))
        assert {:ok, ^response} = AgentRecords.create_agent(repo, attrs)
        assert repo.aggregate(Agent, :count) == 1
        assert repo.aggregate(Command, :count) == 1
        assert repo.aggregate(Event, :count) == 1
      end

      test "raw objects, unknown fields and payload/page limits reject at facade", %{
        fixture: f,
        repo: repo
      } do
        attrs = %{
          id: Ecto.UUID.generate(),
          command_id: Ecto.UUID.generate(),
          authority_id: f.authority_id,
          definition: %{}
        }

        for definition <- [
              %{"pid" => self()},
              %{"credentials" => %{}},
              %{"tuple" => {:invalid, 1}}
            ] do
          assert {:error, :invalid_data} =
                   AgentRecords.create_agent(repo, %{attrs | definition: definition})
        end

        assert {:error, :invalid_data} =
                 AgentRecords.create_agent(repo, Map.put(attrs, :unknown, 1))

        assert repo.aggregate(Agent, :count) == 0
        m = member(%{agent_id: Ecto.UUID.generate()}, Ecto.UUID.generate(), 0)

        op =
          Map.drop(m.operation, [
            :owner_agent_id,
            :turn_id,
            :step_id,
            :role,
            :ordinal,
            :tool_call_id
          ])

        huge =
          put_in(op, [:description, "payload"], %{
            "text" => String.duplicate("x", Codec.limit(:operation))
          })

        assert {:error, :limit} =
                 ActionsOperations.prepare(repo, %{
                   operation: Map.delete(huge, :sources),
                   attempt: m.attempt
                 })

        assert repo.aggregate(Operation, :count) == 0

        for opts <- [[limit: 0], [after_seq: -1], [unknown: 1]] do
          assert {:error, :invalid_data} = AgentRecords.history_page(repo, attrs.id, opts)
        end

        assert {:error, :invalid_data} = AgentRecords.history_page(repo, "nope")
      end
    end
  end

  defp profile_tests do
    quote do
      test "Agent profile freezes component identities and owns the association projection", %{
        fixture: f,
        repo: repo
      } do
        profile = Beamlet.Agent.Storage.Profiles.authority()
        assert profile.profile == "agent-authority"
        assert profile.format_version == 3

        assert profile.components == [
                 %{name: "foundation", version: 1},
                 %{name: "actions-authority", version: 1},
                 %{name: "agent", version: 1}
               ]

        assert Enum.map(profile.migrations, & &1.id) == [1, 100, 300]

        assert Enum.at(profile.migrations, 1) ==
                 Beamlet.Actions.Storage.Profiles.authority_migration()

        assert ContractFixture.sql(f, "SELECT version FROM schema_migrations ORDER BY version").rows ==
                 [[1], [100], [300]]

        tables = ContractFixture.tables(f)

        assert Enum.all?(
                 ~w(agents agent_events agent_operations checkpoints commands operations operation_events dispatch_scopes),
                 &(&1 in tables)
               )

        refute "events" in tables
        refute :owner_agent_id in Beamlet.Actions.Storage.Schema.Operation.__schema__(:fields)
        {pos, _, _} = create(f)
        assert {:ok, %{"agent" => agent}} = AgentRecords.fetch(repo, pos.agent_id)
        assert agent["dispatch_scope_id"] != agent["id"]
      end
    end
  end

  defp invalid_data_tests do
    quote do
      test "malformed Agent JSON is a safe domain error", %{fixture: f, repo: repo} do
        {pos, _, _} = create(f)

        ContractFixture.sql(f, "UPDATE agents SET definition = 'malformed' WHERE id = $1", [
          pos.agent_id
        ])

        assert {:error, :invalid_data} = AgentRecords.fetch(repo, pos.agent_id)
      end

      test "malformed attempt JSON and unrelated programmer errors stay distinct", %{
        fixture: f,
        repo: repo
      } do
        {pos, turn, _} = create(f)
        m = member(pos, turn, 0)
        assert {:ok, _} = AgentRecords.prepare_operations(repo, batch(pos, turn, [m]))

        ContractFixture.sql(
          f,
          "UPDATE executions SET budget = 'malformed' WHERE attempt_id = $1",
          [m.attempt.attempt_id]
        )

        assert {:error, :invalid_data} = OperationRecords.fetch(repo, m.operation.id)

        assert_raise ArgumentError, "unrelated programmer error", fn ->
          Read.read(fn ->
            raise ArgumentError, "unrelated programmer error"
          end)
        end
      end
    end
  end

  defp extra_tests do
    quote do
      test "continuation rollback preserves binding and successful adoption refreshes identity",
           %{fixture: f, repo: repo} do
        {pos, turn, _} = create(f)
        attrs = batch(pos, turn, [member(pos, turn, 0), member(pos, turn, 1)])
        assert {:ok, prepared} = AgentRecords.prepare_operations(repo, attrs)
        [pending, claimed] = prepared["operations"]

        assert {:ok, _} =
                 ActionsOperations.claim_dispatch(repo, %{
                   operation_id: claimed["operation_id"],
                   attempt_id: claimed["attempt_id"],
                   expected_version: 0
                 })

        assert {:ok, activated} =
                 AgentRecords.restore(repo, %{
                   command_id: Ecto.UUID.generate(),
                   position: %{pos | lock_version: prepared["lock_version"]}
                 })

        command = %{
          command_id: Ecto.UUID.generate(),
          position: %{pos | generation: 1, lock_version: activated["lock_version"]},
          turn_id: turn,
          type: "agent.continue_decided",
          payload: %{"resume_operations" => [pending["operation_id"], claimed["operation_id"]]}
        }

        assert {:error, :unresolved_execution} = AgentRecords.advance(repo, command)

        assert {:ok, %{"operation" => unchanged}} =
                 OperationRecords.fetch(repo, pending["operation_id"])

        assert unchanged["dispatch_epoch"] == 0
        assert unchanged["owner_generation"] == 0
        assert unchanged["lock_version"] == 0
        command = %{command | payload: %{"resume_operations" => [pending["operation_id"]]}}
        assert {:ok, _} = AgentRecords.advance(repo, command)
        assert {:ok, ^prepared} = AgentRecords.prepare_operations(repo, attrs)

        assert {:ok, %{"operation" => refreshed}} =
                 OperationRecords.fetch(repo, pending["operation_id"])

        assert refreshed["dispatch_epoch"] == 1
        assert refreshed["owner_generation"] == 1
        assert refreshed["lock_version"] == 1

        assert refreshed["sources"] ==
                 attrs.operations |> hd() |> Map.fetch!(:operation) |> Map.fetch!(:sources)

        expected =
          Map.take(
            refreshed,
            ~w(description_digest lock_version dispatch_scope_id dispatch_epoch)
          )

        stale = %{
          operation_id: pending["operation_id"],
          attempt_id: pending["attempt_id"],
          expected_version: 0,
          expected_operation: Map.put(expected, "lock_version", 0)
        }

        # Neutral participant uses atom-key expected binding.
        expected = %{
          description_digest: expected["description_digest"],
          lock_version: 1,
          dispatch_scope_id: expected["dispatch_scope_id"],
          dispatch_epoch: 1
        }

        assert {:error, :conflict} =
                 ActionsOperations.claim_dispatch(
                   repo,
                   %{stale | expected_operation: %{expected | lock_version: 0}}
                 )

        assert {:ok, _} =
                 ActionsOperations.claim_dispatch(
                   repo,
                   %{stale | expected_operation: expected}
                 )
      end

      test "claim commits before restore without querying or locking Agent", %{
        fixture: f,
        repo: repo
      } do
        {pos, turn, _} = create(f)
        m = member(pos, turn, 0)
        assert {:ok, response} = AgentRecords.prepare_operations(repo, batch(pos, turn, [m]))
        parent = self()

        claimant =
          Task.async(fn ->
            repo.transaction(fn ->
              assert {:ok, _} =
                       ActionsOperations.claim_dispatch(repo, %{
                         operation_id: m.operation.id,
                         attempt_id: m.attempt.attempt_id,
                         expected_version: 0
                       })

              send(parent, {:claimed, self()})
              receive do: (:commit -> :ok)
            end)
          end)

        assert_receive {:claimed, pid}, 2000

        restore =
          Task.async(fn ->
            AgentRecords.restore(repo, %{
              command_id: Ecto.UUID.generate(),
              position: %{pos | lock_version: response["lock_version"]}
            })
          end)

        try do
          assert Task.yield(restore, 100) == nil
        after
          send(pid, :commit)
        end

        assert {:ok, :ok} = Task.await(claimant)
        assert {:ok, _} = Task.await(restore)
        assert {:ok, %{"attempt" => attempt}} = OperationRecords.fetch(repo, m.operation.id)
        assert attempt["dispatch_state"] == "send_claimed"
      end
    end
  end

  defp continuation_tests do
    quote do
      test "explicit continuation adopts prepared and accepted identities but refuses claimed unresolved work",
           %{fixture: f, repo: repo} do
        {pos, turn, _} = create(f)

        assert {:ok, prepared} =
                 AgentRecords.prepare_operations(
                   repo,
                   batch(pos, turn, [
                     member(pos, turn, 0),
                     member(pos, turn, 1),
                     member(pos, turn, 2)
                   ])
                 )

        [fresh, accepted, claimed] = prepared["operations"]

        assert {:ok, result} =
                 ActionsOperations.accept_result(repo, %{
                   operation_id: accepted["operation_id"],
                   expected_version: 0,
                   result: %{"status" => "ok"}
                 })

        assert {:ok, _} =
                 ActionsOperations.claim_dispatch(repo, %{
                   operation_id: claimed["operation_id"],
                   attempt_id: claimed["attempt_id"],
                   expected_version: 0
                 })

        assert {:ok, activated} =
                 AgentRecords.restore(repo, %{
                   command_id: Ecto.UUID.generate(),
                   position: %{pos | lock_version: prepared["lock_version"]}
                 })

        position = %{pos | lock_version: activated["lock_version"], generation: 1}

        assert {:error, :stale_epoch} =
                 ActionsOperations.claim_dispatch(repo, %{
                   operation_id: fresh["operation_id"],
                   attempt_id: fresh["attempt_id"],
                   expected_version: 0
                 })

        command = %{
          command_id: Ecto.UUID.generate(),
          position: position,
          turn_id: turn,
          type: "agent.continue_decided",
          payload: %{"resume_operations" => [claimed["operation_id"]]}
        }

        assert {:error, :unresolved_execution} = AgentRecords.advance(repo, command)

        command = %{
          command
          | command_id: Ecto.UUID.generate(),
            payload: %{
              "resume_operations" => [fresh["operation_id"], accepted["operation_id"]]
            }
        }

        assert {:ok, continued} = AgentRecords.advance(repo, command)
        assert {:ok, ^continued} = AgentRecords.advance(repo, command)

        assert {:ok, _} =
                 ActionsOperations.claim_dispatch(repo, %{
                   operation_id: fresh["operation_id"],
                   attempt_id: fresh["attempt_id"],
                   expected_version: 0
                 })

        assert {:ok, _} =
                 AgentRecords.consume_results(repo, %{
                   command_id: Ecto.UUID.generate(),
                   position: %{position | lock_version: continued["lock_version"]},
                   turn_id: turn,
                   accepted_refs: [
                     %{
                       "operation_id" => accepted["operation_id"],
                       "accepted_digest" => result["accepted_digest"],
                       "consumption_kind" => "tool_result"
                     }
                   ],
                   join: %{}
                 })

        assert {:ok, %{"operation" => stored}} =
                 OperationRecords.fetch(repo, accepted["operation_id"])

        assert stored["accepted_result"] == %{"status" => "ok"}
      end
    end
  end
end

defmodule Beamlet.Agent.Storage.SQLiteContractTest do
  use Beamlet.Agent.Storage.Contract, backend: :sqlite
end

defmodule Beamlet.Agent.Storage.PostgresContractTest do
  use Beamlet.Agent.Storage.Contract, backend: :postgres

  test "a downgraded synchronous_commit connection is rejected", %{fixture: f} do
    assert {:raised, message} = ContractFixture.reject_downgraded(f)
    assert message =~ "unsupported storage connection settings"
  end
end
