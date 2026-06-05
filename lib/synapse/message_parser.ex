defmodule Synapse.MessageParser do
  @moduledoc """
  Parses message content to extract @mentions and other metadata.
  """

  @mention_regex ~r/(?:^|\s)@(\w[\w.-]*)/

  @doc """
  Extracts @mention usernames from message content.

  ## Examples

      iex> Synapse.MessageParser.extract_mentions("hola @carlos mirá esto")
      ["carlos"]

      iex> Synapse.MessageParser.extract_mentions("@carlos y @fullstack revisen")
      ["carlos", "fullstack"]

      iex> Synapse.MessageParser.extract_mentions("sin menciones")
      []

      iex> Synapse.MessageParser.extract_mentions("email@example.com no es mención")
      []
  """
  def extract_mentions(content) when is_binary(content) do
    @mention_regex
    |> Regex.scan(content)
    |> Enum.map(fn [_, username] -> username end)
    |> Enum.uniq()
  end

  def extract_mentions(_), do: []
end
