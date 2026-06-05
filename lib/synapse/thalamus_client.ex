defmodule Synapse.ThalamusClient do
  @moduledoc """
  Client for Thalamus authentication and user resolution.

  Responsibilities:
  - Validate JWT tokens against Thalamus JWKS
  - Resolve @username mentions to user records
  """

  require Logger

  @doc """
  Verifies a JWT token against Thalamus JWKS endpoint.

  Returns {:ok, claims} or {:error, reason}.
  """
  def verify_jwt(token) when is_binary(token) do
    jwks_url = jwks_url()

    with {:ok, jwks} <- fetch_jwks(jwks_url),
         {:ok, signer} <- build_signer(jwks, token),
         {:ok, claims} <- Joken.verify_and_validate(%{}, token, signer) do
      {:ok, claims}
    else
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  @doc """
  Resolves a list of usernames to user records from Thalamus.

  Returns list of maps with :id, :name, :is_agent.
  """
  def resolve_users(usernames) when is_list(usernames) and usernames != [] do
    base_url = api_url()

    results =
      Task.async_stream(usernames, fn username ->
        case Req.get("#{base_url}/api/users?username=#{URI.encode(username)}",
               headers: [{"accept", "application/json"}]) do
          {:ok, %{status: 200, body: %{"data" => [user | _]}}} ->
            {:ok, %{
              id: user["id"],
              name: user["name"],
              is_agent: user["is_agent"] || false
            }}

          {:ok, %{status: 200, body: %{"data" => []}}} ->
            Logger.warning("[ThalamusClient] User '#{username}' not found")
            :not_found

          error ->
            Logger.error("[ThalamusClient] Error resolving '#{username}': #{inspect(error)}")
            :error
        end
      end, timeout: 10_000, on_timeout: :kill_task)
      |> Enum.to_list()

    results
    |> Enum.filter(fn {:ok, result} -> result != :not_found and result != :error end)
    |> Enum.map(fn {:ok, user} -> user end)
  end

  def resolve_users(_), do: []

  # ── Private ──

  defp jwks_url do
    Application.get_env(:synapse, :thalamus_jwks_url) ||
      System.get_env("THALAMUS_JWKS_URL") ||
      "http://thalamus:4000/.well-known/jwks.json"
  end

  defp api_url do
    Application.get_env(:synapse, :thalamus_api_url) ||
      System.get_env("THALAMUS_API_URL") ||
      "http://thalamus:4000"
  end

  defp fetch_jwks(url) do
    case Req.get(url, receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:error, reason} -> {:error, "Failed to fetch JWKS: #{inspect(reason)}"}
      {:ok, %{status: s}} -> {:error, "JWKS fetch failed: status #{s}"}
    end
  end

  defp build_signer(jwks, token) do
    [header_b64 | _] = String.split(token, ".")
    {:ok, header_json} = Base.url_decode64(header_b64, padding: false)
    header = Jason.decode!(header_json)
    keys = jwks["keys"] || []
    kid = header["kid"]
    alg = header["alg"] || "RS256"
    key = if kid, do: Enum.find(keys, fn k -> k["kid"] == kid end), else: List.first(keys)

    if key do
      pem = jwk_to_pem(key)
      {:ok, Joken.Signer.create(alg, %{"pem" => pem})}
    else
      {:error, "No matching key in JWKS"}
    end
  end

  defp jwk_to_pem(%{"n" => n_b64, "e" => e_b64, "kty" => "RSA"}) do
    n = :binary.decode_unsigned(Base.url_decode64!(n_b64, padding: false))
    e = :binary.decode_unsigned(Base.url_decode64!(e_b64, padding: false))
    rsa_key = {:RSAPublicKey, n, e}
    pem_entry = :public_key.pem_entry_encode(:RSAPublicKey, rsa_key)
    :public_key.pem_encode([pem_entry])
  end
end
