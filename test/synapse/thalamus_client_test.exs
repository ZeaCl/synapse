defmodule Synapse.ThalamusClientTest do
  use ExUnit.Case, async: false

  alias Synapse.ThalamusClient

  setup do
    bypass = Bypass.open()
    Process.sleep(50)
    url = "http://localhost:#{bypass.port}"
    Application.put_env(:synapse, :thalamus_api_url, url)

    on_exit(fn ->
      Application.delete_env(:synapse, :thalamus_api_url)
    end)

    {:ok, bypass: bypass, url: url}
  end

  describe "resolve_users/1" do
    test "resolves a single user", %{bypass: bypass} do
      Bypass.stub(bypass, fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{
          data: [%{"id" => "user_1", "name" => "Carlos", "is_agent" => false}]
        }))
      end)

      users = ThalamusClient.resolve_users(["carlos"])
      assert length(users) == 1
      assert hd(users).id == "user_1"
      assert hd(users).name == "Carlos"
      refute hd(users).is_agent
    end

    test "resolves multiple users in parallel", %{bypass: bypass} do
      Bypass.stub(bypass, fn conn ->
        username = conn.query_string |> URI.decode_query() |> Map.get("username", "")
        Plug.Conn.resp(conn, 200, Jason.encode!(%{
          data: [%{"id" => "#{username}_id", "name" => username, "is_agent" => String.contains?(username, "bot")}]
        }))
      end)

      users = ThalamusClient.resolve_users(["carlos", "fullstack_bot"])
      assert length(users) == 2
      names = Enum.map(users, & &1.name)
      assert "carlos" in names
      assert "fullstack_bot" in names
    end

    test "skips not-found users silently", %{bypass: bypass} do
      Bypass.stub(bypass, fn conn ->
        username = conn.query_string |> URI.decode_query() |> Map.get("username", "")

        if username == "nonexistent" do
          Plug.Conn.resp(conn, 200, Jason.encode!(%{data: []}))
        else
          Plug.Conn.resp(conn, 200, Jason.encode!(%{
            data: [%{"id" => "ok_id", "name" => username, "is_agent" => false}]
          }))
        end
      end)

      users = ThalamusClient.resolve_users(["nonexistent", "ok"])
      assert length(users) == 1
      assert hd(users).name == "ok"
    end

    test "returns empty list for empty input" do
      assert ThalamusClient.resolve_users([]) == []
    end

    test "returns empty list for nil input" do
      assert ThalamusClient.resolve_users(nil) == []
    end
  end
end
