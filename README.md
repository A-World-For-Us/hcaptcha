# Hcaptcha

An Elixir package to add [hCaptcha](https://www.hcaptcha.com/) to Elixir applications: server-side verification and a template that renders the widget.

This is a maintained fork of [sebastiangrebe/hcaptcha](https://github.com/sebastiangrebe/hcaptcha), which is itself a fork of [recaptcha](https://github.com/samueljseay/recaptcha). It is not published on Hex.

## Installation

Add the package to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hcaptcha, github: "A-World-For-Us/hcaptcha", tag: "v0.2.0"}
  ]
end
```

`v0.2.0` is the first release from this fork's new line. Until it is tagged, use `branch: "master"`.

## Configuration

Read the keys from the environment in `config/runtime.exs`:

```elixir
config :hcaptcha,
  public_key: System.fetch_env!("HCAPTCHA_PUBLIC_KEY"),
  secret: System.fetch_env!("HCAPTCHA_PRIVATE_KEY")
```

Other keys:

```elixir
config :hcaptcha, :json_library, Poison
```

`:json_library` defaults to `Jason`.

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
  case Hcaptcha.verify(params["h-captcha-response"]) do
    {:ok, response} -> do_something(response)
    {:error, errors} -> handle_error(errors)
  end
end
```

`Hcaptcha.verify/2` sends a `POST` request to the hCaptcha API and returns:

- `{:ok, %Hcaptcha.Response{challenge_ts: timestamp, hostname: host}}` when the response is valid. See the [API documentation](https://docs.hcaptcha.com/#verify-the-user-response-server-side).
- `{:error, errors}` with a list of atoms. They come from the API [error codes](https://docs.hcaptcha.com/#siteverify-error-codes-table), or are `:challenge_failed` when the request succeeds but the challenge fails.

Options:

| Option      | Action                                | Default                  |
| :---------- | :------------------------------------ | :----------------------- |
| `timeout`   | Time to wait for the API, in ms       | `5000`                   |
| `secret`    | Secret sent with the request          | `:secret` from config    |
| `remote_ip` | The user's IP address                 | none                     |

## Testing

hCaptcha publishes [test keys](https://docs.hcaptcha.com/#integration-testing-test-keys). With the test secret `0x0000000000000000000000000000000000000000`, the API accepts the token `10000000-aaaa-bbbb-cccc-000000000001`. This needs network access.

To test without network access, use the mock client:

```elixir
config :hcaptcha,
  http_client: Hcaptcha.Http.MockClient,
  secret: "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe"
```

```elixir
{:ok, _response} = Hcaptcha.verify("valid_response")
{:error, _errors} = Hcaptcha.verify("invalid_response")
```

The mock client sends any other token to the real API.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](https://opensource.org/licenses/MIT)
