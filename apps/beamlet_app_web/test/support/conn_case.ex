defmodule Beamlet.Web.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Beamlet.Web.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint Beamlet.Web.Endpoint

      use Beamlet.Web, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Beamlet.Web.ConnCase
    end
  end

  @doc """
  Default locale for web tests.

  Tests assert behaviour and copy, and the product ships Chinese by default, so
  every `ConnCase` connection starts with an explicit English session locale:
  the assertions keep testing behaviour instead of translation, and no test
  depends on the process-wide or application default. Chinese tests opt in with
  `@tag locale: "zh_CN"`, and the test that has to prove the shipped default
  builds a session-less connection of its own.
  """
  @test_locale "en"

  def test_locale, do: @test_locale

  setup tags do
    locale = Map.get(tags, :locale, @test_locale)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{"locale" => locale})

    {:ok, conn: conn, locale: locale}
  end
end
