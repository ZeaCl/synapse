defmodule SynapseWeb.MessageControllerTest do
  use SynapseWeb.ConnCase, async: false

  alias Synapse.Repo
  alias Synapse.Schemas.{Conversation, Participant, Message}
  import Ecto.Query

  setup %{conn: conn} do
    user_conn =
      conn
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> Plug.Conn.put_req_header("x-test-user-id", "test_user_a")
      |> Plug.Conn.put_req_header("x-test-name", "Test User A")

    conn = post(user_conn, "/conversations", %{type: "dm", participant_ids: ["user_b"]})
    conv = json_response(conn, 201)["data"]

    # Rebuild conn with auth headers for subsequent requests
    auth_conn =
      build_conn()
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> Plug.Conn.put_req_header("x-test-user-id", "test_user_a")
      |> Plug.Conn.put_req_header("x-test-name", "Test User A")

    {:ok, conn: auth_conn, conv: conv}
  end

  describe "POST /conversations/:id/messages" do
    test "creates a message", %{conn: conn, conv: conv} do
      conn = post(conn, "/conversations/#{conv["id"]}/messages", %{
        content: "hello world @user_b"
      })

      assert conn.status == 201
      assert json_response(conn, 201)["status"] == "sent"

      Process.sleep(100)

      messages = Repo.all(
        from m in Message,
          where: m.conversation_id == ^conv["id"]
      )
      assert length(messages) >= 1
    end

    test "returns 403 for non-participant", %{conv: conv} do
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> Plug.Conn.put_req_header("x-test-user-id", "outsider")
        |> Plug.Conn.put_req_header("x-test-name", "Outsider")
        |> post("/conversations/#{conv["id"]}/messages", %{content: "hey"})

      assert conn.status == 403
    end
  end

  describe "GET /conversations/:id/messages" do
    test "returns empty list for new conversation", %{conn: conn, conv: conv} do
      conn = get(conn, "/conversations/#{conv["id"]}/messages")
      assert conn.status == 200
      data = json_response(conn, 200)["data"]
      assert data == []
    end

    test "returns messages with cursor pagination", %{conn: conn, conv: conv} do
      for i <- 1..3 do
        post(conn, "/conversations/#{conv["id"]}/messages", %{content: "msg #{i}"})
      end

      Process.sleep(100)

      conn = get(conn, "/conversations/#{conv["id"]}/messages?limit=2")
      assert conn.status == 200
      data = json_response(conn, 200)["data"]
      cursor = json_response(conn, 200)["cursor"]

      assert length(data) == 2
      assert cursor["has_more"] == true
      assert cursor["next"] != nil
    end

    test "returns 403 for non-participant", %{conv: conv} do
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> Plug.Conn.put_req_header("x-test-user-id", "outsider")
        |> Plug.Conn.put_req_header("x-test-name", "Outsider")
        |> get("/conversations/#{conv["id"]}/messages")

      assert conn.status == 403
    end
  end
end
