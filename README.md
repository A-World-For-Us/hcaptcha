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

Use `raw` (from Phoenix.HTML) and `Hcaptcha.Template.display/1`. It returns a string with a container `<div>` and an inline `<script>`.

Checkbox:

```html
<form method="post" action="/somewhere">
  <%= raw Hcaptcha.Template.display %>
</form>
```

Invisible. The challenge runs when the form that contains the widget is submitted. Other forms on the page are not touched:

```html
<form method="post" action="/somewhere">
  <%= raw Hcaptcha.Template.display(size: "invisible") %>
</form>
```

Several widgets can share one page, for example two invisible forms, or one invisible and one checkbox. The page loads the hCaptcha script once. The `hl` option of the first widget sets the language.

If the hCaptcha script fails to load, is not ready within 10 seconds, or cannot render the widget, an invisible form is sent without a token. `Hcaptcha.verify/2` then returns an error for the missing token. A submit made before the script has loaded waits for it. After the challenge, the form is sent again with the token and the clicked button.

The template is for forms rendered by controllers. LiveView `phx-submit` forms are not supported: use the LiveView component and hook instead. Do not load `api.js` yourself on a page that uses `display/1`.

`display/1` options:

| Option       | Action                                         | Default                  |
| :----------- | :--------------------------------------------- | :----------------------- |
| `public_key` | Sets the `data-sitekey` attribute              | `:public_key` from config |
| `hl`         | Language of the widget                         | none, hCaptcha detects the language |
| `onload`     | Name of a global JavaScript function, called once without arguments when the hCaptcha script is ready, however many widgets use it | none |
| `callback`   | Name of a global JavaScript function, called with the token on success. In invisible mode the form is submitted after it returns | none |
| `nonce`      | CSP nonce, set on the inline script and on the script it adds | none |
| `theme`, `type`, `tabindex`, `size`, `badge` | Set the matching `data-*` attributes | none |

Options that are `nil` are left out. All values are HTML-escaped.

### Content Security Policy

hCaptcha [needs these directives](https://docs.hcaptcha.com/#content-security-policy-settings):

```text
script-src  https://hcaptcha.com https://*.hcaptcha.com
frame-src   https://hcaptcha.com https://*.hcaptcha.com
style-src   https://hcaptcha.com https://*.hcaptcha.com
connect-src https://hcaptcha.com https://*.hcaptcha.com
```

If your policy uses nonces, pass the nonce to `display/1`. With `'strict-dynamic'` the inline script is allowed by its nonce, and the hCaptcha script it adds inherits that trust.

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
