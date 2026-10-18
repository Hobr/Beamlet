defmodule Beamlet.Storage.TerminalArtifacts do
  @moduledoc """
  Executor-journal terminal attachment container (version 1). The container is
  data, never live references: `%{"version" => 1, "items" => %{artifact_id =>
  %{"digest", "media_type", "size_bytes", "content_base64"}}}`. Every item is
  decoded and checked against its digest and size before the terminal commit;
  limits reject explicitly instead of truncating. The journal cannot resolve
  authority artifact rows, so it verifies identity shape and content integrity,
  not authority existence (that stays in the authority transaction).
  """
  alias Beamlet.Storage.Codec

  @version 1
  @max_items 64
  @max_item 16_777_216
  @max_total_decoded 16_777_216
  @max_encoded 25_165_824
  @item_keys ~w(content_base64 digest media_type size_bytes)
  @base64 ~r/\A(?:[A-Za-z0-9+\/]{4})*(?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=)?\z/
  @digest ~r/\A[0-9a-f]{64}\z/

  @doc "Validates and returns the container unchanged, or a stage-A error atom."
  def encode(container) do
    with {:ok, items} <- container_items(container),
         {:ok, decoded_total} <- validate_items(items),
         {:ok, encoded} <- encoded_size(container) do
      cond do
        decoded_total > @max_total_decoded -> {:error, :limit}
        encoded > @max_encoded -> {:error, :limit}
        true -> {:ok, container}
      end
    end
  end

  @doc "Byte size of the canonical stored representation; used by the 32 MiB transaction budget."
  def encoded_size(value) do
    case Codec.encode(value, :journal_artifacts) do
      {:ok, bytes} -> {:ok, byte_size(bytes)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Decoded bytes of one validated item, or a stage-A error atom."
  def content(container, artifact_id) do
    with {:ok, items} <- container_items(container),
         {:ok, item} <- fetch_item(items, artifact_id),
         {:ok, bytes} <- decode_item(item) do
      {:ok, bytes}
    end
  end

  defp fetch_item(items, artifact_id) do
    case Map.fetch(items, artifact_id) do
      {:ok, item} -> {:ok, item}
      :error -> {:error, :artifact_missing}
    end
  end

  defp container_items(%{"version" => @version, "items" => items} = container)
       when map_size(container) == 2 and is_map(items) and not is_struct(items) do
    cond do
      not Enum.all?(Map.keys(items), &Codec.uuid?/1) -> {:error, :invalid_data}
      map_size(items) > @max_items -> {:error, :limit}
      true -> {:ok, items}
    end
  end

  defp container_items(_), do: {:error, :invalid_data}

  defp validate_items(items) do
    Enum.reduce_while(items, {:ok, 0}, fn {_id, item}, {:ok, total} ->
      case decode_item(item) do
        {:ok, bytes} when byte_size(bytes) + total <= @max_total_decoded ->
          {:cont, {:ok, total + byte_size(bytes)}}

        {:ok, _bytes} ->
          {:halt, {:error, :limit}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp decode_item(item) when is_map(item) and not is_struct(item) do
    if Enum.sort(Map.keys(item)) == @item_keys do
      with {:ok, digest} <- digest(item["digest"]),
           {:ok, _media_type} <- media_type(item["media_type"]),
           {:ok, size} <- size_bytes(item["size_bytes"]),
           {:ok, content} <- base64(item["content_base64"]) do
        cond do
          byte_size(content) > @max_item -> {:error, :limit}
          byte_size(content) != size -> {:error, :invalid_data}
          Codec.hash(content) != digest -> {:error, :invalid_data}
          true -> {:ok, content}
        end
      end
    else
      {:error, :invalid_data}
    end
  end

  defp decode_item(_), do: {:error, :invalid_data}

  defp digest(value) when is_binary(value) do
    if Regex.match?(@digest, value), do: {:ok, value}, else: {:error, :invalid_data}
  end

  defp digest(_), do: {:error, :invalid_data}

  defp media_type(value) when is_binary(value) do
    if String.valid?(value) and byte_size(value) in 1..255,
      do: {:ok, value},
      else: {:error, :invalid_data}
  end

  defp media_type(_), do: {:error, :invalid_data}

  defp size_bytes(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp size_bytes(_), do: {:error, :invalid_data}

  defp base64(value) when is_binary(value) do
    with true <- Regex.match?(@base64, value),
         {:ok, decoded} <- Base.decode64(value),
         true <- Base.encode64(decoded) == value do
      {:ok, decoded}
    else
      _ -> {:error, :invalid_data}
    end
  end

  defp base64(_), do: {:error, :invalid_data}
end
