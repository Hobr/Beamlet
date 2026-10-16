defmodule Beamlet.Harness do
  @moduledoc "Independent native model and Tool contracts. Settings and callbacks remain executor-local."
end

defmodule Beamlet.Harness.Model do
  @moduledoc "A model returns one complete validated reply; no runtime identities are required."
  @callback complete(map(), map(), Beamlet.Harness.Context.t()) :: {:ok, map()} | {:error, atom()}
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
