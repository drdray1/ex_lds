defmodule ExLds.Auth do
  @moduledoc """
  The churchofjesuschrist.org login — an Okta Identity Engine (`idp/idx`)
  password flow, ported from the `church_of_jesus_christ_api` Python client:

    1. GET  www…/services/platform/v4/login    → scrape `stateToken` from HTML
    2. POST id…/idp/idx/introspect              → establish idx cookies
    3. POST id…/idp/idx/identify                → send username, get stateHandle
    4. POST id…/idp/idx/challenge/answer        → send password, get success href
    5. GET  success.href                        → sets the `oauth_id_token` cookie

  The `oauth_id_token` cookie is the bearer token for the data APIs. We then
  warm the lcr/directory hosts and fetch the user profile.

  Returns `{:ok, %ExLds.Session{}}` or `{:error, reason}` — notably
  `{:error, :invalid_credentials}` when the password step is rejected.
  """

  alias ExLds.{Client, Session}

  @login_url "https://www.churchofjesuschrist.org/services/platform/v4/login"
  @introspect_url "https://id.churchofjesuschrist.org/idp/idx/introspect"
  @identify_url "https://id.churchofjesuschrist.org/idp/idx/identify"
  @answer_url "https://id.churchofjesuschrist.org/idp/idx/challenge/answer"
  @lcr_url "https://lcr.churchofjesuschrist.org"
  @directory_url "https://directory.churchofjesuschrist.org"
  @user_url "https://directory.churchofjesuschrist.org/api/v4/user"

  @doc false
  def login(username, password, req_options \\ []) do
    with {:ok, state_token, cookies} <- fetch_state_token(req_options),
         {:ok, cookies} <- introspect(state_token, cookies, req_options),
         {:ok, state_handle, cookies} <- identify(username, state_token, cookies, req_options),
         {:ok, success_href, cookies} <- answer(password, state_handle, cookies, req_options),
         {:ok, token, cookies} <- exchange(success_href, cookies, req_options),
         {:ok, cookies} <- warm_hosts(cookies, req_options),
         {:ok, user, cookies} <- fetch_user(token, cookies, req_options) do
      {:ok, %Session{access_token: token, cookies: cookies, user: user, req_options: req_options}}
    end
  end

  defp fetch_state_token(req_options) do
    {resp, cookies} = Client.get(@login_url, %{}, req_options: req_options)

    case Regex.run(~r/"stateToken":"([^"]+)"/, to_string(resp.body)) do
      [_, token] -> {:ok, unescape(token), cookies}
      _ -> {:error, :state_token_not_found}
    end
  end

  defp introspect(state_token, cookies, req_options) do
    {_resp, cookies} =
      Client.post(@introspect_url, cookies,
        json: %{stateToken: state_token},
        req_options: req_options
      )

    {:ok, cookies}
  end

  defp identify(username, state_token, cookies, req_options) do
    {resp, cookies} =
      Client.post(@identify_url, cookies,
        json: %{identifier: username, stateHandle: state_token},
        req_options: req_options
      )

    case resp.body do
      %{"stateHandle" => handle} -> {:ok, handle, cookies}
      _ -> {:error, :identify_failed}
    end
  end

  defp answer(password, state_handle, cookies, req_options) do
    {resp, cookies} =
      Client.post(@answer_url, cookies,
        json: %{credentials: %{passcode: password}, stateHandle: state_handle},
        req_options: req_options
      )

    case resp.body do
      %{"success" => %{"href" => href}} -> {:ok, href, cookies}
      _ -> {:error, :invalid_credentials}
    end
  end

  defp exchange(success_href, cookies, req_options) do
    {_resp, cookies} = Client.get(success_href, cookies, req_options: req_options)

    case Map.get(cookies, "oauth_id_token") do
      nil -> {:error, :token_not_issued}
      token -> {:ok, token, Map.put(cookies, "owp", token)}
    end
  end

  defp warm_hosts(cookies, req_options) do
    {_r1, cookies} = Client.get(@lcr_url, cookies, req_options: req_options)
    {_r2, cookies} = Client.get(@directory_url, cookies, req_options: req_options)
    {:ok, cookies}
  end

  defp fetch_user(token, cookies, req_options) do
    {resp, cookies} =
      Client.get(@user_url, cookies,
        headers: [{"accept", "application/json"}, {"authorization", "Bearer #{token}"}],
        req_options: req_options
      )

    case resp.body do
      %{} = user when map_size(user) > 0 -> {:ok, user, cookies}
      _ -> {:error, :user_fetch_failed}
    end
  end

  # The login HTML is unicode-escaped; decode the token we scraped from it.
  defp unescape(token) do
    Regex.replace(~r/\\u([0-9a-fA-F]{4})/, token, fn _, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end
end
