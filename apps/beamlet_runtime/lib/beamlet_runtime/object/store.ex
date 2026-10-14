defmodule BeamletRuntime.Object.Store do
  @moduledoc """
  Local durable CAS resource, independent of Beamlet Authority Storage.

  A configured service/account is a trusted local capability. Objects are explicitly
  initialized. Replacement checks version and saves the full request-bound receipt
  in one immediate transaction. Applied and version mismatch are immutable receipts.
  Same scoped key/different input is rejected before version checking or writing.

  No deletion/reset API. Unbounded deduplication requires retained non-rolled-back
  resource history. A persistent instance rejects a same-named replacement database;
  it does not fence clones or old backups, or prove filesystem power-loss durability.
  """
  alias Beamlet.{Identity, Value}
  alias BeamletRuntime.Object.{Repo, Schema}
  alias Ecto.Adapters.SQL

  @operation "object.replace_if_version.v1"
  @max_version 9_007_199_254_740_991
  @enforce_keys [:repo, :identity, :instance, :account]
  defstruct @enforce_keys

  def start_link(opts) do
    database = Keyword.fetch!(opts, :database)

    if not is_binary(database) or database in ["", ":memory:"],
      do: raise(ArgumentError, "persistent object database required")

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
        sql(
          "INSERT OR IGNORE INTO object_service(singleton,identity,instance) VALUES(1,?,?)",
          [identity, Ecto.UUID.generate()]
        )

        service_identity!(identity)
        :ok
      end)
    else
      {:error, :invalid_object_service}
    end
  end

  def new(repo, identity, account) do
    unless Identity.valid_text?(identity) and Identity.valid_text?(account),
      do: raise(ArgumentError, "invalid object service/account")

    case transaction(
           repo,
           fn ->
             service_identity!(identity)
             [[instance]] = sql("SELECT instance FROM object_service WHERE singleton=1", []).rows
             instance
           end,
           :deferred
         ) do
      {:ok, instance} ->
        %__MODULE__{repo: repo, identity: identity, instance: instance, account: account}

      {:error, _reason} ->
        raise ArgumentError, "object service must be available and initialized"
    end
  end

  @doc "Create-or-get a logical object with immutable initial content; does not reset existing versions."
  def create_object(service, object, initial_content) do
    with :ok <- object_scope(service, object), :ok <- Value.validate(initial_content) do
      transaction(service.repo, fn -> create_object_record(service, object, initial_content) end)
    end
  end

  defp create_object_record(service, object, initial_content) do
    verify_service!(service)
    encoded = Jason.encode!(initial_content)

    sql(
      "INSERT OR IGNORE INTO resource_objects(account,object_ref,initial_content,content,version) VALUES(?,?,?,?,0)",
      [service.account, object, encoded, encoded]
    )

    [[initial]] =
      sql(
        "SELECT initial_content FROM resource_objects WHERE account=? AND object_ref=?",
        [service.account, object]
      ).rows

    if Jason.decode!(initial) !== initial_content, do: Repo.rollback(:object_definition_conflict)
    fetch_object(service, object)
  end

  def read_object(service, object) do
    with :ok <- object_scope(service, object) do
      transaction(
        service.repo,
        fn ->
          verify_service!(service)
          fetch_object(service, object)
        end,
        :deferred
      )
    end
  end

  @doc "Local Operation input validation; versions fit the restricted value integer range."
  def validate_request(request) do
    valid =
      is_map(request) and not is_struct(request) and
        Enum.sort(Map.keys(request)) == [
          "account",
          "content",
          "expected_version",
          "object",
          "service"
        ] and
        Enum.all?(["account", "object", "service"], &Identity.valid_text?(request[&1])) and
        is_integer(request["expected_version"]) and request["expected_version"] in 0..@max_version

    if valid, do: Value.validate(request), else: {:error, :invalid_object_request}
  end

  def replace(service, collection, intent_id, request) do
    with :ok <- request_scope(service, collection, intent_id, request) do
      transaction(service.repo, fn -> apply_request(service, collection, intent_id, request) end)
    end
  end

  defp apply_request(service, collection, intent_id, request) do
    verify_service!(service)

    case receipt(service, collection, intent_id, request) do
      nil -> replace_and_receipt(service, collection, intent_id, request)
      saved -> saved
    end
  end

  def read_receipt(service, collection, intent_id, request) do
    with :ok <- request_scope(service, collection, intent_id, request) do
      transaction(
        service.repo,
        fn ->
          verify_service!(service)

          receipt(service, collection, intent_id, request) ||
            Repo.rollback(:object_receipt_not_found)
        end,
        :deferred
      )
    end
  end

  defp replace_and_receipt(service, collection, intent_id, request) do
    current = fetch_object(service, request["object"])
    applied = current["version"] == request["expected_version"]
    version = if applied, do: next_version!(current["version"]), else: current["version"]

    if applied do
      result =
        sql(
          "UPDATE resource_objects SET content=?,version=? WHERE account=? AND object_ref=? AND version=?",
          [
            Jason.encode!(request["content"]),
            version,
            service.account,
            request["object"],
            request["expected_version"]
          ]
        )

      if result.num_rows != 1, do: Repo.rollback(:object_version_changed)
    end

    sql(
      "INSERT INTO object_receipts(account,object_ref,operation,collection,intent_id,request,applied,version,receipt_ref) VALUES(?,?,?,?,?,?,?,?,?)",
      [
        service.account,
        request["object"],
        @operation,
        collection,
        intent_id,
        Jason.encode!(request),
        if(applied, do: 1, else: 0),
        version,
        Ecto.UUID.generate()
      ]
    )

    receipt(service, collection, intent_id, request)
  end

  defp next_version!(@max_version), do: Repo.rollback(:object_version_exhausted)
  defp next_version!(version), do: version + 1

  defp receipt(service, collection, intent_id, request) do
    case sql(
           "SELECT request,applied,version,receipt_ref FROM object_receipts WHERE account=? AND object_ref=? AND operation=? AND collection=? AND intent_id=?",
           [service.account, request["object"], @operation, collection, intent_id]
         ).rows do
      [] ->
        nil

      [[encoded, applied, version, ref]] ->
        saved = Jason.decode!(encoded)
        if saved !== request, do: Repo.rollback(:object_request_conflict)

        body = %{
          "applied" => applied == 1,
          "object_ref" => request["object"],
          "version" => version,
          "receipt_ref" => ref
        }

        body = if applied == 1, do: body, else: Map.put(body, "reason", "version_mismatch")
        %{request: saved, body: body}
    end
  end

  defp fetch_object(service, object) do
    case sql(
           "SELECT version,content FROM resource_objects WHERE account=? AND object_ref=?",
           [service.account, object]
         ).rows do
      [[version, content]] -> %{"version" => version, "content" => Jason.decode!(content)}
      [] -> Repo.rollback(:object_not_found)
    end
  end

  defp request_scope(service, collection, intent_id, request) do
    with :ok <- validate_request(request),
         :ok <- object_scope(service, request["object"]),
         true <- Identity.valid_text?(collection) and Identity.valid_text?(intent_id),
         true <- request["service"] == service.identity and request["account"] == service.account do
      :ok
    else
      false -> {:error, :object_scope_mismatch}
      error -> error
    end
  end

  defp object_scope(%__MODULE__{} = service, object) do
    if Enum.all?(
         [service.identity, service.instance, service.account, object],
         &Identity.valid_text?/1
       ), do: :ok, else: {:error, :invalid_object_scope}
  end

  defp service_identity!(identity) do
    case sql("SELECT identity FROM object_service WHERE singleton=1", []).rows do
      [[^identity]] -> :ok
      _other -> Repo.rollback(:object_service_mismatch)
    end
  end

  defp verify_service!(service) do
    case sql("SELECT identity,instance FROM object_service WHERE singleton=1", []).rows do
      [[identity, instance]] when identity == service.identity and instance == service.instance ->
        :ok

      _other ->
        Repo.rollback(:object_service_mismatch)
    end
  end

  defp transaction(repo, fun, mode \\ :immediate) do
    with_repo(repo, fn -> Repo.transaction(fun, mode: mode, log: false) end)
  rescue
    _error in [Exqlite.Error, DBConnection.ConnectionError] ->
      {:error, :object_commit_indeterminate}

    error in [RuntimeError, ArgumentError] ->
      if repo_lookup_failure?(__STACKTRACE__),
        do: {:error, :object_store_unavailable},
        else: reraise(error, __STACKTRACE__)
  catch
    :exit, _reason -> {:error, :object_commit_indeterminate}
  end

  defp repo_lookup_failure?(trace) do
    Enum.any?(trace, fn
      {Ecto.Repo.Registry, :lookup, _, _} -> true
      _frame -> false
    end)
  end

  defp with_repo(repo, fun) do
    previous = Repo.put_dynamic_repo(repo)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp sql(statement, params),
    do: SQL.query!(Repo.get_dynamic_repo(), statement, params, log: false)
end
