defmodule Hcaptcha.Http.MockClientTest do
  use ExUnit.Case, async: true

  alias Hcaptcha.Http.MockClient
  alias Hcaptcha.TestKeys

  defp body(params), do: URI.encode_query(params)

  test "accepts the test token with the test secret" do
    request = body(secret: TestKeys.secret(), response: TestKeys.token())

    assert {:ok, %{"success" => true, "challenge_ts" => ts, "hostname" => host}} =
             MockClient.request_verification(request, timeout: 10)

    assert {:ok, _, _} = DateTime.from_iso8601(ts)
    assert is_binary(host)
    assert_received {:request_verification, ^request, [timeout: 10]}
  end

  test "rejects another token with the test secret" do
    request = body(secret: TestKeys.secret(), response: "other")

    assert {:ok, %{"success" => false, "error-codes" => ["invalid-input-response"]}} =
             MockClient.request_verification(request)
  end

  test "refuses a real secret, even with the test token" do
    request = body(secret: "0xRealSecret", response: TestKeys.token())

    assert {:error, [:mock_requires_test_secret]} = MockClient.request_verification(request)
  end

  test "refuses the old reCAPTCHA secret and its magic token" do
    request = body(secret: "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe", response: "valid_response")

    assert {:error, [:mock_requires_test_secret]} = MockClient.request_verification(request)
  end

  test "refuses a request without a secret" do
    request = body(response: TestKeys.token())

    assert {:error, [:mock_requires_test_secret]} = MockClient.request_verification(request)
  end
end
