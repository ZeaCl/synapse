defmodule Synapse.GliaClient do
  @moduledoc """
  Forwards messages to Glia when an agent is @mentioned.

  Connects to Glia via WebSocket and relays messages.
  Agent responses flow back and are inserted as conversation messages.
  """

  require Logger

  @doc """
  Pushes a message to an agent via Glia WebSocket.

  The agent's response will be captured by a GenServer that listens
  on the Glia WebSocket channel for done events and reinserts them
  into the Synapse conversation.
  """
  def push_message(agent_id, conv_id, _message) do
    Logger.info("[GliaClient] Forwarding to agent #{agent_id} in conv #{conv_id}")

    # TODO: WebSocket connection to Glia
    # {:ok, _pid} = Synapse.GliaWorker.start_link(
    #   glia_ws: glia_ws,
    #   token: token,
    #   agent_id: agent_id,
    #   conv_id: conv_id,
    #   message: message.content
    # )

    :ok
  end
end
