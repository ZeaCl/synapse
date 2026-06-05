defmodule SynapseWeb.ConversationChannel do
  use Phoenix.Channel
  require Logger

  @impl true
  def join("conversation:" <> conv_id, _params, socket) do
    user_id = socket.assigns.user_id

    if Synapse.Conversation.participant?(conv_id, user_id) do
      # Ensure GenServer is running for this conversation
      DynamicSupervisor.start_child(
        Synapse.ConversationSupervisor,
        {Synapse.Conversation, {conv_id, %{}}}
      )

      # Track presence (placeholder — requires Phoenix.Tracker dependency)
      # {:ok, _} = Phoenix.Tracker.track(...)

      socket = assign(socket, :conversation_id, conv_id)
      {:ok, socket}
    else
      {:error, %{reason: "not_participant"}}
    end
  end

  @impl true
  def handle_in("send_message", %{"content" => content}, socket) do
    conv_id = socket.assigns.conversation_id
    user_id = socket.assigns.user_id

    Synapse.Conversation.send_message(conv_id, user_id, content)
    {:noreply, socket}
  end

  @impl true
  def handle_in("typing", _params, socket) do
    conv_id = socket.assigns.conversation_id
    user_id = socket.assigns.user_id

    Synapse.Conversation.typing(conv_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, msg}, socket) do
    push(socket, "new_message", %{
      id: msg.id,
      sender_id: msg.sender_id,
      content: msg.content,
      mentions: msg.mentions,
      type: msg.type,
      inserted_at: msg.inserted_at
    })
    {:noreply, socket}
  end

  def handle_info({:typing_start, user_id}, socket) do
    push(socket, "typing_start", %{user_id: user_id})
    {:noreply, socket}
  end

  def handle_info({:typing_stop, user_id}, socket) do
    push(socket, "typing_stop", %{user_id: user_id})
    {:noreply, socket}
  end

  # PubSub subscription happens on join
  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, _socket) do
    :ok
  end
end
