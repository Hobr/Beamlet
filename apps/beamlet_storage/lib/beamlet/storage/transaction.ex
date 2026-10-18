defmodule Beamlet.Storage.Transaction do
  @moduledoc """
  Internal storage transaction boundary. Writes take SQLite's immediate lock;
  ordinary Repo reads remain deferred. No retries or external effects are added.
  A driver failure during a write is conservatively outcome-unknown: reconcile
  using stable identities before attempting any external work.
  """
  @deterministic_violations [
    :check_violation,
    :not_null_violation,
    :foreign_key_violation,
    :restrict_violation,
    :exclusion_violation,
    :datatype_mismatch,
    :invalid_text_representation,
    :string_data_right_truncation,
    :numeric_value_out_of_range
  ]

  def write(repo, multi_or_fun) do
    opts = [timeout: 5000, log: false]

    opts =
      if repo.__adapter__() == Ecto.Adapters.SQLite3,
        do: Keyword.put(opts, :mode, :immediate),
        else: opts

    try do
      repo.transaction(multi_or_fun, opts)
    rescue
      error in RuntimeError -> unavailable_repo(error, :storage_outcome_unknown, __STACKTRACE__)
      _ in [DBConnection.ConnectionError] -> {:error, :storage_outcome_unknown}
      error in [Exqlite.Error] -> {:error, classify_sqlite(error)}
      error in [Postgrex.Error] -> {:error, classify_postgres(error)}
    catch
      :exit, _ -> {:error, :storage_outcome_unknown}
    end
  end

  # A rejected statement aborts and rolls back the whole transaction, so the write
  # set is provably absent. Connection loss and unclassified driver errors stay
  # outcome-unknown: the client cannot prove the commit did not happen.
  defp classify_sqlite(%Exqlite.Error{message: message}) when is_binary(message) do
    cond do
      String.contains?(message, "UNIQUE constraint") ->
        :conflict

      String.contains?(message, [
        "CHECK constraint",
        "NOT NULL constraint",
        "FOREIGN KEY",
        "datatype mismatch"
      ]) ->
        :invalid_data

      true ->
        :storage_outcome_unknown
    end
  end

  defp classify_sqlite(_), do: :storage_outcome_unknown

  defp classify_postgres(%Postgrex.Error{postgres: %{code: code}}) do
    cond do
      code == :unique_violation -> :conflict
      code in @deterministic_violations -> :invalid_data
      true -> :storage_outcome_unknown
    end
  end

  defp classify_postgres(_), do: :storage_outcome_unknown

  def read(fun) do
    fun.()
  rescue
    error in RuntimeError ->
      unavailable_repo(error, :storage_unavailable, __STACKTRACE__)

    error in ArgumentError ->
      invalid_json_load(error, __STACKTRACE__)

    _ in [DBConnection.ConnectionError, Exqlite.Error, Postgrex.Error] ->
      {:error, :storage_unavailable}
  catch
    :exit, _ -> {:error, :storage_unavailable}
  end

  # Ecto raises when our strict JSON type refuses corrupted stored bytes. Do not
  # leak the raw field in that exception, or hide unrelated argument/programming errors.
  defp invalid_json_load(error, [{Ecto.Repo.Queryable, :struct_load!, _, _} | _] = stacktrace) do
    if String.starts_with?(error.message, "cannot load ") and
         String.contains?(error.message, " as type #Beamlet.Storage.JSON<"),
       do: {:error, :invalid_data},
       else: reraise(error, stacktrace)
  end

  defp invalid_json_load(error, stacktrace), do: reraise(error, stacktrace)

  defp unavailable_repo(error, reason, stacktrace) do
    if String.starts_with?(error.message, "could not lookup Ecto repo "),
      do: {:error, reason},
      else: reraise(error, stacktrace)
  end
end
