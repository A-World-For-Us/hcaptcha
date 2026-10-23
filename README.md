# Hcaptcha

An Elixir package to add [hCaptcha](https://www.hcaptcha.com/) to Elixir applications: server-side verification, a template for controller forms, and a LiveView component with a JavaScript hook.

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
| `public_key`  | Sitekey, read by `Hcaptcha.Template.display/1` and `Hcaptcha.Components.hcaptcha/1` | none                                 |
| `http_client` | Module that implements `Hcaptcha.HttpClient`               | `Hcaptcha.Http`                      |
| `verify_url`  | Siteverify endpoint                                        | `https://api.hcaptcha.com/siteverify` |
| `timeout`     | Default for the `timeout` option of `verify/2`, in ms      | `5000`                               |
| `req_options` | Transport options passed to `Req.new/1` (proxy, pool, test `plug`) | `[]`                                 |

`Hcaptcha.Http` decodes the answer with Jason. The `:json_library` option no longer exists.

`req_options` can set transport options such as `connect_options` (proxy), `finch` (pool), `adapter` and `plug`. The library owns `method`, `url`, `body`, `headers`, `retry`, `redirect`, `decode_body`, `into` and `receive_timeout`; your values for those are ignored. Requests are never retried and redirects are not followed.

## Usage

### Render the widget

`Hcaptcha.Template.display/1` returns the widget HTML for a form rendered by a controller. In a HEEx template, pass it to `raw/1`.

Checkbox:

```heex
<form method="post" action="/somewhere">
  {Hcaptcha.Template.display() |> raw()}
</form>
```

Invisible. The challenge runs when this form is submitted, and other forms on the page are not touched:

```heex
<form method="post" action="/somewhere">
  {Hcaptcha.Template.display(size: "invisible") |> raw()}
</form>
```

Several widgets can share a page. If the hCaptcha script does not load within 10 seconds, or the challenge neither answers nor opens within 20 seconds, an invisible form is sent without a token, and `Hcaptcha.verify/2` returns `:missing_input_response`. Use one widget per form. Do not load `api.js` yourself on these pages. The listener runs in the capture phase on the form and stops the first, intercepted submit there: bubbling listeners on the form see only the final submit, while capture listeners on `document` or `window` see every attempt.

| Option       | Use                                                     | Default                   |
| :----------- | :------------------------------------------------------ | :------------------------ |
| `public_key` | Sitekey                                                 | `:public_key` from config |
| `hl`         | Widget language, set by the first widget on the page    | detected by hCaptcha      |
| `onload`     | Global JavaScript function called when the API is ready, set by the first widget on the page | none |
| `callback`   | Global JavaScript function called with the token        | none                      |
| `class`      | CSS class of the container                              | none                      |
| `nonce`      | CSP nonce for the scripts                               | none                      |
| `theme`, `type`, `tabindex`, `size`, `badge` | hCaptcha widget settings | none                |

### LiveView

`Hcaptcha.Components.hcaptcha/1` and a JavaScript hook cover LiveView forms with `phx-submit`. Do not use the template and the component on one page: each loads the hCaptcha script on its own.

The component needs `phoenix_live_view` (1.1 or later) in your dependencies. If you add it after `hcaptcha` was compiled, run `mix deps.compile hcaptcha --force`.

The hook is in `deps/hcaptcha`. Add `deps` to the esbuild `NODE_PATH`, or add `"hcaptcha": "file:../deps/hcaptcha"` to `assets/package.json`. Register it in `assets/js/app.js`:

```javascript
import { hooks as colocatedHooks } from "phoenix-colocated/my_app";
import { Hcaptcha } from "hcaptcha";

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { ...colocatedHooks, Hcaptcha },
});
```

Put the component inside a form that `POST`s to a controller. Without a sitekey the component raises, so render it under `:if`, or use the test keys:

```heex
<.form for={@form} action={~p"/verify"} method="post" phx-submit="submit">
  <Hcaptcha.Components.hcaptcha :if={Hcaptcha.public_key()} id="captcha" />
  <button type="submit">Log in</button>
</.form>
```

On `submit`, validate, then call `execute/2`, not in the render that adds the widget. The hook runs the challenge and posts the form with `h-captcha-response`, without the name and value of the clicked button:

```elixir
def handle_event("submit", %{"user" => params}, socket) do
  case validate(params) do
    :ok -> {:noreply, Hcaptcha.Components.execute(socket, "captcha")}
    {:error, form} -> {:noreply, assign(socket, form: form)}
  end
end
```

Timeouts work as for the template.

| Attribute | Use | Default |
| :-------- | :-- | :------ |
| `id` | Element id, also the `id` for `execute/2`. Required | none |
| `sitekey` | Sitekey | `:public_key` from config |
| `hl` | Widget language. The first widget on the page sets it | detected by hCaptcha |
| `class` | CSS classes | none |

To disable the captcha, do not render the component and set `phx-trigger-action={@trigger}` on the form from `handle_event/3`. Skip `Hcaptcha.verify/2` in the controller on the same condition.

### Content Security Policy

hCaptcha [needs these directives](https://docs.hcaptcha.com/#content-security-policy-settings):

```text
script-src  https://hcaptcha.com https://*.hcaptcha.com
frame-src   https://hcaptcha.com https://*.hcaptcha.com
style-src   https://hcaptcha.com https://*.hcaptcha.com
connect-src https://hcaptcha.com https://*.hcaptcha.com
```

With a nonce policy, pass the nonce to `display/1`. The LiveView hook reuses the nonce of the page's scripts, which is enough with `'strict-dynamic'`:

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

```heex
{Hcaptcha.Template.display(size: "invisible", nonce: @csp_nonce) |> raw()}
```

Set `@csp_nonce` on your own `<script>` tags too.

### Verify the response

```elixir
def create(conn, params) do
  remote_ip = conn.remote_ip |> :inet.ntoa() |> to_string()

  case Hcaptcha.verify(params["h-captcha-response"], remote_ip: remote_ip) do
    {:ok, %Hcaptcha.Response{}} ->
      create_account(conn, params)

    {:error, [:missing_input_response]} ->
      # No token: the script was blocked or did not run.
      render_error(conn, "The captcha could not run. Reload the page and try again.")

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

To stub the API itself, use `Req.Test`. It needs `{:plug, "~> 1.15", only: :test}` in your own dependencies, unless Phoenix already brings `plug`:

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
