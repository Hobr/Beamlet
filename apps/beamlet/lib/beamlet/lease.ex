defmodule Beamlet.Lease do
  @moduledoc "Temporary control permission, with an explicit invalidation barrier."

  alias Beamlet.Token

  @max_counter 9_223_372_036_854_775_807
  @enforce_keys [:token, :expires_at]
  defstruct [:token, :expires_at, invalidated: false]

  @type t :: %__MODULE__{token: Token.t(), expires_at: integer(), invalidated: boolean()}

  @spec valid?(t() | nil, Token.t(), integer()) :: boolean()
  def valid?(%__MODULE__{token: token, invalidated: false, expires_at: expiry}, token, now),
    do: now < expiry

  def valid?(_lease, _token, _now), do: false

  @spec generation(t() | nil) :: non_neg_integer()
  def generation(nil), do: 0
  def generation(%__MODULE__{token: token}), do: token.generation

  @spec expiry(integer(), pos_integer()) :: {:ok, integer()} | {:error, :invalid_ttl}
  def expiry(now, ttl)
      when is_integer(now) and is_integer(ttl) and ttl > 0 and
             now >= -@max_counter - 1 and now <= @max_counter and now + ttl <= @max_counter,
      do: {:ok, now + ttl}

  def expiry(_now, _ttl), do: {:error, :invalid_ttl}

  @spec next_generation(non_neg_integer()) ::
          {:ok, pos_integer()} | {:error, :generation_exhausted}
  def next_generation(n) when is_integer(n) and n >= 0 and n < @max_counter, do: {:ok, n + 1}
  def next_generation(_n), do: {:error, :generation_exhausted}
end
