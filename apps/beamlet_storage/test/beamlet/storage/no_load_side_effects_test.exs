defmodule Beamlet.Storage.NoLoadSideEffectsTest do
  use ExUnit.Case, async: true

  test "fresh VM application loading and dependency startup create no Repo or files" do
    path =
      Path.join(System.tmp_dir!(), "beamlet-no-load-#{System.unique_integer([:positive])}.db")

    code = """
    path = System.fetch_env!("BEAMLET_TEST_UNUSED_DB")
    for repo <- [Beamlet.Storage.SQLiteAuthorityRepo, Beamlet.Storage.ExecutorJournalRepo, Beamlet.Storage.PostgresAuthorityRepo] do
      Application.put_env(:beamlet_storage, repo, database: path)
    end
    {:ok, _} = Application.ensure_all_started(:beamlet_storage)
    for repo <- [Beamlet.Storage.SQLiteAuthorityRepo, Beamlet.Storage.ExecutorJournalRepo, Beamlet.Storage.PostgresAuthorityRepo] do
      nil = Process.whereis(repo)
    end
    false = File.exists?(path)
    IO.puts("storage-load-side-effects:none")
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, 0} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", code],
        env: [{"BEAMLET_TEST_UNUSED_DB", path}, {"ERL_FLAGS", "+S 2:2"}],
        stderr_to_stdout: true
      )

    assert output =~ "storage-load-side-effects:none"
    refute File.exists?(path)
  end
end
