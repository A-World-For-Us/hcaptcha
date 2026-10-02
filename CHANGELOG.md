# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Changed

- Require Elixir 1.17 or later. CI covers Elixir 1.17 / OTP 27 and Elixir 1.20 / OTP 29.
- Install from Git: `{:hcaptcha, github: "A-World-For-Us/hcaptcha", branch: "master"}`. The package is not published on Hex.
- **Breaking:** HTTP requests use [Req](https://hex.pm/packages/req) instead of HTTPoison. This also removes `hackney` 1.x, which has known security advisories.
- **Breaking:** the default verify URL is the documented `https://api.hcaptcha.com/siteverify`.
- **Breaking:** `Hcaptcha.Http.MockClient` makes no network call. It accepts the hCaptcha test token and `valid_response`, only with the test secret. Every other token returns `:invalid_input_response`. Any other secret, the old reCAPTCHA key included, returns `:mock_requires_test_secret`.
- **Breaking:** `verify/2` sends the IP as `remoteip`, the parameter the API documents. It sent `remote_ip` before, which the API ignored.
- **Breaking:** `verify/2` returns `[:missing_input_secret]` without a request for every client, `MockClient` included. A secret that is not a string counts as missing.
- **Breaking:** `verify/2` raises `ArgumentError` for a bad `:remote_ip`, `:sitekey` or `:timeout` value.
- **Breaking:** the mock returns `:invalid_input_response`. It returned the atom `:"invalid-input-response"`.
- `Hcaptcha.verify/2` returns an error tuple for any API answer, JSON failure or transport failure. It raised a `CaseClauseError` on some of them.
- The `:timeout` option sets the connect timeout and the receive timeout.
- Redirects are not followed, so the secret goes only to the configured URL. A 3xx answer returns `[:unexpected_status]`.
- Requests are never retried.
- Require `req ~> 0.7`.

### Added

- `Hcaptcha.verify/2` returns `{:error, [:missing_input_response]}` for a `nil`, empty or non-string token, without a request. A server can now tell a missing token (script blocked) from an invalid one.
- `:sitekey` option of `verify/2`, and `:remote_ip` as an `:inet` tuple.
- Error atoms: `:expired_input_response`, `:already_seen_response`, `:missing_remoteip`, `:invalid_remoteip`, `:unexpected_response`, `:invalid_response_body`, `:unexpected_status`, `:http_error`, `:mock_requires_test_secret`.
- `Hcaptcha.HttpClient` behaviour, implemented by `Hcaptcha.Http` and `Hcaptcha.Http.MockClient`.
- `Hcaptcha.TestKeys` with the hCaptcha test sitekey, secret and token.
- `Hcaptcha.public_key/0` returns the configured sitekey.
- Config key `:req_options`: transport options for `Req.new/1` (proxy, pool, test `plug`). The library owns `method`, `url`, `body`, `headers`, `retry`, `redirect`, `decode_body`, `into` and `receive_timeout`.

### Removed

- **Breaking:** HTTPoison.
- **Breaking:** `Hcaptcha.Config`.
- **Breaking:** `{:system, "VAR"}` config values. Use `config/runtime.exs`.
- **Breaking:** the `:json_library` compile-time option. `Hcaptcha.Http` decodes the answer with Jason.
- **Breaking:** the reCAPTCHA test secret in the mock.
- **Breaking:** the mock's fall-through to the real API for unknown tokens.
- **Breaking:** the message `{:request_verification, body, options}` the mock sent to the caller.

### Migration

#### Mock secret

The only change a consumer must make is the secret. `valid_response` and `invalid_response` still work.

Before:

```elixir
config :hcaptcha,
  http_client: Hcaptcha.Http.MockClient,
  secret: "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe"
```

After:

```elixir
config :hcaptcha,
  http_client: Hcaptcha.Http.MockClient,
  secret: "0x0000000000000000000000000000000000000000"
```

The matching sitekey is `Hcaptcha.TestKeys.sitekey()`. Dev defaults such as `secret: System.get_env("HCAPTCHA_PRIVATE_KEY", "6LeIx...")` need the test secret too.

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

#### `Hcaptcha.Config`

Before:

```elixir
Hcaptcha.Config.get_env(:hcaptcha, :public_key)
Hcaptcha.Config.get_env(:hcaptcha, :other_key)
```

After:

```elixir
Hcaptcha.public_key()
Application.get_env(:hcaptcha, :other_key)
```

#### HTTPoison

Remove `config :hcaptcha, :json_library, ...`. To set a proxy or other transport options, use `config :hcaptcha, req_options: [...]`. In tests, `config :hcaptcha, req_options: [plug: {Req.Test, Hcaptcha.Http}]` and `Req.Test.stub(Hcaptcha.Http, fun)` replace any HTTPoison mock.

A custom `:http_client` module should declare `@behaviour Hcaptcha.HttpClient`. Its callback is unchanged: `request_verification(body, options)`.

#### Mock request message

To check the request, stub the API with `Req.Test` (`config :hcaptcha, req_options: [plug: {Req.Test, Hcaptcha.Http}]`, and `{:plug, "~> 1.16", only: :test}` in your dependencies) and read the body in the stub. Or write a test client with `@behaviour Hcaptcha.HttpClient` that sends the message.

#### Error atoms

Handle these in `{:error, errors}` clauses, or match on `[:missing_input_response]` first. The `Hcaptcha` module documentation lists them.

## 0.1.0

State of the fork at the time it was taken from [sebastiangrebe/hcaptcha](https://github.com/sebastiangrebe/hcaptcha).

- `Hcaptcha.verify/2` checks a response token against the hCaptcha API with HTTPoison.
- `Hcaptcha.Template.display/1` renders the widget script and container, checkbox or invisible.
- `Hcaptcha.Http.MockClient` for tests without network access.
- Keys read from application config or from environment variables with `{:system, "VAR"}`.
