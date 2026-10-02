defmodule Hcaptcha.HttpTest do
  use ExUnit.Case, async: false

  alias Hcaptcha.Http
  alias Hcaptcha.TestAdapter

  @body "secret=s&response=r"

  setup do
    original = Application.fetch_env!(:hcaptcha, :req_options)

    on_exit(fn ->
      Application.delete_env(:hcaptcha, :verify_url)
      Application.delete_env(:hcaptcha, :timeout)
      Application.put_env(:hcaptcha, :req_options, original)
    end)

    %{plug_options: original}
  end

  defp count_hits(test_pid, response_fun) do
    fn conn ->
      send(test_pid, {:hit, conn.method, conn.host, conn.request_path})
      response_fun.(conn)
    end
  end

  test "posts the form body with form and JSON headers to the default URL" do
    test_pid = self()

    Req.Test.stub(Http, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:seen, conn.method, conn.host, conn.request_path, conn.scheme, raw})
      send(test_pid, {:headers, conn.req_headers})
      Req.Test.json(conn, %{"success" => true})
    end)

    assert {:ok, %{"success" => true}} = Http.request_verification(@body)

    assert_received {:seen, "POST", "api.hcaptcha.com", "/siteverify", :https, @body}
    assert_received {:headers, headers}
    assert {"content-type", "application/x-www-form-urlencoded"} in headers
    assert {"accept", "application/json"} in headers
  end

  test "uses the configured verify URL" do
    Application.put_env(:hcaptcha, :verify_url, "https://example.test/verify")
    Req.Test.stub(Http, count_hits(self(), &Req.Test.json(&1, %{})))

    assert {:ok, %{}} = Http.request_verification(@body)
    assert_received {:hit, "POST", "example.test", "/verify"}
  end

  describe "timeout" do
    setup do
      TestAdapter.install(fn request ->
        send(self(), {:options, request.options})
        {request, Req.Response.new(status: 200, body: "{}")}
      end)
    end

    test "the option sets the receive and connect timeouts" do
      assert {:ok, %{}} = Http.request_verification(@body, timeout: 1234)
      assert_received {:options, %{receive_timeout: 1234, connect_options: [timeout: 1234]}}
    end

    test "the config is the default" do
      Application.put_env(:hcaptcha, :timeout, 777)

      assert {:ok, %{}} = Http.request_verification(@body)
      assert_received {:options, %{receive_timeout: 777}}
    end

    test "falls back to 5000" do
      assert {:ok, %{}} = Http.request_verification(@body)
      assert_received {:options, %{receive_timeout: 5000}}
    end
  end

  describe "answers" do
    test "decodes JSON whatever the content type" do
      Req.Test.stub(Http, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, ~s({"success":false,"error-codes":["bad-request"]}))
      end)

      assert {:ok, %{"error-codes" => ["bad-request"]}} = Http.request_verification(@body)
    end

    test "returns :invalid_response_body for a 200 body that is not a JSON object" do
      Req.Test.stub(Http, &Plug.Conn.send_resp(&1, 200, "<html>"))
      assert {:error, [:invalid_response_body]} = Http.request_verification(@body)

      Req.Test.stub(Http, &Plug.Conn.send_resp(&1, 200, "[1]"))
      assert {:error, [:invalid_response_body]} = Http.request_verification(@body)
    end

    test "returns :unexpected_status for a non-200 answer without error codes" do
      for body <- ["unavailable", ~s({"a":1}), "[1]", ""] do
        Req.Test.stub(Http, &Plug.Conn.send_resp(&1, 503, body))
        assert {:error, [:unexpected_status]} = Http.request_verification(@body)
      end
    end

    test "returns the body of a non-200 answer that has error codes" do
      Req.Test.stub(Http, fn conn ->
        Plug.Conn.send_resp(
          conn,
          400,
          ~s({"success":false,"error-codes":["missing-input-secret"]})
        )
      end)

      assert {:ok, %{"error-codes" => ["missing-input-secret"]}} =
               Http.request_verification(@body)
    end
  end

  describe "failures" do
    test "returns the transport reason" do
      Req.Test.stub(Http, &Req.Test.transport_error(&1, :timeout))
      assert {:error, [:timeout]} = Http.request_verification(@body)

      Req.Test.stub(Http, &Req.Test.transport_error(&1, :econnrefused))
      assert {:error, [:econnrefused]} = Http.request_verification(@body)
    end

    test "returns :http_error for a transport reason that is not an atom" do
      TestAdapter.install(fn request ->
        {request, %Req.TransportError{reason: {:tls_alert, {:unknown_ca, ~c"x"}}}}
      end)

      assert {:error, [:http_error]} = Http.request_verification(@body)
    end

    test "returns :http_error for any other exception" do
      TestAdapter.install(fn request -> {request, %RuntimeError{message: "boom"}} end)

      assert {:error, [:http_error]} = Http.request_verification(@body)
    end
  end

  describe "redirects and retries" do
    test "a 307 is not followed and returns :unexpected_status" do
      Req.Test.stub(
        Http,
        count_hits(self(), fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://other.test/steal")
          |> Plug.Conn.send_resp(307, "")
        end)
      )

      assert {:error, [:unexpected_status]} = Http.request_verification(@body)
      assert_received {:hit, "POST", "api.hcaptcha.com", "/siteverify"}
      refute_received {:hit, _, _, _}
    end

    test "a failing request is not retried" do
      Req.Test.stub(Http, count_hits(self(), &Plug.Conn.send_resp(&1, 503, "")))

      Http.request_verification(@body)
      assert_received {:hit, _, _, _}
      refute_received {:hit, _, _, _}
    end
  end

  describe ":req_options" do
    test "cannot change the options the library owns", %{plug_options: plug_options} do
      Application.put_env(
        :hcaptcha,
        :req_options,
        plug_options ++
          [
            retry: :transient,
            redirect: true,
            decode_body: true,
            url: "https://evil.test/x",
            method: :get,
            body: "evil=1",
            headers: [{"x-evil", "1"}]
          ]
      )

      test_pid = self()

      Req.Test.stub(Http, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:hit, conn.method, conn.host, conn.request_path, raw, conn.req_headers})

        case conn.method do
          "POST" -> Plug.Conn.send_resp(conn, 503, "")
          _ -> Req.Test.json(conn, %{})
        end
      end)

      assert {:error, [:unexpected_status]} = Http.request_verification(@body)
      assert_received {:hit, "POST", "api.hcaptcha.com", "/siteverify", @body, headers}
      refute List.keymember?(headers, "x-evil", 0)
      refute_received {:hit, _, _, _, _, _}

      Req.Test.stub(Http, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ~s({"success":true}))
      end)

      assert {:ok, %{"success" => true}} = Http.request_verification(@body)
    end

    test "a user redirect option does not follow a 307", %{plug_options: plug_options} do
      Application.put_env(:hcaptcha, :req_options, plug_options ++ [redirect: true])

      Req.Test.stub(
        Http,
        count_hits(self(), fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://other.test/steal")
          |> Plug.Conn.send_resp(307, "")
        end)
      )

      assert {:error, [:unexpected_status]} = Http.request_verification(@body)
      assert_received {:hit, _, "api.hcaptcha.com", _}
      refute_received {:hit, _, _, _}
    end

    test "keeps other connect options and replaces their timeout" do
      TestAdapter.install(fn request ->
        send(self(), {:options, request.options})
        {request, Req.Response.new(status: 200, body: "{}")}
      end)

      Application.put_env(:hcaptcha, :req_options,
        adapter: TestAdapter,
        connect_options: [proxy: {:http, "proxy.test", 8080, []}, timeout: 1]
      )

      assert {:ok, %{}} = Http.request_verification(@body, timeout: 99)
      assert_received {:options, %{connect_options: connect_options}}
      assert connect_options[:proxy] == {:http, "proxy.test", 8080, []}
      assert connect_options[:timeout] == 99
    end
  end
end
