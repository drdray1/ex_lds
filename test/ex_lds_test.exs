defmodule ExLdsTest do
  use ExUnit.Case, async: true

  alias ExLds.{FakeChurch, Member, Session}

  @stub [plug: FakeChurch]

  describe "login/3" do
    test "walks the full Okta flow and returns a session" do
      assert {:ok, %Session{} = session} =
               ExLds.login("leader", FakeChurch.valid_password(), @stub)

      assert session.access_token == "bearer-token-xyz"
      assert session.user["homeUnits"] == [123_456]
      assert Session.home_unit(session) == 123_456
      # Cookies from every step are threaded through.
      assert session.cookies["oauth_id_token"] == "bearer-token-xyz"
      assert session.cookies["owp"] == "bearer-token-xyz"
      assert session.cookies["idx"] == "idxcookie"
    end

    test "returns :invalid_credentials on a bad password" do
      assert {:error, :invalid_credentials} = ExLds.login("leader", "wrong", @stub)
    end
  end

  describe "member_list/2" do
    setup do
      {:ok, session} = ExLds.login("leader", FakeChurch.valid_password(), @stub)
      %{session: session}
    end

    test "returns normalized members for the home unit", %{session: session} do
      assert {:ok, [lauryn, ammon]} = ExLds.member_list(session)

      assert %Member{
               person_uuid: "uuid-1",
               first_name: "Lauryn",
               last_name: "Meacham",
               phone: "8016823316",
               birthday: ~D[1999-08-02],
               birth_month: 8,
               birth_day: 2,
               email: "lauryn@example.com",
               moved_out: false
             } = lauryn

      # "Last, First" fallback + phones[] fallback + year-less birthday + moved-out.
      assert ammon.first_name == "Ammon"
      assert ammon.last_name == "Alvarez"
      assert ammon.phone == "3035949703"
      assert ammon.birthday == nil
      assert {ammon.birth_month, ammon.birth_day} == {11, 5}
      assert ammon.moved_out == true
    end

    test "an explicit unit with no data returns an empty list", %{session: session} do
      assert {:ok, []} = ExLds.member_list(session, unit: 111)
    end

    test "birthdays/2 returns the raw report and user/1 exposes the profile", %{session: session} do
      assert {:ok, %{"8" => [%{"name" => "Meacham, Lauryn"}]}} = ExLds.birthdays(session)
      assert ExLds.user(session)["individualId"] == 42
    end

    test "a non-2xx response surfaces an http_error", %{session: session} do
      bad = %{session | access_token: "wrong-token"}
      assert {:error, {:http_error, 401}} = ExLds.member_list(bad)
    end
  end

  describe "Member.from_json/1 edge cases" do
    test "a record with no birth or phone degrades gracefully" do
      member = Member.from_json(%{"personUuid" => "x", "nameListPreferredLocal" => "Solo"})
      assert member.first_name == "Solo"
      assert member.last_name == nil
      assert member.phone == nil
      assert member.birthday == nil
    end
  end
end
