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
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc "Shared error/outcome words, in catalogue order."
  @spec reasons() :: [String.t()]
  def reasons, do: @reasons

  @doc "Declares the shared msgids for extraction. Never called at runtime."
  @spec declare() :: :ok
  def declare do
    _ = shared_statuses()
    shared_reasons()
  end

  @spec shared_statuses() :: :ok
  defp shared_statuses do
    # Extraction registers msgids at compile time; rendered strings are unused.
    _ = gettext("idle")
    _ = gettext("running")
    _ = gettext("waiting")
    _ = gettext("done")
    _ = gettext("stopped")
    _ = gettext("error")
    _ = gettext("starting")
    _ = gettext("completed")
    _ = gettext("pending")
    _ = gettext("admitting")
    _ = gettext("unknown")
    _ = gettext("complete")
    _ = gettext("partial")
    _ = gettext("ready")
    _ = gettext("active")
    _ = gettext("connected")
    _ = gettext("disconnected")
    _ = gettext("enabled")
    _ = gettext("disabled")
    _ = gettext("local")
    :ok
  end

  @spec shared_reasons() :: :ok
  defp shared_reasons do
    # Preserve literal macro calls so Gettext can extract each shared reason.
    _ = dgettext("errors", "invalid_command")
    _ = dgettext("errors", "invalid_configuration")
    _ = dgettext("errors", "invalid_authority")
    _ = dgettext("errors", "alias_exists")
    _ = dgettext("errors", "alias_limit")
    _ = dgettext("errors", "invalid_alias")
    _ = dgettext("errors", "unknown_alias")
    _ = dgettext("errors", "not_found")
    _ = dgettext("errors", "not_authority")
    _ = dgettext("errors", "stale_agent")
    _ = dgettext("errors", "unavailable")
    _ = dgettext("errors", "timeout")
    _ = dgettext("errors", "limit")
    _ = dgettext("errors", "busy")
    _ = dgettext("errors", "event_limit")
    _ = dgettext("errors", "timeout_or_loss")
    _ = dgettext("errors", "invalid_watch_options")
    _ = dgettext("errors", "request_failed")
    _ = dgettext("errors", "deadline")
    _ = dgettext("errors", "invalid_draft")
    _ = dgettext("errors", "configuration_unavailable")
    _ = dgettext("errors", "create_unknown")
    :ok
  end
end
