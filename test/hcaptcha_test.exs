defmodule HcaptchaTest do
  use ExUnit.Case, async: false

  alias Hcaptcha.Http
  alias Hcaptcha.Http.MockClient
  alias Hcaptcha.RecordingClient
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

  defp use_client(client), do: Application.put_env(:hcaptcha, :http_client, client)

  defp stub_api(body) do
    test_pid = self()

    Req.Test.stub(Http, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:api_request, URI.decode_query(raw)})
      Req.Test.json(conn, body)
    end)
  end

  describe "missing token" do
    for token <- [nil, "", 123, %{}, :atom] do
      test "#{inspect(token)} returns :missing_input_response without a request" do
        use_client(RecordingClient)

        assert {:error, [:missing_input_response]} = Hcaptcha.verify(unquote(Macro.escape(token)))
        refute_received {:request_verification, _, _}
      end
    end
  end

  describe "missing secret" do
    for client <- [Http, MockClient, RecordingClient], secret <- [nil, "", 42, :atom] do
      test "#{inspect(secret)} with #{inspect(client)} returns :missing_input_secret, no request" do
        use_client(unquote(client))
        Application.put_env(:hcaptcha, :secret, unquote(secret))

        assert {:error, [:missing_input_secret]} = Hcaptcha.verify("token")
        refute_received {:request_verification, _, _}
      end
    end

    test "the secret option replaces a missing configured secret" do
      Application.delete_env(:hcaptcha, :secret)
      stub_api(%{"success" => true})

      assert {:ok, _} = Hcaptcha.verify("token", secret: "0xabc")
    end

    test "a non-binary secret option is missing, even when the config has a secret" do
      assert {:error, [:missing_input_secret]} = Hcaptcha.verify("token", secret: 42)
    end
  end

  describe "with the mock client" do
    setup do
      use_client(MockClient)
    end

    test "the test token with the test secret succeeds" do
      assert {:ok, %Response{hostname: host, challenge_ts: ts}} =
               Hcaptcha.verify(TestKeys.token())

      assert is_binary(host)
      assert {:ok, _, _} = DateTime.from_iso8601(ts)
    end

    test "another token with the test secret returns :invalid_input_response" do
      assert {:error, [:invalid_input_response]} = Hcaptcha.verify("not_valid")
    end

    test "a real secret option is refused" do
      assert {:error, [:mock_requires_test_secret]} =
               Hcaptcha.verify(TestKeys.token(), secret: "0xabc")
    end

    test "sends no message to the caller" do
      Hcaptcha.verify(TestKeys.token())

      refute_received _
    end
  end

  describe "request" do
    test "has the configured secret and the token" do
      stub_api(%{"success" => true})
      Application.put_env(:hcaptcha, :secret, "configured")

      Hcaptcha.verify("token")

      assert_received {:api_request, params}
      assert params == %{"secret" => "configured", "response" => "token"}
    end

    test "has the secret option instead of the configured secret" do
      stub_api(%{"success" => true})

      Hcaptcha.verify("token", secret: "0xabc")

      assert_received {:api_request, %{"secret" => "0xabc"}}
    end

    test "sends remote_ip as remoteip, from a string or a tuple" do
      stub_api(%{"success" => true})

      Hcaptcha.verify("token", remote_ip: "192.168.1.1")
      assert_received {:api_request, %{"remoteip" => "192.168.1.1"}}

      Hcaptcha.verify("token", remote_ip: {10, 0, 0, 1})
      assert_received {:api_request, %{"remoteip" => "10.0.0.1"}}

      Hcaptcha.verify("token", remote_ip: {0, 0, 0, 0, 0, 0, 0, 1})
      assert_received {:api_request, %{"remoteip" => "::1"}}
    end

    test "sends the sitekey when given" do
      stub_api(%{"success" => true})

      Hcaptcha.verify("token", sitekey: TestKeys.sitekey())

      assert_received {:api_request, %{"sitekey" => sitekey}}
      assert sitekey == TestKeys.sitekey()
    end

    test "does not send unsupported options" do
      stub_api(%{"success" => true})

      Hcaptcha.verify("token", unsupported_option: "x")

      assert_received {:api_request, params}
      assert Enum.sort(Map.keys(params)) == ["response", "secret"]
    end

    test "passes the timeout option to the client" do
      use_client(RecordingClient)

      Hcaptcha.verify("token", timeout: 25_000)

      assert_received {:request_verification, _, [timeout: 25_000]}
    end

    test "uses the configured timeout when the option is absent" do
      Application.put_env(:hcaptcha, :timeout, 4321)

      TestAdapter.install(fn request ->
        send(self(), {:receive_timeout, request.options.receive_timeout})
        {request, Req.Response.new(status: 200, body: ~s({"success":true}))}
      end)

      assert {:ok, _} = Hcaptcha.verify("token")
      assert_received {:receive_timeout, 4321}

      assert {:ok, _} = Hcaptcha.verify("token", timeout: 99)
      assert_received {:receive_timeout, 99}
    end
  end

  describe "bad options" do
    test "raise ArgumentError" do
      for {option, message} <- [
            {[remote_ip: {1, 2}], ":remote_ip"},
            {[remote_ip: 42], ":remote_ip"},
            {[sitekey: 42], ":sitekey"},
            {[timeout: -1], ":timeout"},
            {[timeout: "5"], ":timeout"}
          ] do
        assert_raise ArgumentError, ~r/#{message}/, fn -> Hcaptcha.verify("token", option) end
      end
    end

    test "are not checked when the token is missing" do
      assert {:error, [:missing_input_response]} = Hcaptcha.verify(nil, sitekey: 42)
    end
  end

  describe "with the real client and a stubbed API" do
    test "a success body returns a Response" do
      stub_api(%{
        "success" => true,
        "challenge_ts" => "2026-01-01T00:00:00Z",
        "hostname" => "a.b"
      })

      assert {:ok, %Response{challenge_ts: "2026-01-01T00:00:00Z", hostname: "a.b"}} =
               Hcaptcha.verify("token")
    end

    test "a success body without hostname does not crash" do
      stub_api(%{"success" => true})

      assert {:ok, %Response{challenge_ts: "", hostname: ""}} = Hcaptcha.verify("token")
    end

    test "error codes are mapped to atoms" do
      codes = [
        {"missing-input-secret", :missing_input_secret},
        {"invalid-input-secret", :invalid_input_secret},
        {"missing-input-response", :missing_input_response},
        {"invalid-input-response", :invalid_input_response},
        {"expired-input-response", :expired_input_response},
        {"already-seen-response", :already_seen_response},
        {"invalid-or-already-seen-response", :invalid_or_already_seen_response},
        {"bad-request", :bad_request},
        {"missing-remoteip", :missing_remoteip},
        {"invalid-remoteip", :invalid_remoteip},
        {"not-using-dummy-passcode", :not_using_dummy_passcode},
        {"not-using-dummy-secret", :not_using_dummy_passcode},
        {"sitekey-secret-mismatch", :sitekey_secret_mismatch},
        {"something-new", :unknown_error}
      ]

      for {code, atom} <- codes do
        stub_api(%{"success" => false, "error-codes" => [code]})
        assert {:error, [^atom]} = Hcaptcha.verify("token")
      end
    end

    test "several error codes are all mapped" do
      stub_api(%{"success" => false, "error-codes" => ["bad-request", "invalid-remoteip"]})

      assert {:error, [:bad_request, :invalid_remoteip]} = Hcaptcha.verify("token")
    end

    test "success false without error codes returns :challenge_failed" do
      stub_api(%{"success" => false})
      assert {:error, [:challenge_failed]} = Hcaptcha.verify("token")

      stub_api(%{"success" => false, "error-codes" => []})
      assert {:error, [:challenge_failed]} = Hcaptcha.verify("token")
    end

    test "an unknown JSON shape returns :unexpected_response" do
      for body <- [%{}, %{"success" => "yes"}, %{"foo" => 1}] do
        stub_api(body)
        assert {:error, [:unexpected_response]} = Hcaptcha.verify("token")
      end
    end

    test "invalid JSON returns :invalid_response_body" do
      Req.Test.stub(Http, &Plug.Conn.send_resp(&1, 200, "not json"))

      assert {:error, [:invalid_response_body]} = Hcaptcha.verify("token")
    end

    test "a transport error returns its reason" do
      Req.Test.stub(Http, &Req.Test.transport_error(&1, :timeout))

      assert {:error, [:timeout]} = Hcaptcha.verify("token")
    end
  end

  describe "custom client" do
    defmodule EmptyErrorClient do
      @behaviour Hcaptcha.HttpClient
      @impl true
      def request_verification(_body, _options), do: {:error, []}
    end

    defmodule FailingClient do
      @behaviour Hcaptcha.HttpClient
      @impl true
      def request_verification(_body, _options), do: {:error, [:boom]}
    end

    test "its error atoms are returned" do
      use_client(FailingClient)

      assert {:error, [:boom]} = Hcaptcha.verify("token")
    end

    test "an empty error list returns :unexpected_response" do
      use_client(EmptyErrorClient)

      assert {:error, [:unexpected_response]} = Hcaptcha.verify("token")
    end
  end
end
