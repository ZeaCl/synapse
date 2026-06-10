defmodule Synapse.Conversation do
  @moduledoc """
  Manages an active conversation as a GenServer.

  One process per active conversation (someone has the WebSocket open).
  Handles message delivery, @mention resolution, and typing tracking.
  Auto-shuts down after 30 minutes of inactivity.
  """

  use GenServer
  require Logger

  alias Synapse.Repo
  alias Synapse.Schemas.{Message, Participant}
  import Ecto.Query

  @idle_timeout :timer.minutes(30)

  # ── Client API ──

  def start_link({conv_id, _opts}) do
    GenServer.start_link(__MODULE__, conv_id, name: via_tuple(conv_id))
  end

  def send_message(conv_id, sender_id, content) do
    case Registry.lookup(Synapse.ConversationRegistry, conv_id) do
      [{pid, _}] ->
        GenServer.cast(pid, {:send_message, sender_id, content})

      [] ->
        # GenServer not running — start it, then persist and broadcast
        DynamicSupervisor.start_child(Synapse.ConversationSupervisor, {__MODULE__, {conv_id, %{}}})
        Process.sleep(50)
        GenServer.cast(via_tuple(conv_id), {:send_message, sender_id, content})
    end
  end

  def typing(conv_id, user_id) do
    case Registry.lookup(Synapse.ConversationRegistry, conv_id) do
      [{pid, _}] -> GenServer.cast(pid, {:typing, user_id})
      [] -> :ok
    end
  end

  def participant?(conv_id, user_id) do
    Repo.exists?(
      from p in Participant,
        where: p.conversation_id == ^conv_id and p.user_id == ^user_id
    )
  end

  # ── GenServer Callbacks ──

  @impl true
  def init(conv_id) do
    schedule_idle_check()
    {:ok, %{conv_id: conv_id, typing_users: MapSet.new(), last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:send_message, sender_id, content}, state) do
    # 1. Parse @mentions
    mentions = Synapse.MessageParser.extract_mentions(content)
    resolved = resolve_mentions(mentions)

    # 2. Persist message
    {:ok, msg} =
      %Message{}
      |> Message.changeset(%{
        conversation_id: state.conv_id,
        sender_id: sender_id,
        content: content,
        mentions: Enum.map(resolved, & &1.id),
        type: "text"
      })
      |> Repo.insert()

    saved = Repo.preload(msg, :conversation)

    # 3. Side effects: forward to AI agent if recipient is an agent
    Task.start(fn ->
      # Check if any participant is an agent (not the sender)
      agent_ids = get_agent_participants(state.conv_id, sender_id)
      if agent_ids != [] do
        forward_to_agent(state.conv_id, agent_ids, content, saved)
      end

      # Add mentioned users as participants
      Enum.each(resolved, fn user ->
        add_participant(state.conv_id, user.id)
      end)
    end)

    # 4. Broadcast via PubSub
    Phoenix.PubSub.broadcast(Synapse.PubSub, topic(state.conv_id), {:new_message, saved})

    {:noreply, %{state | last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:typing, user_id}, state) do
    typing = MapSet.put(state.typing_users, user_id)

    Phoenix.PubSub.broadcast(Synapse.PubSub, topic(state.conv_id), {:typing_start, user_id})

    # Auto-clear typing after 3 seconds
    Process.send_after(self(), {:clear_typing, user_id}, 3000)

    {:noreply, %{state | typing_users: typing, last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:clear_typing, user_id}, state) do
    typing = MapSet.delete(state.typing_users, user_id)
    Phoenix.PubSub.broadcast(Synapse.PubSub, topic(state.conv_id), {:typing_stop, user_id})
    {:noreply, %{state | typing_users: typing}}
  end

  @impl true
  def handle_info(:idle_check, state) do
    # Auto-shutdown after idle timeout regardless of connections
    # (Tracker-based presence check requires phoenix_presence dep)
    Logger.info("[Conversation] #{state.conv_id} — idle shutdown")
    {:stop, :normal, state}
  end

  # ── Private Helpers ──

  defp topic(conv_id), do: "conversation:#{conv_id}"

  defp via_tuple(conv_id), do: {:via, Registry, {Synapse.ConversationRegistry, conv_id}}

  defp schedule_idle_check do
    Process.send_after(self(), :idle_check, @idle_timeout)
  end

  defp resolve_mentions(usernames) do
    # Skip Thalamus resolution when auth bypass is enabled
    if Application.get_env(:synapse, :auth_test_bypass, false) do
      Enum.map(usernames, fn name ->
        %{id: name, name: name, is_agent: false}
      end)
    else
      Synapse.ThalamusClient.resolve_users(usernames)
    end
  end

  defp add_participant(conv_id, user_id) do
    already = Repo.exists?(
      from p in Participant,
        where: p.conversation_id == ^conv_id and p.user_id == ^user_id
    )

    unless already do
      %Participant{}
      |> Participant.changeset(%{conversation_id: conv_id, user_id: user_id, role: "member"})
      |> Repo.insert(on_conflict: :nothing)
    end
  end

  # Check if any participant (other than sender) is an AI agent.
  # Queries Thalamus API to check is_agent flag for each participant.
  # Falls back to known agent IDs if Thalamus is unavailable.
  defp get_agent_participants(conv_id, sender_id) do
    participant_ids =
      from(p in Participant,
        where: p.conversation_id == ^conv_id and p.user_id != ^sender_id,
        select: p.user_id
      )
      |> Repo.all()

    case Synapse.ThalamusClient.check_agents(participant_ids) do
      {:ok, agent_ids} when agent_ids != [] ->
        Logger.info("[Conversation] Agents detected via Thalamus: #{inspect(agent_ids)}")
        agent_ids

      _ ->
        # Fallback to known agent IDs (Thalamus unavailable)
        known_agents = [
          "user_6d7bc3fe-0af6-44a9-8c50-631ff7127ee7",
          "6d7bc3fe-0af6-44a9-8c50-631ff7127ee7"
        ]
        fallback =
          Enum.filter(participant_ids, fn id ->
            String.contains?(id, "@agents.zea.io") or id in known_agents
          end)

        if fallback != [],
          do: Logger.info("[Conversation] Agents detected via fallback: #{inspect(fallback)}")

        fallback
    end
  end

  # Forward message to Pi backend for AI agent response.
  # Parses the SSE stream into individual events, broadcasting each delta
  # in real-time via agent_delta PubSub so the client sees the "thinking chain".
  defp forward_to_agent(conv_id, agent_ids, content, _original_msg) do
    pi_url = Application.get_env(:synapse, :pi_backend_url, "http://zea-agent:3001")
    sse_topic = topic(conv_id)

    Enum.each(agent_ids, fn agent_id ->
      body = Jason.encode!(%{
        "userId" => agent_id,
        "text" => content,
        "conversationId" => conv_id
      })

      case Req.post("#{pi_url}/message",
             headers: [{"content-type", "application/json"}],
             body: body,
             receive_timeout: 120_000) do
        {:ok, %{status: 200, body: response_body}} ->
          # Parse SSE events and stream deltas one by one
          events = parse_sse_events(response_body)
          full_text = stream_agent_deltas(sse_topic, events)

          # Persist the complete agent message
          if full_text != "" do
            {:ok, agent_msg} =
              %Message{}
              |> Message.changeset(%{
                conversation_id: conv_id,
                sender_id: agent_id,
                content: full_text,
                type: "text"
              })
              |> Repo.insert()

            saved = Repo.preload(agent_msg, :conversation)
            Phoenix.PubSub.broadcast(Synapse.PubSub, sse_topic, {:new_message, saved})
          end

        _ ->
          Logger.warning("[Conversation] Failed to get agent response from Pi backend")
      end
    end)
  end

  # Parse SSE body into a list of decoded JSON event maps.
  defp parse_sse_events(sse_body) do
    sse_body
    |> String.split("\n\n", trim: true)
    |> Enum.reduce([], fn event, acc ->
      case String.split(event, "\n") |> Enum.find(&String.starts_with?(&1, "data: ")) do
        nil ->
          acc

        data_line ->
          json_str = String.replace_prefix(data_line, "data: ", "")

          case Jason.decode(json_str) do
            {:ok, event_map} -> [event_map | acc]
            _ -> acc
          end
      end
    end)
    |> Enum.reverse()
  end

  # Broadcast each delta event via PubSub with small delays to simulate
  # real-time streaming. Accumulates full text for final message persistence.
  defp stream_agent_deltas(sse_topic, events) do
    Enum.reduce(events, "", fn event, acc ->
      case event do
        %{"type" => "delta", "text" => text} when is_binary(text) and text != "" ->
          # Small delay between deltas so the client sees the "thinking chain"
          Process.sleep(15)
          Phoenix.PubSub.broadcast(Synapse.PubSub, sse_topic, {:agent_delta, %{text: text}})
          acc <> text

        %{"type" => "tool", "name" => name} ->
          # Broadcast tool call so client can show a tool indicator
          tool_text = "\n\n🔧 _Usando #{name}..._"
          Phoenix.PubSub.broadcast(Synapse.PubSub, sse_topic, {:agent_delta, %{text: tool_text}})
          acc <> tool_text

        %{"type" => "tool_result"} ->
          # Tool results are internal — skip them (they're followed by deltas)
          acc

        _ ->
          acc
      end
    end)
  end
end
