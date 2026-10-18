defmodule Beamlet.I18n.CatalogueTest do
  @moduledoc """
  Ownership rules for the three catalogues.

  Shared copy lives only in `beamlet_i18n`; Web and CLI only own copy no other
  surface uses. These tests fail if a msgid is duplicated across catalogues, if
  an extracted msgid has no Chinese translation, or if a runtime shared lookup
  names a msgid the shared catalogue does not contain.
  """
  use ExUnit.Case
  alias Beamlet.I18n.Catalogue
  alias Beamlet.I18n.CatalogueFiles

  @shared_gettext ~r/Beamlet\.I18n\.gettext\("((?:[^"\\]|\\.)*)"/u
  @shared_dgettext ~r/Beamlet\.I18n\.dgettext\("([a-z_]+)",\s*"((?:[^"\\]|\\.)*)"/u
  # The shared declaration module imports the backend, so its macro calls are bare.
  @declared_gettext ~r/(?<![\w.])gettext\("((?:[^"\\]|\\.)*)"/u
  @declared_dgettext ~r/(?<![\w.])dgettext\("([a-z_]+)",\s*"((?:[^"\\]|\\.)*)"/u

  test "every extracted msgid has a non-empty Chinese translation in its owning catalogue" do
    for {name, {app, domain}} <- CatalogueFiles.catalogues() do
      pot = CatalogueFiles.msgids(CatalogueFiles.pot_path(app, domain))
      chinese = CatalogueFiles.entries(CatalogueFiles.po_path(app, "zh_CN", domain))

      assert Enum.sort(Map.keys(chinese) |> Enum.reject(&(&1 == ""))) == pot,
             "#{name}: zh_CN catalogue does not match the POT exactly"

      for msgid <- pot do
        assert Map.fetch!(chinese, msgid) != "",
               "#{name}: #{inspect(msgid)} has no zh_CN translation"
      end
    end
  end

  test "the English catalogue covers every extracted msgid" do
    for {name, {app, domain}} <- CatalogueFiles.catalogues() do
      pot = CatalogueFiles.msgids(CatalogueFiles.pot_path(app, domain))
      english = CatalogueFiles.entries(CatalogueFiles.po_path(app, "en", domain))

      assert Enum.sort(Map.keys(english) |> Enum.reject(&(&1 == ""))) == pot,
             "#{name}: en catalogue does not match the POT exactly"
    end
  end

  test "no extracted msgid is duplicated across catalogues" do
    sets =
      for {name, {app, domain}} <- CatalogueFiles.catalogues() do
        {name, MapSet.new(CatalogueFiles.msgids(CatalogueFiles.pot_path(app, domain)))}
      end

    for {first, one} <- sets, {second, two} <- sets, first < second do
      overlap = MapSet.intersection(one, two)

      assert MapSet.size(overlap) == 0,
             "#{first} and #{second} both own: #{inspect(Enum.sort(overlap))}"
    end
  end

  test "Web and CLI shared lookups all exist in the shared catalogue" do
    shared = %{
      "default" => MapSet.new(CatalogueFiles.msgids(pot("beamlet_i18n", "default"))),
      "errors" => MapSet.new(CatalogueFiles.msgids(pot("beamlet_i18n", "errors")))
    }

    lookups =
      for app <- ["beamlet_app_web", "beamlet_cli"],
          source <- CatalogueFiles.sources(app),
          {:gettext, msgid} <- scan(source),
          do: {app, Path.basename(source), "default", msgid}

    error_lookups =
      for app <- ["beamlet_app_web", "beamlet_cli"],
          source <- CatalogueFiles.sources(app),
          {:dgettext, domain, msgid} <- scan(source),
          do: {app, Path.basename(source), domain, msgid}

    all = lookups ++ error_lookups

    refute error_lookups == [],
           "the shared error-lookup scan found no literals; the pattern is stale"

    # Shared default-domain words are currently resolved through
    # Beamlet.I18n.Vocabulary with a runtime value, so no caller contains a
    # `Beamlet.I18n.gettext("...")` literal yet. Scan the declaration module
    # instead, so the gettext half of the guard is live and a mistyped literal
    # cannot silently escape the shared catalogue.
    declarations =
      for {kind, domain, msgid} <- scan_declarations(CatalogueFiles.source_file()) do
        assert MapSet.member?(shared[domain], msgid),
               "Beamlet.I18n.Catalogue declares #{inspect(msgid)} in domain #{inspect(domain)}," <>
                 " which is not in the shared catalogue"

        {kind, msgid}
      end

    assert Enum.any?(declarations, fn {kind, _} -> kind == :gettext end),
           "no shared gettext declaration was found in Beamlet.I18n.Catalogue"

    for {app, file, domain, msgid} <- all do
      assert Map.has_key?(shared, domain),
             "#{app}/#{file} uses shared domain #{inspect(domain)}, which does not exist"

      assert MapSet.member?(shared[domain], msgid),
             "#{app}/#{file} uses #{inspect(msgid)} in domain #{inspect(domain)}," <>
               " which is not in the shared catalogue"
    end
  end

  test "shared vocabulary is declared once in the shared catalogue" do
    shared_default = MapSet.new(CatalogueFiles.msgids(pot("beamlet_i18n", "default")))
    shared_errors = MapSet.new(CatalogueFiles.msgids(pot("beamlet_i18n", "errors")))

    for status <- Catalogue.statuses() do
      assert MapSet.member?(shared_default, status),
             "status #{inspect(status)} is translated but missing from the shared default catalogue"
    end

    for reason <- Catalogue.reasons() do
      assert MapSet.member?(shared_errors, reason),
             "reason #{inspect(reason)} is translated but missing from the shared errors catalogue"
    end
  end

  defp pot(app, domain), do: CatalogueFiles.pot_path(app, domain)

  defp scan(path) do
    contents = File.read!(path)

    gettexts =
      for [_, msgid] <- Regex.scan(@shared_gettext, contents), do: {:gettext, unescape(msgid)}

    dgettexts =
      for [_, domain, msgid] <- Regex.scan(@shared_dgettext, contents),
          do: {:dgettext, domain, unescape(msgid)}

    gettexts ++ dgettexts
  end

  defp scan_declarations(path) do
    contents = File.read!(path)

    gettexts =
      for [_, msgid] <- Regex.scan(@declared_gettext, contents),
          do: {:gettext, "default", unescape(msgid)}

    dgettexts =
      for [_, domain, msgid] <- Regex.scan(@declared_dgettext, contents),
          do: {:dgettext, domain, unescape(msgid)}

    gettexts ++ dgettexts
  end

  defp unescape(value), do: String.replace(value, ~S(\"), ~S("))
end
