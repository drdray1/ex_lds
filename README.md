# ex_lds

An Elixir client for [churchofjesuschrist.org](https://www.churchofjesuschrist.org)
Leader and Clerk Resources (LCR). A member logs in with their **own**
credentials and reads their **own** unit's directory — the same data a ward
leader can export by hand from the website.

Ported from the Python `church_of_jesus_christ_api` client.

## Usage

```elixir
{:ok, session} = ExLds.login("username", "password")

{:ok, members} = ExLds.member_list(session)
# => [%ExLds.Member{first_name: "Lauryn", last_name: "Meacham",
#                   phone: "8016823316", birthday: ~D[1999-08-02], ...}, ...]

ExLds.user(session)          # the logged-in member's profile
ExLds.birthdays(session)     # the unit birthday report (raw JSON)
```

`ExLds.Member` normalizes each record to `first_name`, `last_name`, `phone`,
`birthday` (a `Date`, or `nil` with `birth_month`/`birth_day` when the source
omits the year), `email`, `person_uuid`, and `moved_out`.

## Login flow

The site uses an Okta Identity Engine password flow. `login/3` walks it:
fetch the state token from the login page, `introspect`, `identify` (username),
`challenge/answer` (password), then exchange the success redirect for the
`oauth_id_token` bearer cookie used on the data endpoints.

**Two-factor authentication is not supported** by this password-only flow;
`login/3` returns `{:error, :invalid_credentials}` for such accounts.

## Testing

`login/3`, `member_list/2`, and `birthdays/2` accept a trailing keyword list
merged into every Req request, so tests inject a `plug:` stub instead of the
network. See `test/support/fake_church.ex`.

## License

MIT
