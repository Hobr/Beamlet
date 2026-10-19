defmodule Beamlet.I18n.Locale do
  @moduledoc """
  The single locale canonicalisation used by every product surface.

  Canonical locales are `"zh_CN"` (default) and `"en"`. Web and CLI may accept
  additional input spellings, but they must not reimplement the mapping: both
  delegate to `normalize/1` and `default/0` here so the two surfaces cannot
  drift. `put/1` sets the **process-global** Gettext locale, which covers both
  the surface backend and `Beamlet.I18n` in that process.
  """

  @default "zh_CN"
  @locales ["zh_CN", "en"]
  @options [{"zh_CN", "中文"}, {"en", "English"}]

  @doc "Default canonical locale."
  @typedoc "Canonical locale string (zh_CN or en); typespecs cannot enumerate string literals."
  @type t :: String.t()
  @spec default() :: t()
  def default, do: @default

  @doc "Canonical locales in display order."
  @spec locales() :: [t()]
  def locales, do: @locales

  @doc """
  Canonical locale and display label pairs for a language switcher.

  Labels are intentionally not translated: each label is shown in its own
  language.
  """
  @spec options() :: [{t(), String.t()}]
  def options, do: @options

  @doc """
  Canonicalises a locale string, or returns `nil` when it is unknown.

  Accepted spellings: `zh`, `zh-cn`, `zh_CN`, `cn` -> `"zh_CN"`;
  `en`, `en-us`, `en_US` -> `"en"`. Anything else (including `nil` and
  non-binaries) is `nil`, so callers can fall back safely.
  """
  @spec normalize(term()) :: t() | nil
  def normalize(nil), do: nil

  def normalize(locale) when is_binary(locale) do
    locale |> String.trim() |> String.downcase() |> aliases()
  end

  def normalize(_), do: nil

  @doc "Canonicalises a locale, falling back to `default/0`."
  @spec canonicalize(term()) :: t()
  def canonicalize(locale), do: normalize(locale) || default()

  @doc """
  Sets the locale for the current process.

  Uses the process-global Gettext locale so `Beamlet.I18n` (shared copy) and the
  surface backend (`Beamlet.Web.Gettext` / `Beamlet.CLI.Gettext`) resolve the
  same language. The value is canonicalised first, so an unknown locale never
  leaks into rendering.
  """
  @spec put(term()) :: t()
  def put(locale) do
    canonical = canonicalize(locale)
    _ = Gettext.put_locale(canonical)
    canonical
  end

  @doc "Value for an HTML `lang` attribute."
  @spec html_lang(term()) :: String.t()
  def html_lang("zh_CN"), do: "zh-CN"
  def html_lang("en"), do: "en"
  def html_lang(_), do: html_lang(@default)

  @spec aliases(binary()) :: t() | nil
  defp aliases("zh"), do: "zh_CN"
  defp aliases("zh_cn"), do: "zh_CN"
  defp aliases("zh-cn"), do: "zh_CN"
  defp aliases("cn"), do: "zh_CN"
  defp aliases("en"), do: "en"
  defp aliases("en-us"), do: "en"
  defp aliases("en_us"), do: "en"
  defp aliases(_), do: nil
end
