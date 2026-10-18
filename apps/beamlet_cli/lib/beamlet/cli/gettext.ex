defmodule Beamlet.CLI.Gettext do
  @moduledoc """
  CLI-only translation backend.

  Only copy that the terminal surface owns lives here (help text, table
  headers, terminal notices). Shared status/reason words come from
  `Beamlet.I18n` through runtime lookups, so a msgid is never defined twice.

  Catalogues: `apps/beamlet_cli/priv/gettext/{en,zh_CN}/LC_MESSAGES`.
  """
  use Gettext.Backend, otp_app: :beamlet_cli
end
