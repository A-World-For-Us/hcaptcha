# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Changed

- Require Elixir 1.17 or later. CI covers Elixir 1.17 / OTP 27 and Elixir 1.20 / OTP 29.
- Install from Git: `{:hcaptcha, github: "A-World-For-Us/hcaptcha", branch: "master"}`. The package is not published on Hex.
- **Breaking:** HTTP requests use [Req](https://hex.pm/packages/req) instead of HTTPoison. This also removes `hackney` 1.x, which has known security advisories.
- **Breaking:** the default verify URL is the documented `https://api.hcaptcha.com/siteverify`.
- **Breaking:** `Hcaptcha.Http.MockClient` makes no network call and accepts only the hCaptcha test token with the test secret.
- **Breaking:** `{:system, "VAR"}` config values are no longer read. Use `config/runtime.exs`. `Hcaptcha.Config.get_env/3` stays and returns the plain config value.
- **Breaking:** `verify/2` sends the IP as `remoteip`, the parameter the API documents. It sent `remote_ip` before, which the API ignored.
- **Breaking:** the `:json_library` compile-time option is gone. Jason is used through Req.
- `Hcaptcha.verify/2` returns an error tuple for any API answer, JSON failure or transport failure. It raised a `CaseClauseError` on some of them.
- The `:timeout` option sets the connect timeout and the receive timeout.

### Added

- `Hcaptcha.verify/2` returns `{:error, [:missing_input_response]}` for a `nil`, empty or non-string token, without a request. A server can now tell a missing token (script blocked) from an invalid one.
- `Hcaptcha.verify/2` returns `{:error, [:missing_input_secret]}` without a request when no secret is configured.
- `:sitekey` option of `verify/2`, and `:remote_ip` as an `:inet` tuple.
- Error atoms: `:expired_input_response`, `:already_seen_response`, `:missing_remoteip`, `:invalid_remoteip`, `:unexpected_response`, `:invalid_response_body`, `:unexpected_status`, `:http_error`, `:mock_requires_test_secret`.
- `Hcaptcha.HttpClient` behaviour, implemented by `Hcaptcha.Http` and `Hcaptcha.Http.MockClient`.
- `Hcaptcha.TestKeys` with the hCaptcha test sitekey, secret and token.
- Config keys `:timeout`, `:verify_url` and `:req_options`, read at runtime.

### Removed

- HTTPoison, the `{:system, _}` config tuples and the `:json_library` option.
- The mock tokens `valid_response` and `invalid_response`, and the reCAPTCHA test secret in the mock.
- The mock's fall-through to the real API for unknown tokens.

### Migration

#### Mock secret and tokens

Before:

```elixir
config :hcaptcha,
  http_client: Hcaptcha.Http.MockClient,
  secret: "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe"

Hcaptcha.verify("valid_response")
Hcaptcha.verify("invalid_response")
```

After:

```elixir
config :hcaptcha,
  http_client: Hcaptcha.Http.MockClient,
  secret: "0x0000000000000000000000000000000000000000"

Hcaptcha.verify(Hcaptcha.TestKeys.token())
Hcaptcha.verify("any other value")
```

The mock returns `{:error, [:mock_requires_test_secret]}` for any other secret, `nil` included, and for the old reCAPTCHA key. It no longer sends unknown tokens to the real API. An invalid token returns `{:error, [:invalid_input_response]}`. Dev defaults such as `secret: System.get_env("HCAPTCHA_PRIVATE_KEY", "6LeIx...")` must use the test secret above. The matching sitekey is `Hcaptcha.TestKeys.sitekey()`.

#### `{:system, "VAR"}`

Before:

```elixir
config :hcaptcha,
  public_key: {:system, "HCAPTCHA_PUBLIC_KEY"},
  secret: {:system, "HCAPTCHA_PRIVATE_KEY"}
```

After, in `config/runtime.exs`:

```elixir
config :hcaptcha,
  public_key: System.fetch_env!("HCAPTCHA_PUBLIC_KEY"),
  secret: System.fetch_env!("HCAPTCHA_PRIVATE_KEY")
```

The library no longer sets `public_key` or `secret` itself. Without a secret, `verify/2` returns `{:error, [:missing_input_secret]}`.

#### `Hcaptcha.Config`

`Hcaptcha.Config.get_env/3` is unchanged for plain values, for example `Hcaptcha.Config.get_env(:hcaptcha, :public_key)`. It returns a `{:system, _}` tuple as it is, so replace those tuples as above.

#### HTTPoison

The library no longer depends on HTTPoison or `hackney`. Remove `config :hcaptcha, :json_library, ...`. To set a proxy or other transport options, use `config :hcaptcha, req_options: [...]`. In tests, `config :hcaptcha, req_options: [plug: {Req.Test, Hcaptcha.Http}]` and `Req.Test.stub(Hcaptcha.Http, fun)` replace any HTTPoison mock.

A custom `:http_client` module should declare `@behaviour Hcaptcha.HttpClient`. Its callback is unchanged: `request_verification(body, options)`.

#### Error atoms

Handle these in `{:error, errors}` clauses, or match on `[:missing_input_response]` first:

- `[:missing_input_response]` for a missing token. Before, the library sent the request and the API answered the same code.
- `[:invalid_input_response]` is unchanged.
- The mock returned the atom `:"invalid-input-response"`. It now returns `:invalid_input_response`.
- Transport failures still return the reason, for example `[:timeout]`. Other failures are listed in the README.

## 0.1.0

State of the fork at the time it was taken from [sebastiangrebe/hcaptcha](https://github.com/sebastiangrebe/hcaptcha).

- `Hcaptcha.verify/2` checks a response token against the hCaptcha API with HTTPoison.
- `Hcaptcha.Template.display/1` renders the widget script and container, checkbox or invisible.
- `Hcaptcha.Http.MockClient` for tests without network access.
- Keys read from application config or from environment variables with `{:system, "VAR"}`.
