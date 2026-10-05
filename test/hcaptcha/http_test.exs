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

  test "posts the form body with form and JSON headers to the default, then the configured, URL" do
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

    Application.put_env(:hcaptcha, :verify_url, "https://example.test/verify")
    assert {:ok, _} = Http.request_verification(@body)
    assert_received {:seen, "POST", "example.test", "/verify", _, _}
  end

  test "timeout comes from the option, then the config, then 5000" do
    TestAdapter.install(fn request ->
      send(self(), {:options, request.options})
      {request, Req.Response.new(status: 200, body: "{}")}
    end)

    assert {:ok, %{}} = Http.request_verification(@body, timeout: 1234)
    assert_received {:options, %{receive_timeout: 1234, connect_options: [timeout: 1234]}}

    Application.put_env(:hcaptcha, :timeout, 777)
    assert {:ok, %{}} = Http.request_verification(@body)
    assert_received {:options, %{receive_timeout: 777}}

    Application.delete_env(:hcaptcha, :timeout)
    assert {:ok, %{}} = Http.request_verification(@body)
    assert_received {:options, %{receive_timeout: 5000}}
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
      for body <- ["<html>", "[1]"] do
        Req.Test.stub(Http, &Plug.Conn.send_resp(&1, 200, body))
        assert {:error, [:invalid_response_body]} = Http.request_verification(@body)
      end
    end

    test "a non-200 answer returns :unexpected_status without error codes, the body with them" do
      Req.Test.stub(Http, &Plug.Conn.send_resp(&1, 503, "unavailable"))
      assert {:error, [:unexpected_status]} = Http.request_verification(@body)

      Req.Test.stub(
        Http,
        &Plug.Conn.send_resp(
          &1,
          400,
          ~s({"success":false,"error-codes":["missing-input-secret"]})
        )
      )

      assert {:ok, %{"error-codes" => ["missing-input-secret"]}} =
               Http.request_verification(@body)
    end
  end

  describe "failures" do
    test "returns the transport reason" do
      Req.Test.stub(Http, &Req.Test.transport_error(&1, :econnrefused))
      assert {:error, [:econnrefused]} = Http.request_verification(@body)
    end

    test "returns :http_error for a non-atom reason or any other exception" do
      TestAdapter.install(fn request ->
        {request, %Req.TransportError{reason: {:tls_alert, {:unknown_ca, ~c"x"}}}}
      end)

      assert {:error, [:http_error]} = Http.request_verification(@body)

      TestAdapter.install(fn request -> {request, %RuntimeError{message: "boom"}} end)
      assert {:error, [:http_error]} = Http.request_verification(@body)
    end
  end

  describe "secret protection" do
    test "a 307 is not followed, with or without a user redirect option", %{
      plug_options: plug_options
    } do
      Req.Test.stub(
        Http,
        count_hits(self(), fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://other.test/steal")
          |> Plug.Conn.send_resp(307, "")
        end)
      )

      for options <- [plug_options, plug_options ++ [redirect: true]] do
        Application.put_env(:hcaptcha, :req_options, options)

        assert {:error, [:unexpected_status]} = Http.request_verification(@body)
        assert_received {:hit, "POST", "api.hcaptcha.com", "/siteverify"}
        refute_received {:hit, _, _, _}
      end
    end

    test "req_options cannot change the options the library owns, and a failure is not retried",
         %{plug_options: plug_options} do
      Application.put_env(
        :hcaptcha,
        :req_options,
        plug_options ++
          [
            retry: :transient,
            redirect: true,
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
        Plug.Conn.send_resp(conn, 503, "")
      end)

      assert {:error, [:unexpected_status]} = Http.request_verification(@body)
      assert_received {:hit, "POST", "api.hcaptcha.com", "/siteverify", @body, headers}
      refute List.keymember?(headers, "x-evil", 0)
      refute_received {:hit, _, _, _, _, _}
    end
  end
end
