defmodule Beamlet.Web.Locale do
  @moduledoc """
  Web-surface locale resolution and switching.

  Canonicalisation is owned by `Beamlet.I18n.Locale`; this module only decides
  *where* the requested value comes from and installs it for the current
  process.

  Resolution order (one implementation for plugs and LiveViews):

    1. a valid `?locale=` query value, canonicalised;
    2. the session `"locale"` value, canonicalised;
    3. `config :beamlet_app_web, :default_locale`, else the shared default `zh_CN`.

  Because the plug writes a valid `?locale=` back into the session, the value
  survives later requests without any client-side storage; an invalid or
  unknown value is never persisted and falls through to the next source.
  """
  @behaviour Plug

  import Phoenix.Component, only: [assign: 2]

  alias Beamlet.I18n.Locale, as: Shared

  @param "locale"
  @session_key "locale"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = Plug.Conn.fetch_query_params(conn)
    conn = persist_param(conn, conn.query_params[@param])
    locale = resolve(Plug.Conn.get_session(conn, @session_key))
    Shared.put(locale)

    conn
    |> Plug.Conn.assign(:locale, locale)
    |> Plug.Conn.assign(:locale_options, options(conn.request_path, locale))
  end

  @doc "Resolves a locale from a session value and an optional request value."
  def resolve(session_locale, param_locale \\ nil) do
    Shared.normalize(param_locale) || Shared.normalize(session_locale) || default()
  end

  @doc "Configured Web default locale, falling back to the shared default."
  def default do
    Shared.normalize(Application.get_env(:beamlet_app_web, :default_locale)) || Shared.default()
  end

  @doc "Value for the root layout `lang` attribute."
  def html_lang(locale), do: Shared.html_lang(Shared.normalize(locale))

  @doc """
  Switcher entries for a path: `%{code, label, path, current}`.

  `path` keeps the current path and only replaces the `locale` query value, so
  switching never drops the page being viewed. Labels stay in their own
  language by design.
  """
  def options(path, locale) do
    for {code, label} <- Shared.options() do
      %{code: code, label: label, path: path_for(path, code), current: code == locale}
    end
  end

  @doc "Merges a canonical locale into an existing path/query."
  def path_for(path, locale) when is_binary(path) and is_binary(locale) do
    uri = URI.parse(path)

    query =
      case uri.query do
        nil -> %{}
        existing -> URI.decode_query(existing)
      end

    URI.to_string(%{uri | query: query |> Map.put(@param, locale) |> URI.encode_query()})
  end

  def path_for(_path, locale), do: path_for("/", locale)

  @doc "LiveView `on_mount` hook: installs the locale for the LiveView process."
  def on_mount(:default, params, session, socket) do
    locale = resolve(session_value(session), params[@param])
    Shared.put(locale)

    {:cont,
     assign(socket,
       locale: locale,
       current_path: "/",
       locale_options: options("/", locale)
     )}
  end

  @doc """
  Re-resolves the locale on every `handle_params/3` so a `?locale=` change
  applies without remounting, and records the current path for the switcher.
  """
  def on_params(socket, params, uri) do
    locale =
      Shared.normalize(params[@param]) || socket.assigns[:locale] || default()

    Shared.put(locale)
    path = uri_path(uri)

    assign(socket,
      locale: locale,
      current_path: path,
      locale_options: options(path, locale)
    )
  end

  defp persist_param(conn, nil), do: conn

  defp persist_param(conn, value) do
    case Shared.normalize(value) do
      nil -> conn
      locale -> Plug.Conn.put_session(conn, @session_key, locale)
    end
  end

  defp session_value(session) when is_map(session), do: session[@session_key]
  defp session_value(_), do: nil

  defp uri_path(uri) when is_binary(uri) do
    case URI.parse(uri).path do
      path when is_binary(path) and path != "" -> path
      _ -> "/"
    end
  end

  defp uri_path(_), do: "/"
end
