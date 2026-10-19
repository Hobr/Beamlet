defmodule Beamlet.I18n do
  @moduledoc """
  Web 与 CLI 的共享翻译后端，仅依赖 Gettext。界面通过运行时函数查询共享 msgid，提取宏仅由 Catalogue 声明；当前进程的 Gettext 语言同时覆盖共享与界面后端。

  Shared translation backend for the product surfaces (Web and CLI).

  Catalogues live in `apps/beamlet_i18n/priv/gettext/{en,zh_CN}/LC_MESSAGES`.

  Two different call styles are intentional and must not be mixed:

    * `Beamlet.I18n.gettext/1,2` and `Beamlet.I18n.dgettext/2,3` are plain
      **runtime** functions around `Gettext.gettext/3` and `Gettext.dgettext/4`.
      Web and CLI call these so that a shared msgid is looked up in this
      catalogue without importing a second backend macro set into the module.

    * `use Gettext, backend: Beamlet.I18n` imports the extraction macros. Only
      `Beamlet.I18n.Catalogue` uses it, because extraction (not runtime lookup)
      is what keeps the shared `.pot` complete.

  The locale is process-global (`Beamlet.I18n.Locale.put/1`), so the shared
  backend and the surface backend always resolve the same locale.
  """
  use Gettext.Backend, otp_app: :beamlet_i18n

  @doc """
  在共享默认域执行运行时查询，可传插值绑定；不向调用方目录登记提取项。

  Runtime lookup of a shared msgid in the default domain.
  """
  @spec gettext(String.t(), Gettext.bindings()) :: String.t()
  def gettext(msgid, bindings \\ %{}) do
    Gettext.gettext(__MODULE__, msgid, bindings)
  end

  @doc """
  在指定共享域执行运行时查询，可传插值绑定。

  Runtime lookup of a shared msgid in an explicit domain.
  """
  @spec dgettext(String.t(), String.t(), Gettext.bindings()) :: String.t()
  def dgettext(domain, msgid, bindings \\ %{}) do
    Gettext.dgettext(__MODULE__, domain, msgid, bindings)
  end
end
