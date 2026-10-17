defmodule Beamlet.Node.TestBinding do
  @moduledoc false
  def observer(name),
    do: {:beamlet_test_observer, Enum.find([node() | Node.list()], &(Atom.to_string(&1) == name))}

  def binding(id) do
    observer = Atom.to_string(node())

    if Process.whereis(:beamlet_test_observer) == nil,
      do: Process.register(self(), :beamlet_test_observer)

    true = Process.whereis(:beamlet_test_observer) == self()
    provider = if id in ["absent", "missing"], do: "held", else: id

    config =
      case id do
        "held" -> %{"hold" => true}
        "model" -> %{"loop" => true}
        "bad" -> %{"loop" => true, "invalid" => true}
        _ -> %{}
      end

    %{
      provider: provider,
      placement: if(id in ["absent", "missing"], do: %{environment: "absent"}, else: %{}),
      config: Map.put(config, "observer", observer)
    }
  end
end
