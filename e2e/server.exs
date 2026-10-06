Mix.install(
  [
    {:hcaptcha, path: Path.expand("..", __DIR__)},
    {:plug, "~> 1.15"},
    {:bandit, "~> 1.5"}
  ],
  config: [
    hcaptcha: [
      secret: "0x0000000000000000000000000000000000000000",
      public_key: "10000000-ffff-ffff-ffff-000000000001"
    ]
  ]
)

defmodule E2E.Router do
  use Plug.Router

  plug(:csp)
  plug(:match)
  plug(Plug.Parsers, parsers: [:urlencoded])
  plug(:dispatch)

  get("/health", do: send_resp(conn, 200, "up"))
  get("/favicon.ico", do: send_resp(conn, 204, ""))

  get "/invisible" do
    widget = Hcaptcha.Template.display(size: "invisible", nonce: conn.assigns.csp_nonce)

    page(conn, "Invisible", """
    <form id="signup" action="/verify" method="post">
      <input type="text" name="name" id="name" value="x" />
      #{widget}
      <button type="submit" id="submit-button">Sign up</button>
    </form>
    <form id="other" action="/other" method="post">
      <button type="submit" id="other-button">Other</button>
    </form>
    """)
  end

  get "/checkbox" do
    widget = Hcaptcha.Template.display(nonce: conn.assigns.csp_nonce)

    page(conn, "Checkbox", """
    <form id="signup" action="/verify" method="post">
      #{widget}
      <button type="submit" id="submit-button">Sign up</button>
    </form>
    """)
  end

  post "/verify" do
    result =
      case Hcaptcha.verify(conn.params["h-captcha-response"]) do
        {:ok, _response} -> "ok"
        {:error, [error]} -> Atom.to_string(error)
        {:error, errors} -> inspect(errors)
      end

    text(conn, result)
  end

  post("/other", do: text(conn, "other-ok"))

  match(_, do: send_resp(conn, 404, "not found"))

  def csp(conn, _opts) do
    nonce = 16 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
    hcaptcha = "https://hcaptcha.com https://*.hcaptcha.com"

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header(
      "content-security-policy",
      "script-src 'nonce-#{nonce}' 'strict-dynamic' #{hcaptcha}; " <>
        "frame-src #{hcaptcha}; " <>
        "style-src 'self' #{hcaptcha}; " <>
        "connect-src 'self' #{hcaptcha}"
    )
  end

  defp page(conn, title, body) do
    html = """
    <!DOCTYPE html>
    <html lang="en">
      <head><meta charset="utf-8" /><title>hcaptcha e2e #{title}</title></head>
      <body>
        <h1>#{title}</h1>
        #{body}
      </body>
    </html>
    """

    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
  end

  defp text(conn, body) do
    conn |> put_resp_content_type("text/plain") |> send_resp(200, body)
  end
end

port = String.to_integer(System.get_env("PORT", "4040"))

{:ok, _pid} =
  Supervisor.start_link([{Bandit, plug: E2E.Router, ip: {127, 0, 0, 1}, port: port}],
    strategy: :one_for_one
  )

IO.puts("e2e server on http://127.0.0.1:#{port}")
Process.sleep(:infinity)
