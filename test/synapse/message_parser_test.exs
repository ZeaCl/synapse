defmodule Synapse.MessageParserTest do
  use ExUnit.Case, async: true

  alias Synapse.MessageParser

  describe "extract_mentions/1" do
    test "extracts single mention" do
      assert MessageParser.extract_mentions("hola @carlos") == ["carlos"]
    end

    test "extracts multiple mentions" do
      assert MessageParser.extract_mentions("@carlos y @fullstack revisen") == ["carlos", "fullstack"]
    end

    test "returns empty for no mentions" do
      assert MessageParser.extract_mentions("hola mundo") == []
    end

    test "handles nil gracefully" do
      assert MessageParser.extract_mentions(nil) == []
    end

    test "handles empty string" do
      assert MessageParser.extract_mentions("") == []
    end

    test "does not match emails" do
      assert MessageParser.extract_mentions("contacto@example.com") == []
    end

    test "deduplicates mentions" do
      assert MessageParser.extract_mentions("@carlos y @carlos otra vez") == ["carlos"]
    end

    test "handles mentions with dots and hyphens" do
      assert MessageParser.extract_mentions("@user.name y @user-name") == ["user.name", "user-name"]
    end
  end
end
