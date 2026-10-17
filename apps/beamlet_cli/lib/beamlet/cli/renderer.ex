defmodule Beamlet.CLI.Renderer do
  @moduledoc "Bounded terminal projection; errors never render arbitrary terms."
  alias Beamlet.CLI.Command

  @help """
  help | connect <trusted-node> | nodes | agents [authority]
  agents-page <number> (retained query; agents refreshes/replaces it)
  IDs: copy id64:<base64url UTF-8, no padding>; use explicit safe alias.
  Example: attach host@local id64:dHdvIHdvcmRz a
  create <authority> <absolute-options-file>
  attach <authority> <agent-id> [alias]
  input <alias> <text> | status <alias> | watch <alias> [timeout-ms event-limit]
  stop <alias> | close <alias> | detach <alias> | quit
  Config files are trusted executable operator-owned Elixir code, not sandboxed.
  Detach, quit, EOF and watch timeout do not close Agents or cancel upstream work.
  """
  def render(:help) do
    rows = @help |> String.split("\n", trim: true) |> Enum.map(&%{"commands / policy" => &1})
    table(rows)
  end

  def render(:ok), do: "ok"

  def render({:error, reason}) do
    safe =
      if reason in [
           :invalid_command,
           :invalid_configuration,
           :invalid_authority,
           :alias_exists,
           :alias_limit,
           :invalid_alias,
           :unknown_alias,
           :not_found,
           :not_authority,
           :stale_agent,
           :unavailable,
           :timeout,
           :limit,
           :busy,
           :event_limit,
           :timeout_or_loss,
           :invalid_watch_options
         ], do: reason, else: :request_failed

    "error: #{safe}"
  end

  def render({:ok, value}), do: render(value)

  def render(%{agents: agents, failures: failures, complete: complete} = snapshot) do
    header =
      "discovery complete=#{complete} agents=#{length(agents)} failures=#{map_size(failures)}"

    page = Map.get(snapshot, :page, 1)
    pages = max(1, div(length(agents) + 7, 8))

    identities =
      agents
      |> Enum.sort_by(&{Atom.to_string(&1.authority), &1.id, :erlang.pid_to_list(&1.pid)})
      |> Enum.slice((page - 1) * 8, 8)
      |> Enum.map(&identity/1)

    errors =
      Enum.map(failures, fn {authority, reason} ->
        %{"authority" => to_string(authority), "result" => render({:error, reason})}
      end)

    Enum.join(
      [
        header,
        "Showing #{length(identities)} identities; page=#{page}/#{pages}; agents-page N traverses retained query. Discovery is not an atomic cluster snapshot.",
        table(identities),
        table(errors)
      ],
      "\n"
    )
  end

  def render(%{identity: identity, snapshot: snapshot}),
    do: render(identity) <> "\n" <> render(snapshot)

  def render(%{authority: _, id: _, pid: _} = ref), do: table([identity(ref)])

  def render(%{status: status} = snapshot) do
    fields = Map.take(snapshot, [:steps, :turn, :terminal_turn, :final, :progress])

    rows = [
      %{"field" => "status", "value" => to_string(status)}
      | Enum.map(fields, fn {key, value} ->
          %{"field" => to_string(key), "value" => bounded(value, 2048)}
        end)
    ]

    table(rows)
  end

  def render(nodes) when is_list(nodes) do
    table(Enum.map(nodes, &%{"connected trusted node" => to_string(&1)}))
  end

  def render(value), do: bounded(value, 4096)

  # Fixed explicit width prevents terminal width detection from silently omitting
  # the authority/ID columns. Rows/cells are bounded before Owl lays them out.
  defp identity(ref),
    do: %{
      "authority" => to_string(ref.authority),
      "id" => Command.identity_token(ref.id),
      "pid" => inspect(ref.pid)
    }

  defp table([]), do: "(none)"

  defp table(rows) do
    rows
    |> Owl.Table.new(
      max_width: :infinity,
      max_column_widths: fn _ -> 512 end,
      border_style: :none,
      padding_x: 1
    )
    |> Owl.Data.to_chardata()
    |> IO.chardata_to_string()
  end

  defp bounded(value, count) do
    value
    |> inspect(limit: 40, printable_limit: 2048)
    |> Owl.Data.truncate(count)
    |> Owl.Data.to_chardata()
    |> IO.chardata_to_string()
  end
end
