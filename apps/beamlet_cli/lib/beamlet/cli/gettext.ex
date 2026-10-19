defmodule Beamlet.CLI.Gettext do
  @moduledoc """
  仅拥有终端专用文案的翻译后端。共享状态与原因通过 Beamlet.I18n 运行时查询，避免同一 msgid 被两个目录拥有。

  CLI-only translation backend.

  Only copy that the terminal surface owns lives here (help text, table
  headers, terminal notices). Shared status/reason words come from
  `Beamlet.I18n` through runtime lookups, so a msgid is never defined twice.

  Catalogues: `apps/beamlet_cli/priv/gettext/{en,zh_CN}/LC_MESSAGES`.
  """
  use Gettext.Backend, otp_app: :beamlet_cli
end
