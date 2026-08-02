defmodule ExLds.FakeChurch do
  @moduledoc """
  A `Plug`-style stub of the churchofjesuschrist.org Okta flow and LCR
  endpoints, driven via `Req.Test`. Routes by host + path so tests exercise
  the real multi-step login and cookie threading without the network.
  """

  import Plug.Conn

  @valid_password "correct-horse"

  def valid_password, do: @valid_password

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    route(conn.host, conn.request_path, conn)
  end

  # 1. Login page — embeds the state token in a JSON-ish script blob.
  defp route("www.churchofjesuschrist.org", "/services/platform/v4/login", conn) do
    resp(conn, 200, ~s|<script>var config = {"stateToken":"tok-123"};</script>|)
  end

  # 2. introspect — just needs to set a cookie and 200.
  defp route("id.churchofjesuschrist.org", "/idp/idx/introspect", conn) do
    conn
    |> set_cookie("idx", "idxcookie")
    |> json(200, %{"ok" => true})
  end

  # 3. identify — echoes a state handle.
  defp route("id.churchofjesuschrist.org", "/idp/idx/identify", conn) do
    json(conn, 200, %{"stateHandle" => "handle-456"})
  end

  # 4. challenge/answer — success only when the password matches.
  defp route("id.churchofjesuschrist.org", "/idp/idx/challenge/answer", conn) do
    {:ok, body, conn} = read_body(conn)
    passcode = get_in(Jason.decode!(body), ["credentials", "passcode"])

    if passcode == @valid_password do
      json(conn, 200, %{
        "success" => %{"href" => "https://id.churchofjesuschrist.org/oauth/success"}
      })
    else
      json(conn, 200, %{"messages" => %{"value" => [%{"message" => "bad password"}]}})
    end
  end

  # 5. success href — issues the oauth_id_token cookie.
  defp route("id.churchofjesuschrist.org", "/oauth/success", conn) do
    conn
    |> set_cookie("oauth_id_token", "bearer-token-xyz")
    |> resp(200, "ok")
  end

  # Host warm-ups.
  defp route("lcr.churchofjesuschrist.org", "/", conn), do: resp(conn, 200, "")
  defp route("directory.churchofjesuschrist.org", "/", conn), do: resp(conn, 200, "")

  # User profile — requires the bearer token.
  defp route("directory.churchofjesuschrist.org", "/api/v4/user", conn) do
    if bearer(conn) == "bearer-token-xyz" do
      json(conn, 200, %{
        "homeUnits" => [123_456],
        "parentUnits" => [999],
        "individualId" => 42,
        "uuid" => "user-uuid"
      })
    else
      resp(conn, 401, "unauthorized")
    end
  end

  # Member list — requires bearer + the home unit in the query.
  defp route("lcr.churchofjesuschrist.org", "/api/umlu/report/member-list", conn) do
    cond do
      bearer(conn) != "bearer-token-xyz" -> resp(conn, 401, "unauthorized")
      conn.query_params["unitNumber"] != "123456" -> json(conn, 200, [])
      true -> json(conn, 200, members())
    end
  end

  # Birthday report — bearer + unit gated.
  defp route("lcr.churchofjesuschrist.org", "/api/report/birthday-list/unit/" <> _rest, conn) do
    if bearer(conn) == "bearer-token-xyz" do
      json(conn, 200, %{"8" => [%{"name" => "Meacham, Lauryn"}]})
    else
      resp(conn, 401, "unauthorized")
    end
  end

  defp route(_host, _path, conn), do: resp(conn, 404, "not found")

  defp members do
    [
      %{
        "personUuid" => "uuid-1",
        "nameGivenPreferredLocal" => "Lauryn",
        "nameFamilyPreferredLocal" => "Meacham",
        "phoneNumber" => "8016823316",
        "birth" => %{
          "date" => %{"date" => "1999-08-02"},
          "monthDay" => %{"date" => "0000-08-02"}
        },
        "email" => "lauryn@example.com",
        "movedOut" => nil
      },
      %{
        "personUuid" => "uuid-2",
        "nameListPreferredLocal" => "Alvarez, Ammon",
        "phones" => [%{"number" => "3035949703"}],
        "birth" => %{"monthDay" => %{"date" => "0000-11-05"}},
        "movedOut" => "2024-01-01"
      }
    ]
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> resp(status, Jason.encode!(body))
  end

  # Set the header directly (put_resp_cookie only materializes at send time,
  # which Req's plug adapter may not trigger before reading headers).
  defp set_cookie(conn, name, value) do
    put_resp_header(conn, "set-cookie", "#{name}=#{value}; Path=/")
  end
end
