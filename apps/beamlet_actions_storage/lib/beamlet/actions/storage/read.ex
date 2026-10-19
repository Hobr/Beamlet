defmodule Beamlet.Actions.Storage.Read do
  @moduledoc false
  # 只识别本领域严格 JSON 的 Ecto struct_load! 失败；其他 ArgumentError 保留原始堆栈，写事务同样复用此分类。
  alias Beamlet.Storage.Transaction

  @spec read((-> value)) :: value | {:error, :invalid_data | :storage_unavailable} when value: var
  def read(fun) do
    Transaction.read(fun)
  rescue
    error in ArgumentError ->
      if match?([{Ecto.Repo.Queryable, :struct_load!, _, _} | _], __STACKTRACE__) and
           String.starts_with?(error.message, "cannot load ") and
           String.contains?(error.message, [
             " as type #Beamlet.Actions.Storage.JSON<"
           ]),
         do: {:error, :invalid_data},
         else: reraise(error, __STACKTRACE__)
  end
end
