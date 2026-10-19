defmodule Beamlet.CLI.Locale do
  @moduledoc """
  终端语言来源按有效值依次选择：locale 配置、BEAMLET_LANG、default_locale 配置、共享默认 zh_CN。规范化委托给共享模块；Runner 在读取前为当前进程安装一次语言。

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

  @doc """
  返回用于语言选择的规范值与自有语言标签。

  Canonical locales in display order.
  """
  @spec options() :: [{binary(), binary()}]
  def options, do: Shared.options()

  @doc """
  将支持的语言别名规范化，未知或非字符串返回 nil。

  Canonicalises a locale, or `nil` when unknown.
  """
  @spec normalize(term()) :: binary() | nil
  def normalize(locale), do: Shared.normalize(locale)

  @doc """
  依次跳过无效配置与环境值，返回可用的 CLI 语言；默认 zh_CN。

  Configured/environment locale, falling back to the shared default.
  """
  @spec locale() :: binary()
  def locale do
    Shared.normalize(config_value(:locale)) ||
      Shared.normalize(System.get_env(@env)) ||
      Shared.normalize(config_value(:default_locale)) ||
      Shared.default()
  end

  @doc """
  为当前进程安装规范化语言并返回该值；影响共享及界面后端，不改变 Agent 行为。

  Sets the locale for the current CLI process.

  The runner calls this once before reading stdin, so every later render in the
  same process (including `Session` and `Renderer` calls) uses one language.
  Returns the canonical locale.
  """
  @spec put(term()) :: binary()
  def put(locale \\ nil), do: Shared.put(locale || locale())

  @spec config_value(:locale | :default_locale) :: term()
  defp config_value(key), do: Application.get_env(:beamlet_cli, key)
end
