defmodule Beamlet.Harness do
  @moduledoc "Independent neutral model and Tool contracts. Invocation data is explicit; hooks and Tool settings are local."
end

defmodule Beamlet.Harness.Tool do
  @moduledoc "Native Tool declaration and local invocation."
  @callback descriptor() :: map()
  @callback invoke(map(), map(), Beamlet.Harness.Context.t()) :: {:ok, map()} | {:error, atom()}
end

defmodule Beamlet.Harness.Environment do
  @moduledoc "Portable opaque environment label, containing no host root or credentials."
  @enforce_keys [:id]
  defstruct [:id]
end
