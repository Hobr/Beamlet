defmodule Beamlet.Harness.WorkspaceTest do
  use ExUnit.Case, async: true
  alias Beamlet.Harness.Tools.WorkspaceRead, as: Read

  setup do
    root = Path.join(System.tmp_dir!(), "harness-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "bounded descriptor reads preserve UTF-8 at every boundary and close on failure", %{
    root: root
  } do
    File.write!(Path.join(root, "text"), "a😀z")

    for {max, expected} <- [{1, "a"}, {2, "a"}, {3, "a"}, {4, "a"}, {5, "a😀"}, {6, "a😀z"}] do
      assert {:ok, %{text: ^expected, truncated: truncated}} =
               Read.invoke(%{"path" => "text"}, %{root: root, max_bytes: max})

      assert truncated == max < 6
    end

    File.write!(Path.join(root, "empty"), "")
    assert {:ok, %{text: "", truncated: false}} = Read.invoke(%{"path" => "empty"}, %{root: root})
    File.write!(Path.join(root, "bad"), <<255>>)
    before = length(File.ls!("/proc/self/fd"))

    for _ <- 1..50,
        do: assert({:error, :invalid_utf8} = Read.invoke(%{"path" => "bad"}, %{root: root}))

    assert length(File.ls!("/proc/self/fd")) == before
    File.write!(Path.join(root, "long"), String.duplicate("x", 100_000))

    assert {:ok, %{bytes: 65_536, truncated: true}} =
             Read.invoke(%{"path" => "long"}, %{root: root})
  end

  test "rejects unsafe components, ancestors, symlinks and nonregular leaves", %{root: root} do
    File.write!(Path.join(root, "ok"), "allowed")
    File.ln_s!(Path.join(root, "ok"), Path.join(root, "link"))
    File.mkdir!(Path.join(root, "dir"))
    File.ln_s!(Path.join(root, "dir"), Path.join(root, "alias"))
    {"", 0} = System.cmd("mkfifo", [Path.join(root, "fifo")])

    for path <- [
          "",
          "/etc/passwd",
          "../ok",
          "a/../ok",
          "./ok",
          "a//ok",
          "a\\ok",
          "a\0",
          "link",
          "dir",
          "alias/ok",
          "fifo",
          "missing",
          String.duplicate("a/", 33) <> "ok"
        ] do
      assert {:error, _} = Read.invoke(%{"path" => path}, %{root: root})
    end

    assert {:error, _} = Read.validate_root(Path.join(root, "alias"))
    assert {:error, _} = Read.validate_root(Path.join(root, "alias/child"))
    assert File.read!(Path.join(root, "ok")) == "allowed"
  end

  test "sentinel exposes invalid continuation but permits an unobserved truncated suffix", %{
    root: root
  } do
    for bytes <- [<<0xE2, 0x41>>, <<0xF0, 0x80>>, <<0xED, 0xA0>>] do
      File.write!(Path.join(root, "sentinel"), bytes)

      assert {:error, :invalid_utf8} =
               Read.invoke(%{"path" => "sentinel"}, %{root: root, max_bytes: 1})
    end

    File.write!(Path.join(root, "sentinel"), <<0xF0, 0x9F, 0x98>>)

    assert {:ok, %{text: "", bytes: 0, truncated: true}} =
             Read.invoke(%{"path" => "sentinel"}, %{root: root, max_bytes: 1})

    assert {:error, :invalid_utf8} = Read.invoke(%{"path" => "sentinel"}, %{root: root})
    assert {:error, _} = Read.invoke(%{"path" => "sentinel"}, %{root: root, write: true})
  end

  test "all UTF-8 codepoint widths and device leaves", %{root: root} do
    for codepoint <- ["é", "€", "😀"] do
      File.write!(Path.join(root, "unicode"), "x" <> codepoint <> "z")

      for max <- 1..(byte_size(codepoint) + 2) do
        {:ok, result} = Read.invoke(%{"path" => "unicode"}, %{root: root, max_bytes: max})
        assert String.valid?(result.text)
        assert result.bytes == byte_size(result.text)
        assert result.bytes <= max
        assert result.truncated == max < byte_size(codepoint) + 2
      end
    end

    assert {:error, _} = Read.invoke(%{"path" => "null"}, %{root: "/dev"})
  end
end
