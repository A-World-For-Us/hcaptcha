Mix.install(
  [
    {:hcaptcha, path: Path.expand("..", __DIR__)},
    {:plug, "~> 1.15"},
    {:phoenix, "~> 1.8"},
    {:phoenix_live_view, "~> 1.1"},
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

defmodule E2E.Assets do
  @moduledoc false
  import Plug.Conn

  @files %{
    "/js/phoenix.mjs" => {:phoenix, "priv/static/phoenix.mjs"},
    "/js/phoenix_live_view.js" => {:phoenix_live_view, "priv/static/phoenix_live_view.esm.js"},
    "/js/hcaptcha.js" => {:path, "../assets/js/hcaptcha.js"},
    "/js/core.js" => {:path, "../assets/js/core.js"}
  }

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: "/favicon.ico"} = conn, _opts) do
    conn |> send_resp(204, "") |> halt()
  end

  def call(%Plug.Conn{request_path: path} = conn, _opts) do
    case @files do
      %{^path => source} ->
        conn
        |> put_resp_content_type("text/javascript")
        |> send_file(200, file(source))
        |> halt()

      _ ->
        conn
    end
  end

  defp file({:path, relative}), do: Path.expand(relative, __DIR__)
  defp file({app, relative}), do: Application.app_dir(app, relative)
end

defmodule E2E.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>hcaptcha e2e</title>
        <script type="importmap" nonce={@csp_nonce}>
          {"imports": {
            "phoenix": "/js/phoenix.mjs",
            "phoenix_live_view": "/js/phoenix_live_view.js",
            "hcaptcha": "/js/hcaptcha.js"
          }}
        </script>
        <script type="module" nonce={@csp_nonce}>
          import { Socket } from "phoenix";
          import { LiveSocket } from "phoenix_live_view";
          import { Hcaptcha } from "hcaptcha";

          const token = document.querySelector("meta[name='csrf-token']").content;
          const liveSocket = new LiveSocket("/live", Socket, {
            params: { _csrf_token: token },
            hooks: { Hcaptcha },
          });
          liveSocket.connect();
          window.liveSocket = liveSocket;
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end

defmodule E2E.LoginLive do
  use Phoenix.LiveView
  import Hcaptcha.Components

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{"email" => ""}, as: :login))}
  end

  def render(assigns) do
    ~H"""
    <h1>LiveView login</h1>
    <.form for={@form} id="login" action="/verify" method="post" phx-submit="submit">
      <input type="email" name={@form[:email].name} id="email" value={@form[:email].value} />
      <.hcaptcha id="captcha" />
      <button type="submit" id="submit-button">Log in</button>
    </.form>
    """
  end

  def handle_event("submit", _params, socket) do
    {:noreply, Hcaptcha.Components.execute(socket, "captcha")}
  end
end

defmodule E2E.Web do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {E2E.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:csp)
  end

  scope "/" do
    pipe_through(:browser)

    live_session :default do
      live("/", E2E.LoginLive)
    end
  end

  forward("/", E2E.Router)

  def csp(conn, opts), do: E2E.Router.csp(conn, opts)
end

port = String.to_integer(System.get_env("PORT", "4040"))

Application.put_env(:e2e, E2E.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: port],
  server: true,
  url: [host: "127.0.0.1", port: port],
  secret_key_base: String.duplicate("e2e-secret", 8),
  live_view: [signing_salt: "e2e-salt"],
  pubsub_server: E2E.PubSub
)

defmodule E2E.Endpoint do
  use Phoenix.Endpoint, otp_app: :e2e

  @session_options [store: :cookie, key: "_e2e_key", signing_salt: "e2e-session"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(E2E.Assets)
  plug(Plug.Parsers, parsers: [:urlencoded], pass: ["*/*"])
  plug(Plug.Session, @session_options)
  plug(E2E.Web)
end

{:ok, _pid} =
  Supervisor.start_link([{Phoenix.PubSub, name: E2E.PubSub}, E2E.Endpoint],
    strategy: :one_for_one
  )

IO.puts("e2e server on http://127.0.0.1:#{port}")
Process.sleep(:infinity)
