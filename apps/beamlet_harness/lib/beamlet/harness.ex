defmodule Beamlet.Harness do
  @moduledoc "Independent neutral model and Tool contracts. Invocation data is explicit; hooks and Tool settings are local."
end

defmodule Beamlet.Harness.Tool do
  @moduledoc "Native Tool declaration and local invocation."
  @typedoc "Tool-specific local settings and output fields stay extensible; descriptors and arguments use neutral JSON."
  @type settings :: %{optional(atom() | String.t()) => term()}
  @type output :: %{optional(atom() | String.t()) => term()}
  @callback descriptor() :: Beamlet.Harness.Catalogue.descriptor()
  @callback invoke(Beamlet.Harness.Model.json_object(), settings(), Beamlet.Harness.Context.t()) ::
              {:ok, output()} | {:error, atom()}
end

defmodule Beamlet.Harness.Environment do
  @moduledoc "Portable opaque environment label, containing no host root or credentials."
  @enforce_keys [:id]
  defstruct [:id]
  @typedoc "Portable label resolved by the trusted local adapter; contains no host path."
  @type t :: %__MODULE__{id: String.t()}
end
