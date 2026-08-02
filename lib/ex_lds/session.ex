defmodule ExLds.Session do
  @moduledoc """
  An authenticated churchofjesuschrist.org session: the bearer token, the
  accumulated cookie jar, the logged-in user's details, and the Req option
  overrides used for testing.
  """

  @enforce_keys [:access_token, :user]
  defstruct access_token: nil,
            cookies: %{},
            user: %{},
            req_options: []

  @type t :: %__MODULE__{
          access_token: String.t(),
          cookies: %{String.t() => String.t()},
          user: map(),
          req_options: keyword()
        }

  @doc "The member's home unit number (the ward), used as the default report scope."
  def home_unit(%__MODULE__{user: user}) do
    case user["homeUnits"] do
      [unit | _] -> unit
      _ -> nil
    end
  end
end
