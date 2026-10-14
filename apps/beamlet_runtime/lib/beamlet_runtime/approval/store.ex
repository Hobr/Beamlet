defmodule BeamletRuntime.Approval.Store do
  @moduledoc """
  Example local approval resource, not Beamlet's authority Storage backend.

  A separate durable SQLite database owns requests and immutable decisions.
  Stable {collection, intent_id} keys and request comparison provide unbounded
  creation deduplication while this database is retained. No TTL/delete API.
  Credentials are not persisted. decide accepts a principal authenticated by
  trusted local application code; identifiers are not network credentials.

  Restore the same service identity and database after restart. Never substitute
  an empty database for a lost service and claim the old guarantees still hold.
  WAL/FULL relies on actual filesystem durability; this is not a remote provider.
  """
  alias Beamlet.{Identity, Value}
  alias BeamletRuntime.Approval.{Repo, Schema}
  alias Ecto.Adapters.SQL

  @enforce_keys [:repo, :identity, :instance]
  defstruct @enforce_keys

  def start_link(opts) do
    database = Keyword.fetch!(opts, :database)

    if not is_binary(database) or database in ["", ":memory:"],
      do: raise(ArgumentError, "persistent approval database required")

    File.mkdir_p!(Path.dirname(Path.expand(database)))

    opts =
      Keyword.merge(opts,
        journal_mode: :wal,
        synchronous: :full,
        foreign_keys: :on,
        default_transaction_mode: :immediate,
        log: false
      )

    Repo.start_link(Keyword.put_new(opts, :name, nil))
  end

  def child_spec(opts),
    do: %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }

  def migrate(repo, identity) do
    if Identity.valid_text?(identity) do
      with_repo(repo, fn -> Ecto.Migrator.run(Repo, [{1, Schema}], :up, all: true, log: false) end)

      transaction(repo, fn ->
        sql("INSERT OR IGNORE INTO approval_service(singleton,identity,instance) VALUES(1,?,?)", [
          identity,
          Ecto.UUID.generate()
        ])

        verify_identity(identity)
      end)
    else
      {:error, :invalid_service_identity}
    end
  end

  def new(repo, identity) do
    case transaction(
           repo,
           fn ->
             verify_identity(identity)

             [[instance]] =
               sql("SELECT instance FROM approval_service WHERE singleton=1", []).rows

             instance
           end,
           :deferred
         ) do
      {:ok, instance} ->
        %__MODULE__{repo: repo, identity: identity, instance: instance}

      {:error, _reason} ->
        raise ArgumentError,
              "approval service must be available and initialized with the configured identity"
    end
  end

  @doc "Bounded local schema check, used before accepting a new Intent."
  def validate_request(request) do
    valid =
      is_map(request) and not is_struct(request) and
        Enum.sort(Map.keys(request)) == ["responders", "service", "subject"] and
        Identity.valid_text?(request["service"]) and is_list(request["responders"]) and
        request["responders"] != [] and Enum.all?(request["responders"], &Identity.valid_text?/1) and
        length(Enum.uniq(request["responders"])) == length(request["responders"])

    if valid, do: Value.validate(request), else: {:error, :invalid_approval_request}
  end

  def create(%__MODULE__{} = service, collection, intent_id, request) do
    with :ok <- validate_scope(service, collection, intent_id),
         :ok <- validate_request(request),
         true <- request["service"] == service.identity do
      transaction(service.repo, fn ->
        create_request(service, collection, intent_id, request)
      end)
    else
      false -> {:error, :approval_service_mismatch}
      error -> error
    end
  end

  defp create_request(service, collection, intent_id, request) do
    verify_service(service)

    sql("INSERT OR IGNORE INTO approvals(collection,intent_id,request) VALUES(?,?,?)", [
      collection,
      intent_id,
      Jason.encode!(request)
    ])

    approval = fetch(collection, intent_id)
    if approval.request !== request, do: Repo.rollback(:approval_request_conflict)
    approval
  end

  def read(%__MODULE__{} = service, collection, intent_id) do
    with :ok <- validate_scope(service, collection, intent_id) do
      transaction(
        service.repo,
        fn ->
          verify_service(service)
          fetch(collection, intent_id)
        end,
        :deferred
      )
    end
  end

  @doc "First authorized decision wins. Identical replay returns original receipt; changed decision or responder is rejected."
  def decide(%__MODULE__{} = service, collection, intent_id, principal, decision) do
    with :ok <- validate_scope(service, collection, intent_id),
         true <- Identity.valid_text?(principal) and decision in ["approved", "denied"] do
      transaction(service.repo, fn ->
        authorized_decision(service, collection, intent_id, principal, decision)
      end)
    else
      false -> {:error, :invalid_approval_decision}
      error -> error
    end
  end

  defp authorized_decision(service, collection, intent_id, principal, decision) do
    verify_service(service)
    approval = fetch(collection, intent_id)

    if principal not in approval.request["responders"],
      do: Repo.rollback(:responder_not_authorized)

    accept_decision(approval, collection, intent_id, principal, decision)
  end

  defp accept_decision(%{decision: nil}, collection, intent_id, principal, decision) do
    sql(
      "UPDATE approvals SET decision=?,decision_ref=?,responder=? WHERE collection=? AND intent_id=? AND decision IS NULL",
      [decision, Ecto.UUID.generate(), principal, collection, intent_id]
    )

    fetch(collection, intent_id)
  end

  defp accept_decision(
         %{decision: decision, responder: principal} = approval,
         _collection,
         _id,
         principal,
         decision
       ),
       do: approval

  defp accept_decision(_approval, _collection, _id, _principal, _decision),
    do: Repo.rollback(:approval_already_decided)

  defp fetch(collection, id) do
    case sql(
           "SELECT request,decision,decision_ref,responder FROM approvals WHERE collection=? AND intent_id=?",
           [collection, id]
         ).rows do
      [[request, decision, ref, responder]] ->
        %{
          request: Jason.decode!(request),
          decision: decision,
          decision_ref: ref,
          responder: responder,
          approval_ref: id
        }

      [] ->
        Repo.rollback(:approval_not_found)
    end
  end

  defp verify_identity(identity) do
    case sql("SELECT identity FROM approval_service WHERE singleton=1", []).rows do
      [[^identity]] -> :ok
      _mismatch -> Repo.rollback(:approval_service_mismatch)
    end
  end

  defp verify_service(%{identity: identity, instance: instance}) do
    case sql("SELECT identity,instance FROM approval_service WHERE singleton=1", []).rows do
      [[^identity, ^instance]] -> :ok
      _mismatch -> Repo.rollback(:approval_service_mismatch)
    end
  end

  defp validate_scope(service, collection, id) do
    if Identity.valid_text?(service.instance) and Identity.valid_text?(service.identity) and
         Identity.valid_text?(collection) and
         Identity.valid_text?(id), do: :ok, else: {:error, :invalid_approval_scope}
  end

  defp transaction(repo, fun, mode \\ :immediate) do
    with_repo(repo, fn -> Repo.transaction(fun, mode: mode, log: false) end)
  rescue
    _error -> {:error, :approval_service_unavailable}
  catch
    :exit, _reason -> {:error, :approval_service_unavailable}
  end

  defp with_repo(repo, fun) do
    previous = Repo.put_dynamic_repo(repo)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp sql(query, params), do: SQL.query!(Repo.get_dynamic_repo(), query, params, log: false)
end
