defmodule Beamlet.CLI.Command do
  @moduledoc """
  终端命令的有界 UTF-8 语法；最多 65536 字节，无通用求值或 shell 转义。超限执行文本整体拒绝，不截取前缀执行。

  Bounded UTF-8 command grammar. Executable input is never truncated.
  """
  @max_bytes 65_536
  @typedoc "解析后的固定命令元组；命令字面量与参数数量由语法校验，不是 Elixir 表达式。

Parsed commands; binary command literals are enforced by the grammar."
  @type t ::
          {binary()}
          | {binary(), binary()}
          | {:input, binary(), binary()}
          | {:agents, binary() | nil}
          | {:agents_page, pos_integer()}
          | {:connect, binary()}
          | {:create, binary(), binary()}
          | {:attach, binary(), binary(), binary()}
          | {:watch, binary(), keyword()}
  @typep parsed :: {:ok, t()} | {:error, :invalid_command}
  @doc "返回可执行命令行的 65536 字节上限。"
  @spec max_bytes() :: 65_536
  def max_bytes, do: @max_bytes

  @doc "解析完整 UTF-8 命令行；非法类型、字节、语法或超限返回 invalid_command，不执行命令。"
  @spec parse(term()) :: parsed()
  def parse(line) when is_binary(line) and byte_size(line) <= @max_bytes do
    if String.valid?(line), do: parse_words(String.trim_trailing(line, "\n")), else: error()
  end

  def parse(_), do: error()
  @spec error() :: {:error, :invalid_command}
  defp error, do: {:error, :invalid_command}

  @spec parse_words(binary()) :: parsed()
  defp parse_words(line) do
    case String.split(line, ~r/\s+/, parts: 3, trim: true) do
      ["input", name, text] when byte_size(text) > 0 -> {:ok, {:input, name, text}}
      _ -> words(String.split(line))
    end
  end

  @spec words([binary()]) :: parsed()
  defp words([command]) when command in ~w(help nodes quit), do: {:ok, {command}}
  defp words(["agents"]), do: {:ok, {:agents, nil}}
  defp words(["agents", authority]), do: {:ok, {:agents, authority}}

  defp words(["agents-page", page]) do
    case Integer.parse(page) do
      {n, ""} when n > 0 -> {:ok, {:agents_page, n}}
      _ -> error()
    end
  end

  defp words(["connect", authority]), do: {:ok, {:connect, authority}}
  defp words(["create", authority, path]), do: {:ok, {:create, authority, path}}
  defp words(["attach", authority, id]), do: attach(authority, id, id)
  defp words(["attach", authority, id, name]), do: attach(authority, id, name)

  defp words([command, name]) when command in ~w(status stop close detach),
    do: {:ok, {command, name}}

  defp words(["watch", name]), do: {:ok, {:watch, name, []}}

  defp words(["watch", name, timeout]), do: words(["watch", name, timeout, "64"])

  defp words(["watch", name, timeout, events]) do
    with {ms, ""} <- Integer.parse(timeout),
         {count, ""} <- Integer.parse(events),
         true <- ms in 1..60_000 and count in 1..256 do
      {:ok, {:watch, name, [timeout: ms, events: count]}}
    else
      _ -> error()
    end
  end

  defp words(_), do: error()
  @doc "将完整 UTF-8 ID 编码为无填充 Base64url 的 id64 标记，便于含空白或保留前缀的 ID 精确 attach；解析时另行验证 1..128 字节限制。"
  @spec identity_token(binary()) :: binary()
  def identity_token(id), do: "id64:" <> Base.url_encode64(id, padding: false)

  @spec attach(binary(), binary(), binary()) :: parsed()
  defp attach(authority, "id64:" <> encoded, name) do
    with {:ok, id} <- Base.url_decode64(encoded, padding: false),
         true <- byte_size(id) in 1..128 and String.valid?(id) do
      {:ok, {:attach, authority, id, name}}
    else
      _ -> error()
    end
  end

  defp attach(authority, id, name), do: {:ok, {:attach, authority, id, name}}
end
