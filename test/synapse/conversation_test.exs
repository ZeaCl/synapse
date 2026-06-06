defmodule Synapse.ConversationTest do
  use Synapse.DataCase, async: false

  alias Synapse.Repo
  alias Synapse.Conversation
  alias Synapse.Schemas.Participant
  alias Synapse.Schemas.Conversation, as: ConvSchema
  import Ecto.Query

  setup do
    conv_id = Ecto.UUID.generate()

    # Create conversation + participants directly
    {:ok, conv} =
      %ConvSchema{}
      |> ConvSchema.changeset(%{type: "dm", created_by: "user_a"})
      |> Repo.insert()

    %Participant{}
    |> Participant.changeset(%{conversation_id: conv.id, user_id: "user_a", role: "owner"})
    |> Repo.insert!()

    %Participant{}
    |> Participant.changeset(%{conversation_id: conv.id, user_id: "user_b", role: "member"})
    |> Repo.insert!()

    {:ok, conv: conv}
  end

  describe "participant?/2" do
    test "returns true for actual participant", %{conv: conv} do
      assert Conversation.participant?(conv.id, "user_a")
      assert Conversation.participant?(conv.id, "user_b")
    end

    test "returns false for non-participant", %{conv: conv} do
      refute Conversation.participant?(conv.id, "user_c")
    end
  end

  describe "send_message/3" do
    test "persists message to DB and starts GenServer", %{conv: conv} do
      Conversation.send_message(conv.id, "user_a", "hola @user_b")

      # Wait for async GenServer
      Process.sleep(100)

      messages = Repo.all(
        from m in Synapse.Schemas.Message,
          where: m.conversation_id == ^conv.id,
          order_by: [desc: :inserted_at]
      )

      assert length(messages) >= 1
      msg = List.last(messages)
      assert msg.content == "hola @user_b"
      assert msg.sender_id == "user_a"
      assert msg.type == "text"
    end

    test "starts GenServer if not running", %{conv: conv} do
      # GenServer should not exist yet
      assert Registry.lookup(Synapse.ConversationRegistry, conv.id) == []

      Conversation.send_message(conv.id, "user_a", "test message")
      Process.sleep(100)

      # GenServer should now be running
      assert [{pid, _}] = Registry.lookup(Synapse.ConversationRegistry, conv.id)
      assert Process.alive?(pid)
    end
  end
end
