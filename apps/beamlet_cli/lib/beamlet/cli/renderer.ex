defmodule Beamlet.CLI.Renderer do
  @moduledoc "Bounded terminal projection; errors never render arbitrary terms."
  alias Beamlet.CLI.Command
  alias Beamlet.I18n.Vocabulary

  use Gettext, backend: Beamlet.CLI.Gettext

  # Shared error vocabulary. These literals are runtime lookups into
  # `Beamlet.I18n`; the table itself is the allowlist, so an unexpected term can
  # never become copy or leak into the terminal.
  @spec safe_reason(term()) :: binary()
  defp safe_reason(:invalid_command), do: Beamlet.I18n.dgettext("errors", "invalid_command")

  defp safe_reason(:invalid_configuration),
    do: Beamlet.I18n.dgettext("errors", "invalid_configuration")

  defp safe_reason(:invalid_authority), do: Beamlet.I18n.dgettext("errors", "invalid_authority")
  defp safe_reason(:alias_exists), do: Beamlet.I18n.dgettext("errors", "alias_exists")
  defp safe_reason(:alias_limit), do: Beamlet.I18n.dgettext("errors", "alias_limit")
  defp safe_reason(:invalid_alias), do: Beamlet.I18n.dgettext("errors", "invalid_alias")
  defp safe_reason(:unknown_alias), do: Beamlet.I18n.dgettext("errors", "unknown_alias")
  defp safe_reason(:not_found), do: Beamlet.I18n.dgettext("errors", "not_found")
  defp safe_reason(:not_authority), do: Beamlet.I18n.dgettext("errors", "not_authority")
  defp safe_reason(:stale_agent), do: Beamlet.I18n.dgettext("errors", "stale_agent")
  defp safe_reason(:unavailable), do: Beamlet.I18n.dgettext("errors", "unavailable")
  defp safe_reason(:timeout), do: Beamlet.I18n.dgettext("errors", "timeout")
  defp safe_reason(:limit), do: Beamlet.I18n.dgettext("errors", "limit")
  defp safe_reason(:busy), do: Beamlet.I18n.dgettext("errors", "busy")
  defp safe_reason(:event_limit), do: Beamlet.I18n.dgettext("errors", "event_limit")
  defp safe_reason(:timeout_or_loss), do: Beamlet.I18n.dgettext("errors", "timeout_or_loss")

  defp safe_reason(:invalid_watch_options),
    do: Beamlet.I18n.dgettext("errors", "invalid_watch_options")

  defp safe_reason(_), do: Beamlet.I18n.dgettext("errors", "request_failed")

  # Help body. Command grammar, keywords and example tokens stay untranslated;
  # only the prose lines have a different translation.
  @spec help_lines() :: [binary()]
  defp help_lines do
    [
      gettext("help | connect <trusted-node> | nodes | agents [authority]"),
      gettext("agents-page <number> (retained query; agents refreshes/replaces it)"),
      gettext("IDs: copy id64:<base64url UTF-8, no padding>; use explicit safe alias."),
      gettext("Example: attach host@local id64:dHdvIHdvcmRz a"),
      gettext("create <authority> <absolute-options-file>"),
      gettext("attach <authority> <agent-id> [alias]"),
      gettext("input <alias> <text> | status <alias> | watch <alias> [timeout-ms event-limit]"),
      gettext("stop <alias> | close <alias> | detach <alias> | quit"),
      gettext("Config files are trusted executable operator-owned Elixir code, not sandboxed."),
      gettext("Detach, quit, EOF and watch timeout do not close Agents or cancel upstream work.")
    ]
  end

  # Unknown values intentionally use the bounded inspect fallback.
  @spec render(term()) :: binary()
  def render(:help) do
    header = gettext("commands / policy")
    rows = help_lines() |> Enum.map(&%{header => &1})
    table(rows)
  end

  def render(:ok), do: gettext("ok")

  def render({:error, reason}),
    do: gettext("error: %{reason}", reason: safe_reason(reason))

  def render({:ok, value}), do: render(value)

  def render(%{agents: agents, failures: failures, complete: complete} = snapshot) do
    header =
      gettext("discovery complete=%{complete} agents=%{agents} failures=%{failures}",
        complete: complete,
        agents: length(agents),
        failures: map_size(failures)
      )

    page = Map.get(snapshot, :page, 1)
    pages = max(1, div(length(agents) + 7, 8))

    identities =
      agents
      |> Enum.sort_by(&{Atom.to_string(&1.authority), &1.id, :erlang.pid_to_list(&1.pid)})
      |> Enum.slice((page - 1) * 8, 8)
      |> Enum.map(&identity/1)

    errors =
      Enum.map(failures, fn {authority, reason} ->
        %{
          gettext("authority") => to_string(authority),
          gettext("result") => render({:error, reason})
        }
      end)

    Enum.join(
      [
        header,
        gettext(
          "Showing %{shown} identities; page=%{page}/%{pages}; agents-page N traverses retained query. Discovery is not an atomic cluster snapshot.",
          shown: length(identities),
          page: page,
          pages: pages
        ),
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
      %{gettext("field") => "status", gettext("value") => Vocabulary.status(status)}
      | Enum.map(fields, fn {key, value} ->
          %{gettext("field") => to_string(key), gettext("value") => bounded(value, 2048)}
        end)
    ]

    table(rows)
  end

  def render(nodes) when is_list(nodes) do
    header = gettext("connected trusted node")
    table(Enum.map(nodes, &%{header => to_string(&1)}))
  end

  def render(value), do: bounded(value, 4096)

  # Fixed explicit width prevents terminal width detection from silently omitting
  # the authority/ID columns. Rows/cells are bounded before Owl lays them out.
  @spec identity(%{
          required(:authority) => node(),
          required(:id) => binary(),
          required(:pid) => pid(),
          optional(atom()) => term()
        }) :: %{binary() => binary()}
  defp identity(ref),
    do: %{
      gettext("authority") => to_string(ref.authority),
      gettext("id") => Command.identity_token(ref.id),
      gettext("pid") => inspect(ref.pid)
    }

  @spec table([%{binary() => binary()}]) :: binary()
  defp table([]), do: gettext("(none)")

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

  @spec bounded(term(), pos_integer()) :: binary()
  defp bounded(value, count) do
    value
    |> inspect(limit: 40, printable_limit: 2048)
    |> Owl.Data.truncate(count)
    |> Owl.Data.to_chardata()
    |> IO.chardata_to_string()
  end
end
