defmodule Beamlet.Harness.Tools.WorkspaceRead do
  @moduledoc """
  从受信本地树读取有界 UTF-8 文本。逐级 lstat 与打开后身份核对不构成原子 OS 沙箱；必须控制祖先目录、挂载和写入者，防止竞态、硬链接或阻塞存储。

  Read-only trusted-tree text Tool. Component checks are not atomic OS confinement.
  """
  @behaviour Beamlet.Harness.Tool
  alias Beamlet.Harness.{Arguments, Context}
  @impl true
  @typep text_result ::
           {:ok, %{text: binary(), truncated: boolean(), bytes: non_neg_integer()}}
           | {:error, :invalid_utf8}
  @typep read_result :: text_result() | {:error, :workspace_unavailable}
  @doc """
  返回静态数据描述；不访问本地设置、文件或认证。
  """
  @spec descriptor() :: Beamlet.Harness.Catalogue.descriptor()
  def descriptor do
    %{
      "name" => "workspace_read",
      "description" => "Read a relative UTF-8 text file",
      "parameters" => %{
        "type" => "object",
        "properties" => %{"path" => %{"type" => "string", "minLength" => 1, "maxLength" => 4096}},
        "required" => ["path"],
        "additionalProperties" => false
      }
    }
  end

  @doc """
  检查绝对、规范化、无 NUL 的根路径及其全部祖先均为非符号链接目录；成功返回 File.Stat，失败为 invalid_root 或 unsafe_path。
  """
  @spec validate_root(term()) :: {:ok, File.Stat.t()} | {:error, :invalid_root | :unsafe_path}
  def validate_root(root) when is_binary(root) do
    if String.valid?(root) and Path.type(root) == :absolute and
         not String.contains?(root, <<0>>) and Path.expand(root) == root do
      walk("/", Path.split(root) -- ["/"], :directory)
    else
      {:error, :invalid_root}
    end
  end

  def validate_root(_), do: {:error, :invalid_root}

  @impl true
  @doc """
  参数仅含相对 path；本地 settings 仅含 root 和可选 max_bytes（1..65536，默认 65536）。拒绝路径穿越、符号链接和非普通文件，读取 max+1 哨兵后总会关闭文件。返回 text/bytes/truncated；路径与设置错误为 workspace_unavailable，已观察文本非法为 invalid_utf8，调用前取消为 cancelled。截断时可丢弃不完整码点，不扫描哨兵以后的内容。
  """
  @spec invoke(term(), term(), Context.t()) :: read_result() | {:error, :cancelled}
  def invoke(args, settings, context \\ %Context{}) do
    with false <- Context.cancelled?(context),
         :ok <- Arguments.validate(args, descriptor()["parameters"]),
         %{root: root} <- settings,
         true <- Map.keys(settings) -- [:root, :max_bytes] == [],
         {:ok, _} <- validate_root(root),
         {:ok, parts} <- parts(args["path"]),
         {:ok, stat} <- walk(root, parts, :regular),
         max <- Map.get(settings, :max_bytes, 65_536),
         true <- is_integer(max) and max in 1..65_536 do
      read(Path.join([root | parts]), stat, max)
    else
      true -> {:error, :cancelled}
      _ -> {:error, :workspace_unavailable}
    end
  end

  @spec parts(String.t()) :: {:ok, [String.t()]} | {:error, :invalid_path}
  defp parts(path) do
    parts = String.split(path, "/")

    if byte_size(path) <= 4096 and Path.type(path) == :relative and length(parts) <= 32 and
         not String.contains?(path, [<<0>>, "\\"]) and
         Enum.all?(parts, &(&1 not in ["", ".", ".."])) do
      {:ok, parts}
    else
      {:error, :invalid_path}
    end
  end

  @spec walk(String.t(), [String.t()], :directory | :regular) ::
          {:ok, File.Stat.t()} | {:error, :unsafe_path}
  defp walk(path, [], type) do
    case File.lstat(path) do
      {:ok, %{type: ^type} = stat} -> {:ok, stat}
      _ -> {:error, :unsafe_path}
    end
  end

  defp walk(path, [part | rest], type) do
    with {:ok, _} <- walk(path, [], :directory), do: walk(Path.join(path, part), rest, type)
  end

  @spec read(String.t(), File.Stat.t(), pos_integer()) :: read_result()
  defp read(path, stat, max) do
    case :file.open(String.to_charlist(path), [:read, :raw, :binary]) do
      {:ok, fd} ->
        try do
          with {:ok, info} <- :file.read_file_info(fd),
               opened <- File.Stat.from_record(info),
               true <-
                 opened.type == :regular and opened.inode == stat.inode and
                   opened.major_device == stat.major_device,
               {:ok, data} <- read_data(fd, max + 1) do
            text(data, max)
          else
            _ -> {:error, :workspace_unavailable}
          end

          # 即使身份、读取或 UTF-8 校验失败也释放文件描述符。
        after
          :file.close(fd)
        end

      _ ->
        {:error, :workspace_unavailable}
    end
  end

  @spec read_data(:file.io_device(), pos_integer()) :: {:ok, binary()} | {:error, term()}
  defp read_data(fd, count) do
    case :file.read(fd, count) do
      :eof -> {:ok, ""}
      result -> result
    end
  end

  @spec text(binary(), pos_integer()) :: text_result()
  defp text(data, max) do
    truncated = byte_size(data) > max
    prefix = binary_part(data, 0, min(max, byte_size(data)))

    case :unicode.characters_to_binary(prefix, :utf8, :utf8) do
      text when is_binary(text) ->
        {:ok, %{text: text, truncated: truncated, bytes: byte_size(text)}}

      {:incomplete, valid, _} when truncated ->
        truncated_text(data, valid)

      _ ->
        {:error, :invalid_utf8}
    end
  end

  @spec truncated_text(binary(), binary()) :: text_result()
  defp truncated_text(data, valid) do
    case :unicode.characters_to_binary(data, :utf8, :utf8) do
      {:error, _, _} -> {:error, :invalid_utf8}
      {:incomplete, _, tail} -> truncated_result(valid, completable?(tail))
      _ -> truncated_result(valid, true)
    end
  end

  @spec truncated_result(binary(), boolean()) :: text_result()
  defp truncated_result(valid, true),
    do: {:ok, %{text: valid, truncated: true, bytes: byte_size(valid)}}

  defp truncated_result(_, false), do: {:error, :invalid_utf8}

  # 即便 OTP 暂缓校验短码点，也要校验已经观察到的哨兵字节。
  # Validate observed bytes even when OTP postpones validation of a short codepoint.
  @spec completable?(binary()) :: boolean()
  defp completable?(<<lead, _::binary>> = tail) do
    suffix =
      cond do
        lead == 0xE0 -> <<0xA0, 0x80>>
        lead == 0xF0 -> <<0x90, 0x80, 0x80>>
        lead in 0xC2..0xDF -> <<0x80>>
        lead in 0xE1..0xEF -> <<0x80, 0x80>>
        lead in 0xF1..0xF4 -> <<0x80, 0x80, 0x80>>
        true -> <<>>
      end

    missing = byte_size(suffix) + 1 - byte_size(tail)
    missing >= 0 and String.valid?(tail <> binary_part(suffix, byte_size(tail) - 1, missing))
  end
end
