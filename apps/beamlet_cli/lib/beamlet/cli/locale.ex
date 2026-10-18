defmodule Beamlet.CLI.Locale do
  @moduledoc """
  CLI locale resolution.

  Canonicalisation and the default live in `Beamlet.I18n.Locale`; this module
  only resolves *where* the CLI value comes from:

    1. `config :beamlet_cli, :locale` — trusted operator configuration, which
       wins over everything else;
    2. the `BEAMLET_LANG` environment variable, so an operator can override the
       shipped default without editing (possibly baked-in) configuration;
    3. `config :beamlet_cli, :default_locale` — the shipped default;
    4. the shared default `zh_CN`.

  `:default_locale` deliberately ranks *below* `BEAMLET_LANG`: it is the value
  the release ships with, so letting it outrank the environment would make the
  documented environment override unreachable. An unusable value at any step is
  skipped, so a typo never hides the next choice and never disables
  translation.
  """
  alias Beamlet.I18n.Locale, as: Shared

  @env "BEAMLET_LANG"

  @doc "Canonical locales in display order."
  def options, do: Shared.options()

  @doc "Canonicalises a locale, or `nil` when unknown."
  def normalize(locale), do: Shared.normalize(locale)

  @doc "Configured/environment locale, falling back to the shared default."
  def locale do
    Shared.normalize(config_value(:locale)) ||
      Shared.normalize(System.get_env(@env)) ||
      Shared.normalize(config_value(:default_locale)) ||
      Shared.default()
  end

  @doc """
  Sets the locale for the current CLI process.

  The runner calls this once before reading stdin, so every later render in the
  same process (including `Session` and `Renderer` calls) uses one language.
  Returns the canonical locale.
  """
  def put(locale \\ nil), do: Shared.put(locale || locale())

  defp config_value(key), do: Application.get_env(:beamlet_cli, key)
end
