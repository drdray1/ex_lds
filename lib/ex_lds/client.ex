defmodule ExLds.Client do
  @moduledoc """
  A tiny cookie-aware HTTP layer over Req. The church login is a multi-step
  Okta flow whose steps depend on cookies set by earlier steps, and Req does
  not persist cookies across separate requests — so we thread a cookie jar
  (a `name => value` map) through each call manually.

  `req_options` are merged into every request, which lets tests inject a
  `plug:` stub instead of hitting the network.
  """

  @doc """
  Performs a request, returning `{response, updated_cookies}`. Sends the jar
  as a `Cookie` header and merges any `set-cookie` from the response back in.
  """
  def request(method, url, cookies, opts \\ []) do
    {req_options, opts} = Keyword.pop(opts, :req_options, [])

    base =
      [method: method, url: url, headers: cookie_header(cookies), retry: :transient]
      |> Keyword.merge(opts)
      |> Keyword.merge(req_options)

    response = Req.request!(base)
    {response, merge_set_cookie(cookies, response)}
  end

  def get(url, cookies, opts \\ []), do: request(:get, url, cookies, opts)
  def post(url, cookies, opts \\ []), do: request(:post, url, cookies, opts)

  defp cookie_header(cookies) when map_size(cookies) == 0, do: []

  defp cookie_header(cookies) do
    value = Enum.map_join(cookies, "; ", fn {k, v} -> "#{k}=#{v}" end)
    [{"cookie", value}]
  end

  defp merge_set_cookie(cookies, response) do
    response
    |> Req.Response.get_header("set-cookie")
    |> Enum.reduce(cookies, fn set_cookie, acc ->
      case parse_cookie(set_cookie) do
        {name, value} -> Map.put(acc, name, value)
        :skip -> acc
      end
    end)
  end

  # Take the first `name=value` pair before the first `;`; ignore attributes.
  defp parse_cookie(set_cookie) do
    set_cookie
    |> String.split(";", parts: 2)
    |> hd()
    |> String.split("=", parts: 2)
    |> case do
      [name, value] -> {String.trim(name), String.trim(value)}
      _ -> :skip
    end
  end
end
