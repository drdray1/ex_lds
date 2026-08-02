defmodule ExLds do
  @moduledoc """
  Elixir client for churchofjesuschrist.org — logs in with a member's own
  credentials and pulls their ward's data from Leader and Clerk Resources
  (LCR).

  A member (typically a ward leader with LCR access) uses their own
  credentials to read their own unit's directory — the same data they can
  export by hand from the website.

      {:ok, session} = ExLds.login("username", "password")
      {:ok, members} = ExLds.member_list(session)

  Accounts with two-factor authentication enabled are not supported by this
  password-only flow — `login/3` returns `{:error, :invalid_credentials}`.
  """

  alias ExLds.{Auth, Client, Member, Session}

  @member_list_url "https://lcr.churchofjesuschrist.org/api/umlu/report/member-list?unitNumber=%{unit}"
  @birthdays_url "https://lcr.churchofjesuschrist.org/api/report/birthday-list/unit/%{unit}?month=1&months=12"

  @doc """
  Logs in and returns an authenticated session. `req_options` are merged into
  every request (used by tests to inject a stub).
  """
  @spec login(String.t(), String.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def login(username, password, req_options \\ []) do
    Auth.login(username, password, req_options)
  end

  @doc """
  The unit member list as `ExLds.Member` structs. Defaults to the session's
  home unit; pass `unit:` to override.
  """
  @spec member_list(Session.t(), keyword()) :: {:ok, [Member.t()]} | {:error, term()}
  def member_list(%Session{} = session, opts \\ []) do
    unit = Keyword.get(opts, :unit) || Session.home_unit(session)

    with {:ok, records} <- get_json(session, expand(@member_list_url, unit)) do
      {:ok, Enum.map(List.wrap(records), &Member.from_json/1)}
    end
  end

  @doc "The raw birthday report JSON for the unit (grouped by month by the API)."
  @spec birthdays(Session.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def birthdays(%Session{} = session, opts \\ []) do
    unit = Keyword.get(opts, :unit) || Session.home_unit(session)
    get_json(session, expand(@birthdays_url, unit))
  end

  @doc "The logged-in user's profile (home unit, individual id, uuid, name)."
  @spec user(Session.t()) :: map()
  def user(%Session{user: user}), do: user

  defp get_json(%Session{} = session, url) do
    {resp, _cookies} =
      Client.get(url, session.cookies,
        headers: [
          {"accept", "application/json"},
          {"authorization", "Bearer #{session.access_token}"}
        ],
        req_options: session.req_options
      )

    if resp.status in 200..299 do
      {:ok, resp.body}
    else
      {:error, {:http_error, resp.status}}
    end
  end

  defp expand(template, unit), do: String.replace(template, "%{unit}", to_string(unit))
end
