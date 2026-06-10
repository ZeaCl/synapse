defmodule SynapseWeb.ConversationControllerTest do
  use SynapseWeb.ConnCase, async: false

  alias Synapse.Repo
  alias Synapse.Schemas.{Conversation, Participant}
  import Ecto.Query

  setup %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> Plug.Conn.put_req_header("x-test-user-id", "test_user_a")
      |> Plug.Conn.put_req_header("x-test-name", "Test User A")

    {:ok, conn: conn}
  end

  defp conn_for(user_id, name \\ nil) do
    name = name || user_id

    build_conn()
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header("x-test-user-id", user_id)
    |> Plug.Conn.put_req_header("x-test-name", name)
  end

  describe "POST /conversations" do
    test "creates a DM conversation", %{conn: conn} do
      conn = post(conn, "/conversations", %{
        type: "dm",
        participant_ids: ["user_b"]
      })

      assert conn.status == 201
      data = json_response(conn, 201)["data"]
      assert data["type"] == "dm"
      assert data["created_by"] == "test_user_a"

      participants = Repo.all(from p in Participant, where: p.conversation_id == ^data["id"])
      assert length(participants) == 2
      user_ids = Enum.map(participants, & &1.user_id)
      assert "test_user_a" in user_ids
      assert "user_b" in user_ids
    end

    test "returns existing DM if one already exists", %{conn: conn} do
      conn1 = post(conn, "/conversations", %{type: "dm", participant_ids: ["user_b"]})
      conv1 = json_response(conn1, 201)["data"]

      conn2 = post(conn, "/conversations", %{type: "dm", participant_ids: ["user_b"]})
      conv2 = json_response(conn2, 201)["data"]

      assert conv2["id"] == conv1["id"]
    end

    test "creates a group conversation with title", %{conn: conn} do
      conn = post(conn, "/conversations", %{
        type: "group",
        title: "Test Group",
        participant_ids: ["user_b", "user_c"]
      })

      assert conn.status == 201
      data = json_response(conn, 201)["data"]
      assert data["type"] == "group"
      assert data["title"] == "Test Group"

      participants = Repo.all(from p in Participant, where: p.conversation_id == ^data["id"])
      assert length(participants) == 3
    end

    test "rejects group without title", %{conn: conn} do
      conn = post(conn, "/conversations", %{
        type: "group",
        participant_ids: ["user_b"]
      })

      assert conn.status == 422
    end
  end

  describe "GET /conversations" do
    test "lists conversations for authenticated user", %{conn: conn} do
      post(conn, "/conversations", %{type: "dm", participant_ids: ["user_b"]})

      conn2 = conn_for("test_user_b")
      post(conn2, "/conversations", %{type: "dm", participant_ids: ["user_c"]})

      auth_conn =
        build_conn()
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> Plug.Conn.put_req_header("x-test-user-id", "test_user_a")
        |> Plug.Conn.put_req_header("x-test-name", "Test User A")

      conn3 = get(auth_conn, "/conversations")
      data = json_response(conn3, 200)["data"]
      assert length(data) >= 1
    end
  end

  describe "GET /conversations/:id" do
    test "returns conversation for participant", %{conn: conn} do
      conn = post(conn, "/conversations", %{type: "dm", participant_ids: ["user_b"]})
      conv = json_response(conn, 201)["data"]

      # Rebuild conn with auth headers (previous conn was recycled)
      auth_conn =
        build_conn()
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> Plug.Conn.put_req_header("x-test-user-id", "test_user_a")
        |> Plug.Conn.put_req_header("x-test-name", "Test User A")

      conn2 = get(auth_conn, "/conversations/#{conv["id"]}")
      assert conn2.status == 200
      data = json_response(conn2, 200)["data"]
      assert data["id"] == conv["id"]
    end

    test "returns 403 for non-participant", %{conn: conn} do
      conn_b = conn_for("test_user_b")
      conn_b = post(conn_b, "/conversations", %{type: "dm", participant_ids: ["user_c"]})
      conv = json_response(conn_b, 201)["data"]

      conn = get(conn, "/conversations/#{conv["id"]}")
      assert conn.status == 403
    end
  end
end
