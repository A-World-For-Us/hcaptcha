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
| `req_options` | Transport options passed to `Req.new/1` (proxy, pool, test `plug`) | `[]`                                 |

`Hcaptcha.Http` decodes the answer with Jason. The `:json_library` option no longer exists.

`req_options` can set transport options such as `connect_options` (proxy), `finch` (pool), `adapter` and `plug`. The library owns `method`, `url`, `body`, `headers`, `retry`, `redirect`, `decode_body`, `into` and `receive_timeout`; your values for those are ignored. Requests are never retried and redirects are not followed.

## Usage

### Render the widget

`Hcaptcha.Template.display/1` returns the widget HTML for a form rendered by a controller. Wrap it with `raw`.

Checkbox:

```html
<form method="post" action="/somewhere">
  <%= raw Hcaptcha.Template.display %>
</form>
```

Invisible. The challenge runs when this form is submitted, and other forms on the page are not touched:

```html
<form method="post" action="/somewhere">
  <%= raw Hcaptcha.Template.display(size: "invisible") %>
</form>
```

Several widgets can share a page. If the hCaptcha script does not load, or the challenge neither answers nor opens within 10 seconds, an invisible form is sent without a token, and `Hcaptcha.verify/2` returns `:missing_input_response`. Do not load `api.js` yourself on these pages.

| Option       | Use                                                     | Default                   |
| :----------- | :------------------------------------------------------ | :------------------------ |
| `public_key` | Sitekey                                                 | `:public_key` from config |
| `hl`         | Widget language, set by the first widget on the page    | detected by hCaptcha      |
| `onload`     | Global JavaScript function called when the API is ready, set by the first widget on the page | none |
| `callback`   | Global JavaScript function called with the token        | none                      |
| `class`      | CSS class of the container                              | none                      |
| `nonce`      | CSP nonce for the scripts                               | none                      |
| `theme`, `type`, `tabindex`, `size`, `badge` | hCaptcha widget settings | none                |

### Content Security Policy

hCaptcha [needs these directives](https://docs.hcaptcha.com/#content-security-policy-settings):

```text
script-src  https://hcaptcha.com https://*.hcaptcha.com
frame-src   https://hcaptcha.com https://*.hcaptcha.com
style-src   https://hcaptcha.com https://*.hcaptcha.com
connect-src https://hcaptcha.com https://*.hcaptcha.com
```

With a nonce policy, pass the nonce to `display/1`:

```elixir
# router.ex
plug :put_csp_nonce

defp put_csp_nonce(conn, _opts) do
  nonce = 16 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)

  conn
  |> assign(:csp_nonce, nonce)
  |> put_resp_header(
    "content-security-policy",
    "script-src 'nonce-#{nonce}' 'strict-dynamic' https://hcaptcha.com https://*.hcaptcha.com; " <>
      "frame-src https://hcaptcha.com https://*.hcaptcha.com; " <>
      "style-src 'self' https://hcaptcha.com https://*.hcaptcha.com; " <>
      "connect-src 'self' https://hcaptcha.com https://*.hcaptcha.com"
  )
end
```

```html
<%= raw Hcaptcha.Template.display(size: "invisible", nonce: @csp_nonce) %>
```

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

A `nil`, empty or non-string token returns `{:error, [:missing_input_response]}` and sends no request. A missing or non-string secret returns `{:error, [:missing_input_secret]}` and sends no request, with every client. A token that the API refuses returns `{:error, [:invalid_input_response]}`, `[:expired_input_response]`, `[:already_seen_response]` or `[:sitekey_secret_mismatch]`. This lets you tell a missing token from a bad one.

A bad option value (`remote_ip: {1, 2}`, a `sitekey` that is not a string, a negative `timeout`) is a programming error and raises `ArgumentError`.

Options:

| Option      | Action                                                                  | Default                |
| :---------- | :---------------------------------------------------------------------- | :--------------------- |
| `timeout`   | Connect timeout and receive timeout, in ms (see below)                  | `:timeout` from config, else `5000` |
| `secret`    | Secret sent with the request. Takes precedence over the config, with the mock too | `:secret` from config  |
| `remote_ip` | The user's IP address, as a string or an `:inet` tuple. Sent as `remoteip` | none                |
| `sitekey`   | The sitekey the token must belong to                                    | none                   |

`timeout` applies to the connection and to each wait for data from the API, so a request can take longer than this value in total. A failed request is not retried.

### Errors

`verify/2` returns `{:error, atoms}`. The list can hold several atoms when the API returns several codes. Match `:missing_input_response` first to tell a missing token (the widget script was blocked) from a bad one:

```elixir
case Hcaptcha.verify(token) do
  {:ok, _response} -> :ok
  {:error, [:missing_input_response]} -> :no_token
  {:error, errors} -> {:rejected, errors}
end
```

hCaptcha error codes become atoms: `"invalid-input-response"` is `:invalid_input_response`. See the [hCaptcha error codes](https://docs.hcaptcha.com/#siteverify-error-codes-table) and the moduledoc of `Hcaptcha` ([`lib/hcaptcha.ex`](lib/hcaptcha.ex)) for the atoms the library adds.

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

The mock never calls the network. With the test secret it accepts the test token and `valid_response`. Every other token, `invalid_response` included, returns `:invalid_input_response`. With any other secret it returns `{:error, [:mock_requires_test_secret]}`, so a mock left in production rejects every user and lets nobody through. The mock records nothing and sends no message. To check the request body, stub the API with `Req.Test` (below).

To stub the API itself, use `Req.Test`. It needs `{:plug, "~> 1.16", only: :test}` in your own dependencies:

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
