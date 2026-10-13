defmodule BeamletWeb.PubSubTest do
  use ExUnit.Case, async: true

  test "the endpoint's PubSub server supports subscriptions and broadcasts" do
    pubsub = BeamletWeb.Endpoint.config(:pubsub_server)
    topic = "pubsub_test:#{System.unique_integer([:positive])}"
    message = {:pubsub_test, make_ref()}

    assert :ok = Phoenix.PubSub.subscribe(pubsub, topic)
    assert :ok = Phoenix.PubSub.broadcast(pubsub, topic, message)
    assert_receive ^message
  end
end
