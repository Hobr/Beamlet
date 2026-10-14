defmodule BeamletWeb.QrCodeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "the custom-pattern encoder retains its output after the bitstring fix" do
    result = EQRCode.Encode.encode("beamlet", :l, <<0::64>>)
    assert {5, :l, bits} = result
    assert Enum.all?(bits, &(&1 in [0, 1]))

    digest = :crypto.hash(:sha256, :erlang.term_to_binary(result)) |> Base.encode16(case: :lower)
    assert digest == "e0b823c411df81fa349fdac40d2eef1eacf000a7111ad2fd944f8e6530adec47"
  end

  test "the Petal QR component encodes a value into an accessible SVG" do
    html =
      render_component(&PetalComponents.QrCode.qr_code/1,
        value: "https://beamlet.example/pair",
        label: "Pair with Beamlet",
        background: "white"
      )

    document = LazyHTML.from_document(html)

    assert [_] =
             document
             |> LazyHTML.query(~s(svg[role="img"][aria-label="Pair with Beamlet"]))
             |> Enum.to_list()

    assert [path] = document |> LazyHTML.query("svg > path") |> Enum.to_list()
    assert [encoded] = LazyHTML.attribute(path, "d")
    assert byte_size(encoded) > 100
    refute html =~ "https://beamlet.example/pair"
  end
end
