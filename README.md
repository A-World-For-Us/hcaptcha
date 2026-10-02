# Hcaptcha

An Elixir package to add [hCaptcha](https://www.hcaptcha.com/) to Elixir applications: server-side verification and a template that renders the widget.

This is a maintained fork of [sebastiangrebe/hcaptcha](https://github.com/sebastiangrebe/hcaptcha), which is itself a fork of [recaptcha](https://github.com/samueljseay/recaptcha). It is not published on Hex.

## Installation

Add the package to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hcaptcha, github: "A-World-For-Us/hcaptcha", branch: "master"}
  ]
end
```

## Configuration

Read the keys from the environment in `config/runtime.exs`:

```elixir
config :hcaptcha,
  public_key: System.fetch_env!("HCAPTCHA_PUBLIC_KEY"),
  secret: System.fetch_env!("HCAPTCHA_PRIVATE_KEY")
```

All keys are read at runtime. `{:system, "VAR"}` tuples are not supported.

| Key           | Use                                                        | Default                              |
| :------------ | :--------------------------------------------------------- | :----------------------------------- |
| `secret`      | Secret sent by `Hcaptcha.verify/2`                         | none (`verify` returns `{:error, [:missing_input_secret]}`) |
| `public_key`  | Sitekey, read by `Hcaptcha.Template.display/1`             | none                                 |
| `http_client` | Module that implements `Hcaptcha.HttpClient`               | `Hcaptcha.Http`                      |
| `verify_url`  | Siteverify endpoint                                        | `https://api.hcaptcha.com/siteverify` |
| `timeout`     | Default for the `timeout` option of `verify/2`, in ms      | `5000`                               |
| `req_options` | Extra options for `Req.request/1` (proxy, test `plug`)     | `[]`                                 |

The JSON library is Jason, through Req. The `:json_library` option no longer exists.

## Usage

### Render the widget

Use `raw` (from Phoenix.HTML) and `Hcaptcha.Template.display/1`.

Checkbox:

```html
<form method="post" action="/somewhere">
  <%= raw Hcaptcha.Template.display %>
</form>
```

Invisible:

```html
<form method="post" action="/somewhere">
  <%= raw Hcaptcha.Template.display(size: "invisible") %>
</form>
```

The hCaptcha script loads asynchronously. To run code once it has loaded, pass the name of a JavaScript function:

```html
<%= raw Hcaptcha.Template.display(onload: "myOnLoadCallback") %>
```

`display/1` options:

| Option       | Action                                         | Default                  |
| :----------- | :--------------------------------------------- | :----------------------- |
| `public_key` | Sets the `data-sitekey` attribute              | `:public_key` from config |
| `hl`         | Language of the widget                         | `en`                     |
| `onload`     | Name of a JavaScript function called on load   | none                     |
| `callback`   | Name of the JavaScript function called on success | `hcaptchaCallback` when `size` is `"invisible"` |
| `theme`, `type`, `tabindex`, `size`, `badge` | Set the matching `data-*` attributes | none |

### Verify the response

```elixir
def create(conn, params) do
  remote_ip = conn.remote_ip |> :inet.ntoa() |> to_string()

  case Hcaptcha.verify(params["h-captcha-response"], remote_ip: remote_ip) do
    {:ok, %Hcaptcha.Response{}} ->
      create_account(conn, params)

    {:error, [:missing_input_response]} ->
      # No token: the script was blocked or did not run.
      render_error(conn, "Enable JavaScript and reload the page.")

    {:error, _errors} ->
      render_error(conn, "The captcha check failed. Try again.")
  end
end
```

`Hcaptcha.verify/2` sends a `POST` request to the hCaptcha API and returns:

- `{:ok, %Hcaptcha.Response{challenge_ts: timestamp, hostname: host}}` when the token is valid.
- `{:error, errors}` with a list of atoms.

A `nil`, empty or non-string token returns `{:error, [:missing_input_response]}` and sends no request. A token that the API rejects returns `{:error, [:invalid_input_response]}`. This lets you tell a missing token from a bad one.

Options:

| Option      | Action                                                                  | Default                |
| :---------- | :---------------------------------------------------------------------- | :--------------------- |
| `timeout`   | Connect timeout and receive timeout, in ms (see below)                  | `:timeout` from config, else `5000` |
| `secret`    | Secret sent with the request                                            | `:secret` from config  |
| `remote_ip` | The user's IP address, as a string or an `:inet` tuple. Sent as `remoteip` | none                |
| `sitekey`   | The sitekey the token must belong to                                    | none                   |

`timeout` applies to the connection and to each wait for data from the API, so a request can take longer than this value in total. There is no retry.

### Errors

| Error | Cause |
| :---- | :---- |
| `:missing_input_response` | No token given (no request sent), or the API reports it missing |
| `:invalid_input_response` | The API rejected the token |
| `:expired_input_response` | The token expired (120 s by default) |
| `:already_seen_response` | The token was already verified once |
| `:invalid_or_already_seen_response` | Older API code for the two cases above |
| `:missing_input_secret` | No secret configured (no request sent), or the API reports it missing |
| `:invalid_input_secret` | The secret is invalid |
| `:bad_request` | The API reports a malformed request |
| `:missing_remoteip`, `:invalid_remoteip` | Problem with the `remote_ip` option |
| `:not_using_dummy_passcode` | A test sitekey was used with a secret that is not the test secret |
| `:sitekey_secret_mismatch` | The sitekey does not belong to the secret |
| `:unknown_error` | The API sent an error code this library does not know |
| `:challenge_failed` | The API answered `success: false` with no error code |
| `:unexpected_response` | The API answer has no known shape |
| `:invalid_response_body` | The API answer is not a JSON object |
| `:unexpected_status` | HTTP status other than 200, without error codes in the body |
| `:timeout`, `:econnrefused`, ... | Transport failure. The reason comes from Mint |
| `:http_error` | Any other HTTP client failure |
| `:mock_requires_test_secret` | Only from `Hcaptcha.Http.MockClient`, see below |

The list can hold several atoms when the API returns several codes.

## Testing

hCaptcha publishes [test keys](https://docs.hcaptcha.com/#integration-testing-test-keys). `Hcaptcha.TestKeys` has them: `sitekey/0`, `secret/0` and `token/0`. The real API accepts the test token with the test secret.

To run tests without network access, configure the mock client in `config/test.exs`:

```elixir
config :hcaptcha,
  http_client: Hcaptcha.Http.MockClient,
  secret: "0x0000000000000000000000000000000000000000",
  public_key: "10000000-ffff-ffff-ffff-000000000001"
```

```elixir
{:ok, _response} = Hcaptcha.verify(Hcaptcha.TestKeys.token())
{:error, [:invalid_input_response]} = Hcaptcha.verify("anything else")
```

The mock never calls the network. It accepts only the test token and only with the test secret. With any other secret it returns `{:error, [:mock_requires_test_secret]}`, so a mock left in production rejects every user and lets nobody through. The mock sends `{:request_verification, body, options}` to the calling process, so a test can use `assert_received` on the request.

To stub the API itself, use `Req.Test`:

```elixir
config :hcaptcha, req_options: [plug: {Req.Test, Hcaptcha.Http}]
```

```elixir
Req.Test.stub(Hcaptcha.Http, &Req.Test.json(&1, %{"success" => true}))
```

## Contributing

See [CONTRIBUTING.md](https://github.com/A-World-For-Us/hcaptcha/blob/master/CONTRIBUTING.md).

## License

[MIT](https://opensource.org/licenses/MIT)
