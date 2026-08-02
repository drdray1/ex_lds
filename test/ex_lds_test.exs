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
      assert {:ok, [split_name, list_name]} = ExLds.member_list(session)

      assert %Member{
               person_uuid: "uuid-1",
               first_name: "Testina",
               last_name: "Fakerson",
               phone: "5555550101",
               birthday: ~D[1999-08-02],
               birth_month: 8,
               birth_day: 2,
               email: "testina@example.com",
               moved_out: false
             } = split_name

      # "Last, First" fallback + phones[] fallback + year-less birthday + moved-out.
      assert list_name.first_name == "Person"
      assert list_name.last_name == "Sample"
      assert list_name.phone == "5555550102"
      assert list_name.birthday == nil
      assert {list_name.birth_month, list_name.birth_day} == {11, 5}
      assert list_name.moved_out == true
    end

    test "an explicit unit with no data returns an empty list", %{session: session} do
      assert {:ok, []} = ExLds.member_list(session, unit: 111)
    end

    test "birthdays/2 returns the raw report and user/1 exposes the profile", %{session: session} do
      assert {:ok, %{"8" => [%{"name" => "Fakerson, Testina"}]}} = ExLds.birthdays(session)
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
