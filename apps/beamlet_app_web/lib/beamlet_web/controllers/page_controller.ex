defmodule Beamlet.Web.PageController do
  use Beamlet.Web, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
