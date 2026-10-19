defmodule Beamlet.Web.Gettext do
  @moduledoc """
  Web 专用文案的 Gettext 后端，共享词汇由 Beamlet.I18n 拥有。每个模块只导入一个后端宏集合，避免提取重复所有权。

  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://gettext.hexdocs.pm), your module compiles translations
  that you can use in your application. To use this Gettext backend module,
  call `use Gettext` and pass it as an option:

      use Gettext, backend: Beamlet.Web.Gettext

      # Simple translation
      gettext("Here is the string to translate")

      # Plural translation
      ngettext("Here is the string to translate",
               "Here are the strings to translate",
               3)

      # Domain-based translation
      dgettext("errors", "Here is the error message to translate")

  See the [Gettext Docs](https://gettext.hexdocs.pm) for detailed usage.
  """
  use Gettext.Backend, otp_app: :beamlet_app_web
end
