defmodule Synapse.Schemas.MessageTest do
  use Synapse.DataCase, async: true

  alias Synapse.Schemas.Message

  describe "changeset/2" do
    test "valid text message" do
      changeset = Message.changeset(%Message{}, %{
        conversation_id: Ecto.UUID.generate(),
        sender_id: "user_a",
        content: "hello world"
      })
      assert changeset.valid?
    end

    test "valid message with mentions" do
      changeset = Message.changeset(%Message{}, %{
        conversation_id: Ecto.UUID.generate(),
        sender_id: "user_a",
        content: "hello @bob",
        mentions: ["bob_id"]
      })
      assert changeset.valid?
    end

    test "requires content" do
      changeset = Message.changeset(%Message{}, %{
        conversation_id: Ecto.UUID.generate(),
        sender_id: "user_a"
      })
      refute changeset.valid?
    end

    test "requires conversation_id" do
      changeset = Message.changeset(%Message{}, %{
        sender_id: "user_a",
        content: "hello"
      })
      refute changeset.valid?
    end

    test "default type is text" do
      changeset = Message.changeset(%Message{}, %{
        conversation_id: Ecto.UUID.generate(),
        sender_id: "user_a",
        content: "hello"
      })
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :type) == "text"
    end

    test "invalid type rejected" do
      changeset = Message.changeset(%Message{}, %{
        conversation_id: Ecto.UUID.generate(),
        sender_id: "user_a",
        content: "hello",
        type: "invalid"
      })
      refute changeset.valid?
    end

    test "valid image type" do
      changeset = Message.changeset(%Message{}, %{
        conversation_id: Ecto.UUID.generate(),
        sender_id: "user_a",
        content: "check this photo",
        type: "image",
        metadata: %{url: "https://example.com/img.jpg"}
      })
      assert changeset.valid?
    end
  end
end
