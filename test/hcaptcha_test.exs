defmodule HcaptchaTest do
  use ExUnit.Case, async: false

  alias Hcaptcha.Http
  alias Hcaptcha.Http.MockClient
  alias Hcaptcha.Response
  alias Hcaptcha.TestKeys

  setup do
    keys = [:http_client, :secret]
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

  defp use_mock, do: Application.put_env(:hcaptcha, :http_client, MockClient)

  defp stub_api(body) do
    test_pid = self()

    Req.Test.stub(Http, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:api_request, raw})
      Req.Test.json(conn, body)
    end)
  end

  describe "public_key/0" do
    setup do
      original = Application.fetch_env!(:hcaptcha, :public_key)
      on_exit(fn -> Application.put_env(:hcaptcha, :public_key, original) end)
    end

    test "returns the configured sitekey" do
      Application.put_env(:hcaptcha, :public_key, "abc")

      assert Hcaptcha.public_key() == "abc"
    end

    test "returns nil when unset" do
      Application.delete_env(:hcaptcha, :public_key)

      assert Hcaptcha.public_key() == nil
    end
  end

  describe "missing token" do
    for token <- [nil, "", 123, %{}, :atom] do
      test "#{inspect(token)} returns :missing_input_response without a request" do
        use_mock()

        assert {:error, [:missing_input_response]} = Hcaptcha.verify(unquote(Macro.escape(token)))
        refute_received {:request_verification, _, _}
      end
    end
  end

  describe "with the mock client" do
    setup do
      use_mock()
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

    test "a missing secret reaches the mock, which refuses it" do
      Application.delete_env(:hcaptcha, :secret)

      assert {:error, [:mock_requires_test_secret]} = Hcaptcha.verify(TestKeys.token())
    end

    test "the configured secret and token are in the request body" do
      token = TestKeys.token()
      secret = TestKeys.secret()
      Hcaptcha.verify(token)

      assert_received {:request_verification, body, []}
      assert URI.decode_query(body) == %{"secret" => secret, "response" => token}
    end

    test "the secret option overrides the configured secret" do
      Hcaptcha.verify(TestKeys.token(), secret: "0xabc")

      assert_received {:request_verification, body, _}
      assert %{"secret" => "0xabc"} = URI.decode_query(body)
    end

    test "the timeout option is passed to the client" do
      Hcaptcha.verify(TestKeys.token(), timeout: 25_000)

      assert_received {:request_verification, _, [timeout: 25_000]}
    end

    test "remote_ip is sent as remoteip, from a string or a tuple" do
      Hcaptcha.verify(TestKeys.token(), remote_ip: "192.168.1.1")
      assert_received {:request_verification, body, _}
      assert %{"remoteip" => "192.168.1.1"} = URI.decode_query(body)

      Hcaptcha.verify(TestKeys.token(), remote_ip: {10, 0, 0, 1})
      assert_received {:request_verification, body, _}
      assert %{"remoteip" => "10.0.0.1"} = URI.decode_query(body)
    end

    test "sitekey is sent when given" do
      Hcaptcha.verify(TestKeys.token(), sitekey: TestKeys.sitekey())

      assert_received {:request_verification, body, _}
      assert %{"sitekey" => sitekey} = URI.decode_query(body)
      assert sitekey == TestKeys.sitekey()
    end

    test "unsupported options are not sent" do
      Hcaptcha.verify(TestKeys.token(), unsupported_option: "x")

      assert_received {:request_verification, body, _}
      assert Map.keys(URI.decode_query(body)) |> Enum.sort() == ["response", "secret"]
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

      assert_received {:api_request, raw}
      assert %{"response" => "token", "secret" => _} = URI.decode_query(raw)
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

    test "a missing secret returns :missing_input_secret without a request" do
      Application.delete_env(:hcaptcha, :secret)
      stub_api(%{"success" => true})

      assert {:error, [:missing_input_secret]} = Hcaptcha.verify("token")
      refute_received {:api_request, _}

      Application.put_env(:hcaptcha, :secret, "")
      assert {:error, [:missing_input_secret]} = Hcaptcha.verify("token")
      refute_received {:api_request, _}
    end

    test "a secret option replaces a missing configured secret" do
      Application.delete_env(:hcaptcha, :secret)
      stub_api(%{"success" => true})

      assert {:ok, _} = Hcaptcha.verify("token", secret: "0xabc")
    end
  end

  describe "custom client" do
    defmodule BadClient do
      @behaviour Hcaptcha.HttpClient
      @impl true
      def request_verification(_body, _options), do: {:error, []}
    end

    test "an empty error list returns :unexpected_response" do
      Application.put_env(:hcaptcha, :http_client, BadClient)

      assert {:error, [:unexpected_response]} = Hcaptcha.verify("token")
    end
  end
end
