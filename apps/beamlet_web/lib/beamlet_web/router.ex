defmodule Beamlet.Web.Router do
  use Beamlet.Web, :router

  @live_debugger_sources (if Mix.env() == :dev do
                            port = Application.compile_env!(:live_debugger, :port)

                            {" http://127.0.0.1:#{port}",
                             "; connect-src 'self' http://127.0.0.1:#{port} ws://127.0.0.1:#{port}"}
                          else
                            {"", ""}
                          end)

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Beamlet.Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  defp put_csp_nonce(conn, _opts) do
    nonce = :crypto.strong_rand_bytes(16) |> Base.encode64()
    [policy] = get_resp_header(conn, "content-security-policy")

    {debugger_assets, debugger_connections} = @live_debugger_sources

    # Keep LiveDebugger's cross-origin assets and socket limited to development.
    # LiveView and the theme switcher need inline styles, but scripts require a nonce.
    policy =
      policy <>
        "; script-src 'self' 'nonce-#{nonce}'#{debugger_assets};" <>
        " style-src 'self' 'unsafe-inline'#{debugger_assets}; img-src 'self' data:" <>
        debugger_connections

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy)
  end

  scope "/", Beamlet.Web do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", Beamlet.Web do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:beamlet_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Beamlet.Web.Telemetry
    end
  end
end
