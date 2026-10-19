defmodule Beamlet.CLI.Runner do
  @moduledoc """
  独占标准输入的前台会话宿主，由发布入口在应用启动后调用。EOF/quit 退出码为 0，读取错误为 1；退出不关闭已有 Agent。

  Standalone terminal owner, invoked after Application startup by the release.
  """
  alias Beamlet.CLI.{Command, Locale, Renderer, Session}

  @typep line :: binary() | :eof | {:error, :input | :line_limit}
  @typep output :: (binary() -> term())
  @typedoc "可注入的终端读取、输出和退出效果，退出回调的返回值保留。

Injected terminal effects; exit callback's value is preserved."
  @type options(value) :: [{:read, (-> line())} | {:output, output()} | {:exit, (0 | 1 -> value)}]
  @doc "确保 CLI 应用已启动，然后进入读取循环；默认退出回调结束 VM，供前台发布入口使用。"
  @spec main() :: :ok
  def main do
    {:ok, _} = Application.ensure_all_started(:beamlet_cli)
    run(Session.new(Application.get_env(:beamlet_cli, :allowed_nodes, [])))
  end

  @doc "安装当前进程语言并运行会话；可注入 read/output/exit 效果，返回退出回调结果。EOF/quit 不关闭 Agent。"
  @spec run(Session.t(), options(value)) :: value | :ok when value: var
  def run(session, opts \\ []) do
    # The locale is resolved once for the process before any stdin is read, so
    # every later Renderer/Session output in this process uses one language.
    # Locale installation is a process side effect; the resolved name is unused.
    _ = Locale.put()
    read = Keyword.get(opts, :read, fn -> read_line(:stdio) end)
    output = Keyword.get(opts, :output, &Owl.IO.puts/1)
    exit = Keyword.get(opts, :exit, &System.stop/1)
    exit.(loop(session, read, output))
  end

  @spec loop(Session.t(), (-> line()), output()) :: 0 | 1
  defp loop(session, read, output) do
    case read.() do
      :eof ->
        0

      {:error, _} ->
        output.(Renderer.render({:error, :invalid_command}))
        1

      line ->
        case Session.execute(session, line, output) do
          {:quit, _} -> 0
          {:continue, next} -> loop(next, read, output)
        end
    end
  end

  # A terminal's Unicode decoder can replace malformed input before returning it.
  # The exclusive reader temporarily requests Latin-1 device encoding so binread
  # transports original bytes, then restores encoding before any output/callback.
  # Pipes and injected nonterminal devices require no device-option mutation.
  @doc """
  逐字节读取至 LF 或 EOF，保留部分 EOF 与文本空格；超限/非法 UTF-8 整体拒绝。独占终端临时切换 Latin-1 并在返回前恢复编码，非终端不改选项。

  Reads one line from the device, preserving original bytes and trailing spaces;
  an over-limit or invalid UTF-8 line is rejected as a whole.
  """
  @spec read_line(IO.device()) :: line()
  def read_line(device) do
    target = if device == :stdio, do: :standard_io, else: device
    options = :io.getopts(target)

    if is_list(options) and Keyword.get(options, :terminal, false) do
      case :io.setopts(target, encoding: :latin1) do
        :ok ->
          try do
            read_line(device, [], 0)
          after
            :io.setopts(target, encoding: Keyword.fetch!(options, :encoding))
          end

        _ ->
          {:error, :input}
      end
    else
      read_line(device, [], 0)
    end
  end

  # Byte loop shared by read_line/1: reject the whole line once it exceeds the
  # command byte limit, and validate UTF-8 only after the line is complete.
  @spec read_line(IO.device(), [binary()], non_neg_integer()) :: line()
  defp read_line(device, chunks, count) do
    case IO.binread(device, 1) do
      :eof ->
        if count == 0, do: :eof, else: finish(chunks)

      {:error, _} ->
        {:error, :input}

      "\n" ->
        finish(chunks)

      byte ->
        if count + byte_size(byte) > Command.max_bytes(),
          do: {:error, :line_limit},
          else: read_line(device, [byte | chunks], count + byte_size(byte))
    end
  end

  @spec finish([binary()]) :: binary() | {:error, :input}
  defp finish(chunks) do
    text = IO.iodata_to_binary(Enum.reverse(chunks))
    if String.valid?(text), do: text, else: {:error, :input}
  end
end
