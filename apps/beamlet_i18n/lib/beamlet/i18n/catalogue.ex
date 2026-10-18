defmodule Beamlet.I18n.Catalogue do
  @moduledoc """
  Single owner of the shared msgids.

  Web and CLI never register this backend for extraction (they only call the
  runtime functions in `Beamlet.I18n`), so nothing else can prune a shared
  entry. This module therefore has to *declare* every shared msgid exactly once
  through the extraction macros. `mix gettext.extract --merge` from the
  repository root turns these declarations into
  `apps/beamlet_i18n/priv/gettext/*/LC_MESSAGES/*.po`.

  `declare/0` is never executed at runtime. The lists below are the closed
  vocabulary that `Beamlet.I18n.Vocabulary` translates: a word outside them is
  never handed to Gettext, so an internal atom can never become a msgid.
  """
  use Gettext, backend: Beamlet.I18n

  # Shared status/state vocabulary (default domain).
  @statuses ~w(
    idle running waiting done stopped error starting completed pending admitting
    unknown complete partial ready active connected disconnected enabled disabled
    local
  )

  # Shared error/outcome vocabulary (errors domain).
  @reasons ~w(
    invalid_command invalid_configuration invalid_authority alias_exists alias_limit
    invalid_alias unknown_alias not_found not_authority stale_agent unavailable
    timeout limit busy event_limit timeout_or_loss invalid_watch_options
    request_failed deadline invalid_draft configuration_unavailable create_unknown
  )

  @doc "Shared status/state words, in catalogue order."
  def statuses, do: @statuses

  @doc "Shared error/outcome words, in catalogue order."
  def reasons, do: @reasons

  @doc "Declares the shared msgids for extraction. Never called at runtime."
  def declare do
    _ = shared_statuses()
    shared_reasons()
  end

  defp shared_statuses do
    gettext("idle")
    gettext("running")
    gettext("waiting")
    gettext("done")
    gettext("stopped")
    gettext("error")
    gettext("starting")
    gettext("completed")
    gettext("pending")
    gettext("admitting")
    gettext("unknown")
    gettext("complete")
    gettext("partial")
    gettext("ready")
    gettext("active")
    gettext("connected")
    gettext("disconnected")
    gettext("enabled")
    gettext("disabled")
    gettext("local")
    :ok
  end

  defp shared_reasons do
    dgettext("errors", "invalid_command")
    dgettext("errors", "invalid_configuration")
    dgettext("errors", "invalid_authority")
    dgettext("errors", "alias_exists")
    dgettext("errors", "alias_limit")
    dgettext("errors", "invalid_alias")
    dgettext("errors", "unknown_alias")
    dgettext("errors", "not_found")
    dgettext("errors", "not_authority")
    dgettext("errors", "stale_agent")
    dgettext("errors", "unavailable")
    dgettext("errors", "timeout")
    dgettext("errors", "limit")
    dgettext("errors", "busy")
    dgettext("errors", "event_limit")
    dgettext("errors", "timeout_or_loss")
    dgettext("errors", "invalid_watch_options")
    dgettext("errors", "request_failed")
    dgettext("errors", "deadline")
    dgettext("errors", "invalid_draft")
    dgettext("errors", "configuration_unavailable")
    dgettext("errors", "create_unknown")
    :ok
  end
end
