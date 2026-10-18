defmodule Beamlet.Agent.Storage.Read do
  @moduledoc false
  alias Beamlet.Storage.Transaction

  def read(fun) do
    Transaction.read(fun)
  rescue
    error in ArgumentError ->
      if match?([{Ecto.Repo.Queryable, :struct_load!, _, _} | _], __STACKTRACE__) and
           String.starts_with?(error.message, "cannot load ") and
           String.contains?(error.message, [
             " as type #Beamlet.Agent.Storage.JSON<",
             " as type #Beamlet.Actions.Storage.JSON<"
           ]),
         do: {:error, :invalid_data},
         else: reraise(error, __STACKTRACE__)
  end
end
