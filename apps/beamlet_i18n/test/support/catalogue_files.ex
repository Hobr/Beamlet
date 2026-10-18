defmodule Beamlet.I18n.CatalogueFiles do
  @moduledoc """
  Reads the shipped Gettext catalogues for ownership tests.

  Paths are resolved through `Application.app_dir/2`, so the tests read exactly
  the `priv` directory the release ships (Mix symlinks it in dev/test), not a
  copy under `test/`.
  """

  @catalogues [
    shared_default: {:beamlet_i18n, "default"},
    shared_errors: {:beamlet_i18n, "errors"},
    web_default: {:beamlet_app_web, "default"},
    web_errors: {:beamlet_app_web, "errors"},
    cli_default: {:beamlet_cli, "default"}
  ]

  @locales ["zh_CN", "en"]

  @doc "Every (behaviour, app, domain) catalogue the product ships."
  def catalogues, do: @catalogues

  @doc "Locales with a shipped `.po` file."
  def locales, do: @locales

  @doc "Absolute path of a POT file."
  def pot_path(app, domain), do: Path.join(priv(app), "#{domain}.pot")

  @doc "Absolute path of a PO file."
  def po_path(app, locale, domain),
    do: Path.join([priv(app), locale, "LC_MESSAGES", "#{domain}.po"])

  @doc """
  Parses a PO/POT file into `%{msgid => msgstr}`.

  Only single-line `msgid`/`msgstr` entries are used by these catalogues (there
  are no plurals or multi-line strings); continuation lines are skipped.
  """
  def entries(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce({%{}, nil}, fn line, {acc, current} ->
      cond do
        String.starts_with?(line, "msgid ") ->
          {acc, value(line, "msgid ")}

        String.starts_with?(line, "msgstr ") and is_binary(current) ->
          {Map.put(acc, current, value(line, "msgstr ")), current}

        true ->
          {acc, current}
      end
    end)
    |> elem(0)
  end

  @doc "Msgids of a PO/POT file, without the header entry."
  def msgids(path) do
    path
    |> entries()
    |> Map.keys()
    |> Enum.reject(&(&1 == ""))
    |> Enum.sort()
  end

  @doc """
  Repository root, found by walking up from this file until the umbrella apps
  directory is visible, so the tests do not depend on the working directory.
  """
  def source_root do
    __DIR__
    |> Path.expand()
    |> ancestors()
    |> Enum.find(fn dir -> File.dir?(Path.join([dir, "apps", "beamlet_app_web", "lib"])) end) ||
      raise "could not locate the umbrella root from #{__DIR__}"
  end

  @doc "The shared msgid declaration module (sole owner of the shared POT)."
  def source_file do
    Path.join([source_root(), "apps", "beamlet_i18n", "lib", "beamlet", "i18n", "catalogue.ex"])
  end

  @doc "All Elixir and HEEx sources of an application."
  def sources(app) do
    root = source_root()

    ~w(*.ex *.heex)
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join([root, "apps", app, "lib", "**", pattern]))
    end)
    |> Enum.sort()
  end

  defp priv(app) when is_binary(app), do: priv(String.to_existing_atom(app))
  defp priv(app) when is_atom(app), do: Application.app_dir(app, "priv/gettext")

  defp ancestors(dir) do
    parent = Path.dirname(dir)
    if parent == dir, do: [dir], else: [dir | ancestors(parent)]
  end

  defp value(line, prefix) do
    line
    |> String.trim_leading(prefix)
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
    |> String.replace(~S(\\"), ~S("))
    |> String.replace(~S(\\), ~S())
  end
end
