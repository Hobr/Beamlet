defmodule BeamletWeb.PageController do
  use BeamletWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
