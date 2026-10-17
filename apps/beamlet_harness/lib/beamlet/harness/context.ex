defmodule Beamlet.Harness.Context do
  @moduledoc "Bounded conversation policy and optional local neutral hooks."
  defstruct progress: nil, cancelled?: nil
  @type t :: %__MODULE__{progress: nil | (map() -> any()), cancelled?: nil | (-> boolean())}

  def cancelled?(%__MODULE__{cancelled?: nil}), do: false
  def cancelled?(%__MODULE__{cancelled?: callback}), do: callback.() == true
  def emit(%__MODULE__{progress: nil}, _), do: :ok

  def emit(%__MODULE__{progress: callback}, event) do
    with true <- is_map(event),
         {:ok, json} <- Jason.encode(event),
         true <- byte_size(json) <= 8192 do
      callback.(event)
    else
      _ -> {:error, :progress_limit}
    end
  end

  def append(messages, additions) when is_list(messages) and is_list(additions) do
    all = messages ++ additions

    with true <- length(all) <= 128,
         {:ok, json} <- Jason.encode(all),
         true <- byte_size(json) <= 1_048_576 do
      {:ok, all}
    else
      _ -> {:error, :context_limit}
    end
  rescue
    _ -> {:error, :context_limit}
  end

  def append(_, _), do: {:error, :context_limit}
end
