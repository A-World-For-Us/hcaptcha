defmodule HcaptchaTest do
  use ExUnit.Case, async: false

  alias Hcaptcha.Http
  alias Hcaptcha.Http.MockClient
  alias Hcaptcha.Response
  alias Hcaptcha.TestAdapter
  alias Hcaptcha.TestKeys

  setup do
    keys = [:http_client, :secret, :timeout]
    original = Map.new(keys, &{&1, Application.fetch_env(:hcaptcha, &1)})

    on_exit(fn ->
      for {key, result} <- original do
        case result do
          {:ok, value} -> Application.put_env(:hcaptcha, key, value)
          :error -> Application.delete_env(:hcaptcha, key)
        end
      end
    end)
  end

  defp stub_api(body) do
    test_pid = self()

    Req.Test.stub(Http, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:api_request, URI.decode_query(raw)})
      Req.Test.json(conn, body)
    end)
  end

  test "a missing token returns :missing_input_response without a request, before option checks" do
    stub_api(%{"success" => true})

    for token <- [nil, "", 123, %{}, :atom] do
      assert {:error, [:missing_input_response]} = Hcaptcha.verify(token, sitekey: 42)
    end

    refute_received {:api_request, _}
  end

  test "a missing secret returns :missing_input_secret without a request" do
    stub_api(%{"success" => true})

    for secret <- [nil, "", 42, :atom] do
      Application.put_env(:hcaptcha, :secret, secret)
      assert {:error, [:missing_input_secret]} = Hcaptcha.verify("token")
    end

    assert {:error, [:missing_input_secret]} = Hcaptcha.verify("token", secret: 42)
    refute_received {:api_request, _}
  end

  test "the mock client returns a Response for the test token and refuses a real secret" do
    Application.put_env(:hcaptcha, :http_client, MockClient)

    assert {:ok, %Response{hostname: host}} = Hcaptcha.verify(TestKeys.token())
    assert is_binary(host)
    assert {:error, [:invalid_input_response]} = Hcaptcha.verify("not_valid")

    assert {:error, [:mock_requires_test_secret]} =
             Hcaptcha.verify(TestKeys.token(), secret: "0xabc")
  end

  describe "request" do
    test "carries the configured secret, token and supported options, and nothing else" do
      stub_api(%{"success" => true})
      Application.put_env(:hcaptcha, :secret, "configured")

      Hcaptcha.verify("token")
      assert_received {:api_request, params}
      assert params == %{"secret" => "configured", "response" => "token"}

      Hcaptcha.verify("token",
        secret: "0xabc",
        remote_ip: "192.168.1.1",
        sitekey: TestKeys.sitekey(),
        unsupported_option: "x"
      )

      assert_received {:api_request, params}

      assert params == %{
               "secret" => "0xabc",
               "response" => "token",
               "remoteip" => "192.168.1.1",
               "sitekey" => TestKeys.sitekey()
             }
    end

    test "sends a tuple remote_ip as text" do
      stub_api(%{"success" => true})

      Hcaptcha.verify("token", remote_ip: {10, 0, 0, 1})
      assert_received {:api_request, %{"remoteip" => "10.0.0.1"}}

      Hcaptcha.verify("token", remote_ip: {0, 0, 0, 0, 0, 0, 0, 1})
      assert_received {:api_request, %{"remoteip" => "::1"}}
    end

    test "the timeout option reaches the HTTP request" do
      TestAdapter.install(fn request ->
        send(self(), {:receive_timeout, request.options.receive_timeout})
        {request, Req.Response.new(status: 200, body: ~s({"success":true}))}
      end)

      assert {:ok, _} = Hcaptcha.verify("token", timeout: 99)
      assert_received {:receive_timeout, 99}
    end

    test "bad options raise ArgumentError" do
      for {option, message} <- [
            {[remote_ip: {1, 2}], ":remote_ip"},
            {[sitekey: 42], ":sitekey"},
            {[timeout: -1], ":timeout"}
          ] do
        assert_raise ArgumentError, ~r/#{message}/, fn -> Hcaptcha.verify("token", option) end
      end
    end
  end

  describe "results" do
    test "a success body returns a Response, with empty strings for missing fields" do
      stub_api(%{
        "success" => true,
        "challenge_ts" => "2026-01-01T00:00:00Z",
        "hostname" => "a.b"
      })

      assert {:ok, %Response{challenge_ts: "2026-01-01T00:00:00Z", hostname: "a.b"}} =
               Hcaptcha.verify("token")

      stub_api(%{"success" => true})
      assert {:ok, %Response{challenge_ts: "", hostname: ""}} = Hcaptcha.verify("token")
    end

    test "error codes are mapped to atoms, unknown ones to :unknown_error" do
      stub_api(%{
        "success" => false,
        "error-codes" => ["bad-request", "invalid-remoteip", "something-new"]
      })

      assert {:error, [:bad_request, :invalid_remoteip, :unknown_error]} =
               Hcaptcha.verify("token")
    end

    test "success false without error codes returns :challenge_failed" do
      stub_api(%{"success" => false})
      assert {:error, [:challenge_failed]} = Hcaptcha.verify("token")
    end

    test "an unknown JSON shape returns :unexpected_response" do
      for body <- [%{}, %{"success" => "yes"}] do
        stub_api(body)
        assert {:error, [:unexpected_response]} = Hcaptcha.verify("token")
      end
    end

    test "a transport error returns its reason" do
      Req.Test.stub(Http, &Req.Test.transport_error(&1, :timeout))

      assert {:error, [:timeout]} = Hcaptcha.verify("token")
    end

    test "a custom client returning an empty error list returns :unexpected_response" do
      defmodule EmptyErrorClient do
        @behaviour Hcaptcha.HttpClient
        @impl true
        def request_verification(_body, _options), do: {:error, []}
      end

      Application.put_env(:hcaptcha, :http_client, EmptyErrorClient)
      assert {:error, [:unexpected_response]} = Hcaptcha.verify("token")
    end
  end
end
