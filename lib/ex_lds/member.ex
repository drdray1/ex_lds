defmodule ExLds.Member do
  @moduledoc """
  A ward member normalized from the LCR member-list JSON down to the fields a
  birthday app cares about. `birthday` is a `Date` (year may be absent from
  the source, in which case it is `nil` and only `birth_month`/`birth_day`
  are set).
  """

  defstruct [
    :person_uuid,
    :first_name,
    :last_name,
    :phone,
    :birthday,
    :birth_month,
    :birth_day,
    :email,
    :moved_out
  ]

  @type t :: %__MODULE__{}

  @doc "Builds a Member from one LCR member-list record."
  def from_json(%{} = record) do
    {first, last} = names(record)
    {date, month, day} = birth(record["birth"])

    %__MODULE__{
      person_uuid: record["personUuid"] || record["uuid"],
      first_name: first,
      last_name: last,
      phone: phone(record),
      birthday: date,
      birth_month: month,
      birth_day: day,
      email: record["email"],
      moved_out: not is_nil(record["movedOut"])
    }
  end

  # Prefer the split preferred-name fields; fall back to splitting "Last, First".
  defp names(record) do
    given = record["nameGivenPreferredLocal"]
    family = record["nameFamilyPreferredLocal"]

    cond do
      is_binary(given) or is_binary(family) ->
        {given, family}

      is_binary(record["nameListPreferredLocal"]) ->
        case String.split(record["nameListPreferredLocal"], ",", parts: 2) do
          [last, first] -> {String.trim(first), String.trim(last)}
          [only] -> {String.trim(only), nil}
        end

      true ->
        {nil, nil}
    end
  end

  defp phone(record) do
    cond do
      is_binary(record["phoneNumber"]) and record["phoneNumber"] != "" ->
        record["phoneNumber"]

      is_list(record["phones"]) ->
        record["phones"]
        |> Enum.map(& &1["number"])
        |> Enum.find(&(is_binary(&1) and &1 != ""))

      true ->
        nil
    end
  end

  # `birth` looks like:
  #   %{"date" => %{"date" => "1999-08-02"}, "monthDay" => %{"date" => "0000-08-02"}}
  # Some records omit the year (privacy), leaving only monthDay.
  defp birth(nil), do: {nil, nil, nil}

  defp birth(%{} = birth) do
    full = get_in(birth, ["date", "date"])
    month_day = get_in(birth, ["monthDay", "date"])

    cond do
      is_binary(full) ->
        case Date.from_iso8601(full) do
          {:ok, date} -> {date, date.month, date.day}
          _ -> month_day_only(month_day)
        end

      true ->
        month_day_only(month_day)
    end
  end

  # "0000-08-02" → {nil, 8, 2}
  defp month_day_only(nil), do: {nil, nil, nil}

  defp month_day_only(month_day) do
    case String.split(month_day, "-") do
      [_year, m, d] -> {nil, String.to_integer(m), String.to_integer(d)}
      _ -> {nil, nil, nil}
    end
  end
end
