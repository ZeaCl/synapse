defmodule Synapse.DebugTest do
  use ExUnit.Case, async: false

  test "application env works" do
    Application.put_env(:synapse, :thalamus_api_url, "http://test:9999")
    url = Application.get_env(:synapse, :thalamus_api_url)
    assert url == "http://test:9999"
    Application.delete_env(:synapse, :thalamus_api_url)
  end
end
