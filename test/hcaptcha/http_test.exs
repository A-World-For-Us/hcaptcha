defmodule Hcaptcha.HttpTest do
  use ExUnit.Case, async: false

  alias Hcaptcha.Http

  defmodule CaptureAdapter do
    def run(request) do
      send(Application.fetch_env!(:hcaptcha, :capture_pid), {:options, request.options})
      {request, Req.Response.new(status: 200, body: "{}")}
    end
  end

  @body "secret=s&response=r"

  setup do
    on_exit(fn ->
      Application.delete_env(:hcaptcha, :verify_url)
      Application.delete_env(:hcaptcha, :timeout)
    end)
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
    test_pid = self()

    Req.Test.stub(Http, fn conn ->
      send(test_pid, {:seen, conn.host, conn.request_path})
      Req.Test.json(conn, %{})
    end)

    assert {:ok, %{}} = Http.request_verification(@body)
    assert_received {:seen, "example.test", "/verify"}
  end

  test "passes the timeout option to Req" do
    test_pid = self()
    original = Application.get_env(:hcaptcha, :req_options)

    Application.put_env(:hcaptcha, :capture_pid, test_pid)
    Application.put_env(:hcaptcha, :req_options, adapter: CaptureAdapter)

    on_exit(fn ->
      Application.delete_env(:hcaptcha, :capture_pid)
      Application.put_env(:hcaptcha, :req_options, original)
    end)

    assert {:ok, %{}} = Http.request_verification(@body, timeout: 1234)
    assert_received {:options, %{receive_timeout: 1234, connect_options: [timeout: 1234]}}

    Application.put_env(:hcaptcha, :timeout, 777)
    assert {:ok, %{}} = Http.request_verification(@body)
    assert_received {:options, %{receive_timeout: 777}}
  end

  test "decodes JSON whatever the content type" do
    Req.Test.stub(Http, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(200, ~s({"success":false,"error-codes":["bad-request"]}))
    end)

    assert {:ok, %{"error-codes" => ["bad-request"]}} = Http.request_verification(@body)
  end

  test "returns :invalid_response_body for a body that is not a JSON object" do
    Req.Test.stub(Http, &Plug.Conn.send_resp(&1, 200, "<html>"))
    assert {:error, [:invalid_response_body]} = Http.request_verification(@body)

    Req.Test.stub(Http, &Plug.Conn.send_resp(&1, 200, "[1]"))
    assert {:error, [:invalid_response_body]} = Http.request_verification(@body)
  end

  test "returns the transport reason on a transport error" do
    Req.Test.stub(Http, &Req.Test.transport_error(&1, :timeout))
    assert {:error, [:timeout]} = Http.request_verification(@body)

    Req.Test.stub(Http, &Req.Test.transport_error(&1, :econnrefused))
    assert {:error, [:econnrefused]} = Http.request_verification(@body)
  end

  test "returns :unexpected_status for a non-200 answer without error codes" do
    Req.Test.stub(Http, &Plug.Conn.send_resp(&1, 503, "unavailable"))
    assert {:error, [:unexpected_status]} = Http.request_verification(@body)

    Req.Test.stub(Http, &Plug.Conn.send_resp(&1, 500, ~s({"a":1})))
    assert {:error, [:unexpected_status]} = Http.request_verification(@body)
  end

  test "returns the body of a non-200 answer that has error codes" do
    Req.Test.stub(Http, fn conn ->
      conn
      |> Plug.Conn.send_resp(400, ~s({"success":false,"error-codes":["missing-input-secret"]}))
    end)

    assert {:ok, %{"error-codes" => ["missing-input-secret"]}} = Http.request_verification(@body)
  end

  test "does not retry a failing request" do
    test_pid = self()

    Req.Test.stub(Http, fn conn ->
      send(test_pid, :hit)
      Plug.Conn.send_resp(conn, 503, "")
    end)

    Http.request_verification(@body)
    assert_received :hit
    refute_received :hit
  end
end
