defmodule Beamlet.Binding do
  @moduledoc """
  Validates trusted Handler snapshots and compares external retry protocols.

  Finite idempotency requires a resource-enforced expiry protocol, plus trusted
  contract_time at each retry decision. Authority lease time never extends it.
  Explicit valid_through: nil means an unbounded guarantee; omission is invalid.
  Capabilities originate in trusted Handler configuration, not caller payloads.
  Adapters derive key/scope from the complete saved Intent idempotency context.
  """

  alias Beamlet.{Identity, Value}

  @spec validate(term(), String.t()) :: :ok | {:error, atom()}
  def validate(binding, operation) when is_map(binding) and not is_struct(binding) do
    with :ok <- Value.validate(binding),
         :ok <- validate_fields(binding, operation) do
      validate_idempotency(binding["idempotency"])
    end
  end

  def validate(_binding, _operation), do: {:error, :invalid_handler_binding}

  @spec idempotency_valid?(map() | nil, map()) :: boolean()
  def idempotency_valid?(%{"idempotency" => contract}, context) when is_map(contract) do
    case Map.fetch(contract, "valid_through") do
      {:ok, nil} -> true
      {:ok, expiry} -> finite_valid?(expiry, contract, context)
      :error -> false
    end
  end

  def idempotency_valid?(_binding, _context), do: false

  @spec same_retry_protocol?(map(), map()) :: boolean()
  def same_retry_protocol?(original, next) do
    original["resource"] === next["resource"] and original["protocol"] === next["protocol"] and
      contract_identity(original["idempotency"]) === contract_identity(next["idempotency"])
  end

  defp contract_identity(contract) when is_map(contract),
    do: Map.take(contract, ["scope", "key", "protocol"])

  defp contract_identity(_contract), do: nil

  defp finite_valid?(expiry, contract, %{contract_time: at}) when is_integer(at),
    do: contract["expiry_enforced"] == true and at <= expiry

  defp finite_valid?(_expiry, _contract, _context), do: false

  defp validate_fields(binding, operation) do
    valid =
      binding["operation"] == operation and Identity.valid_text?(binding["handler"]) and
        Identity.valid_text?(binding["protocol"]) and is_map(binding["resource"]) and
        optional_map?(binding["completion"]) and optional_map?(binding["query"])

    if valid, do: :ok, else: {:error, :invalid_handler_binding}
  end

  defp optional_map?(nil), do: true
  defp optional_map?(value), do: is_map(value) and map_size(value) > 0

  defp validate_idempotency(nil), do: :ok

  defp validate_idempotency(contract) when is_map(contract) do
    valid =
      Identity.valid_text?(contract["key"]) and Identity.valid_text?(contract["protocol"]) and
        is_map(contract["scope"]) and map_size(contract["scope"]) > 0 and
        Map.has_key?(contract, "valid_through") and valid_window?(contract)

    if valid, do: :ok, else: {:error, :invalid_idempotency_contract}
  end

  defp validate_idempotency(_contract), do: {:error, :invalid_idempotency_contract}

  defp valid_window?(%{"valid_through" => nil}), do: true

  defp valid_window?(%{"valid_through" => expiry, "expiry_enforced" => enforced}),
    do: is_integer(expiry) and expiry >= 0 and is_boolean(enforced)

  defp valid_window?(_contract), do: false
end
