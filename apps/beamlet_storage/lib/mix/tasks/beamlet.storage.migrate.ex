defmodule Mix.Tasks.Beamlet.Storage.Migrate do
  @shortdoc "Explicitly install/migrate durable datasets (operator action)"

  @moduledoc """
  Installs the durable authority and executor-journal datasets for the roles you
  name, exactly once. Hosts, Agents and boot never run this implicitly.

      mix beamlet.storage.migrate --storage /absolute/storage.exs --roles authority,executor

  `--storage` must name an absolute, trusted operator-owned Elixir file whose value
  is the same keyword list the host would put under `storage:`:

      [
        adapter: :sqlite,
        database: "/var/lib/beamlet/authority.db",
        dataset_id: "…",
        journal: [database: "/var/lib/beamlet/journal.db", dataset_id: "…"],
        executor_id: "…"
      ]

  Never commit that file: it holds deployment paths. The command prints only the
  role outcomes and a safe reason atom; it never echoes paths or configuration.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [storage: :string, roles: :string])

    with true <- rest == [] and invalid == [],
         path when is_binary(path) <- opts[:storage],
         true <- Path.type(path) == :absolute,
         {:ok, storage} <- read(path),
         {:ok, roles} <- roles(opts[:roles]) do
      ensure_started()

      case Beamlet.Storage.Operator.initialize(roles, storage) do
        {:ok, result} -> Mix.shell().info("installed #{inspect(result)}")
        {:error, reason} -> Mix.raise("durable installation refused: #{inspect(reason)}")
      end
    else
      _ -> Mix.raise("usage: mix beamlet.storage.migrate --storage /abs/storage.exs --roles a,e")
    end
  end

  defp read(path) do
    {storage, _binding} = Code.eval_file(path)
    if is_list(storage), do: {:ok, storage}, else: :error
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp roles(nil), do: {:ok, [:authority, :executor]}

  defp roles(value) do
    case value |> String.split(",", trim: true) do
      [] -> :error
      names -> names(Enum.map(names, &safe_role/1))
    end
  end

  defp names(roles) when is_list(roles) do
    if Enum.all?(roles, &(&1 in [:authority, :executor])) and Enum.uniq(roles) == roles,
      do: {:ok, roles},
      else: :error
  end

  defp safe_role("authority"), do: :authority
  defp safe_role("executor"), do: :executor
  defp safe_role(_), do: :unknown

  defp ensure_started do
    {:ok, _} = Application.ensure_all_started(:beamlet_storage)
    :ok
  end
end
