# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

This release changes the configuration and the test mock. Read the migration notes below before you upgrade.

The library now needs Elixir 1.17 or later. Install it from Git with `{:hcaptcha, github: "A-World-For-Us/hcaptcha", branch: "master"}`: it is not published on Hex.

### Verification

`Hcaptcha.verify/2` no longer calls the API when the token is `nil` or empty. It returns `{:error, [:missing_input_response]}`, so a server can tell a blocked widget script from a bad token. With no secret configured, it returns `{:error, [:missing_input_secret]}`, also without a request.

Every API answer, JSON failure and network failure now gives an error tuple. Before, some of them raised a `CaseClauseError`. A bad option value, such as a `:remote_ip` that is not an IP, raises `ArgumentError`. The `Hcaptcha` module doc lists every error atom.

The IP is now sent as `remoteip`, the name the API reads. Before, the API ignored it. `:remote_ip` also accepts an `:inet` tuple, such as `conn.remote_ip`, and the new `:sitekey` option checks that the token was issued for that sitekey.

### HTTP client

Requests go through [Req](https://hex.pm/packages/req) (`~> 0.7`) instead of HTTPoison, which also removes `hackney` 1.x and its security advisories. The default URL is the documented `https://api.hcaptcha.com/siteverify`. Redirects are not followed and each request is sent once, so the secret goes only to the configured URL. `:timeout` sets both the connect and the receive timeout.

Transport options, such as a proxy, a connection pool or a test plug, go in the new `:req_options` key. A custom client implements the new `Hcaptcha.HttpClient` behaviour. The `:json_library` option is gone: Jason decodes the answer.

### Test mock

`Hcaptcha.Http.MockClient` never calls the network. Before, it sent every unknown token to the real API. It accepts the hCaptcha test token and `valid_response`, and only with the hCaptcha test secret. Other tokens return `:invalid_input_response` (it was `:"invalid-input-response"`). Any other secret, the old reCAPTCHA key included, returns `:mock_requires_test_secret`, so a mock left in production by mistake lets nobody through. The mock no longer sends `{:request_verification, body, options}` to the calling process.

`Hcaptcha.TestKeys` gives the hCaptcha test sitekey, secret and token.

### Configuration

`{:system, "VAR"}` values are no longer read: set the keys in `config/runtime.exs`. `Hcaptcha.Config` is removed. Read the sitekey with the new `Hcaptcha.public_key/0`.

### Migration

#### Mock secret

This is the only change the mock needs. `valid_response` and `invalid_response` still work.

```elixir
# Before
config :hcaptcha,
  http_client: Hcaptcha.Http.MockClient,
  secret: "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe"

# After
config :hcaptcha,
  http_client: Hcaptcha.Http.MockClient,
  secret: "0x0000000000000000000000000000000000000000"
```

Dev defaults such as `System.get_env("HCAPTCHA_PRIVATE_KEY", "6LeIx...")` need the test secret too. The matching sitekey is `Hcaptcha.TestKeys.sitekey()`.

#### `{:system, "VAR"}`

```elixir
# Before, in config/config.exs
config :hcaptcha,
  public_key: {:system, "HCAPTCHA_PUBLIC_KEY"},
  secret: {:system, "HCAPTCHA_PRIVATE_KEY"}

# After, in config/runtime.exs
config :hcaptcha,
  public_key: System.fetch_env!("HCAPTCHA_PUBLIC_KEY"),
  secret: System.fetch_env!("HCAPTCHA_PRIVATE_KEY")
```

#### `Hcaptcha.Config`

```elixir
# Before
Hcaptcha.Config.get_env(:hcaptcha, :public_key)
Hcaptcha.Config.get_env(:hcaptcha, :other_key)

# After
Hcaptcha.public_key()
Application.get_env(:hcaptcha, :other_key)
```

#### HTTPoison and request checks in tests

Remove `config :hcaptcha, :json_library, ...`. A custom `:http_client` module needs `@behaviour Hcaptcha.HttpClient`; its callback is still `request_verification(body, options)`.

To check the request in a test, stub the API with `Req.Test`: set `config :hcaptcha, req_options: [plug: {Req.Test, Hcaptcha.Http}]`, add `{:plug, "~> 1.16", only: :test}` to your dependencies, and read the body in `Req.Test.stub(Hcaptcha.Http, fun)`.

## 0.1.0

State of the fork at the time it was taken from [sebastiangrebe/hcaptcha](https://github.com/sebastiangrebe/hcaptcha).

- `Hcaptcha.verify/2` checks a response token against the hCaptcha API with HTTPoison.
- `Hcaptcha.Template.display/1` renders the widget script and container, checkbox or invisible.
- `Hcaptcha.Http.MockClient` for tests without network access.
- Keys read from application config or from environment variables with `{:system, "VAR"}`.
