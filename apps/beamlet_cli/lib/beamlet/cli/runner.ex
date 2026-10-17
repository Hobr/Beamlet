defmodule Beamlet.CLI.Runner do
  @moduledoc "Standalone terminal owner, invoked after Application startup by the release."
  alias Beamlet.CLI.{Command, Renderer, Session}

  def main do
    {:ok, _} = Application.ensure_all_started(:beamlet_cli)
    run(Session.new(Application.get_env(:beamlet_cli, :allowed_nodes, [])))
  end

  def run(session, opts \\ []) do
    read = Keyword.get(opts, :read, fn -> read_line(:stdio) end)
    output = Keyword.get(opts, :output, &Owl.IO.puts/1)
    exit = Keyword.get(opts, :exit, &System.stop/1)
    exit.(loop(session, read, output))
  end

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

  defp finish(chunks) do
    text = IO.iodata_to_binary(Enum.reverse(chunks))
    if String.valid?(text), do: text, else: {:error, :input}
  end
end
