defmodule Hcaptcha.Http.MockClientTest do
  use ExUnit.Case, async: true

  alias Hcaptcha.Http.MockClient
  alias Hcaptcha.TestKeys

  defp body(params), do: URI.encode_query(params)

  test "accepts the test token and valid_response with the test secret" do
    for token <- [TestKeys.token(), "valid_response"] do
      assert {:ok, %{"success" => true, "challenge_ts" => ts}} =
               MockClient.request_verification(body(secret: TestKeys.secret(), response: token))

      assert {:ok, _, _} = DateTime.from_iso8601(ts)
    end
  end

  test "rejects any other token with the test secret" do
    for token <- ["other", "invalid_response"] do
      assert {:ok, %{"success" => false, "error-codes" => ["invalid-input-response"]}} =
               MockClient.request_verification(body(secret: TestKeys.secret(), response: token))
    end
  end

  test "refuses every secret but the test secret, with every token" do
    for secret <- ["0xRealSecret", "6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe", nil],
        token <- ["valid_response", "invalid_response", TestKeys.token()] do
      request = body(Enum.reject([secret: secret, response: token], &is_nil(elem(&1, 1))))
      assert {:error, [:mock_requires_test_secret]} = MockClient.request_verification(request)
    end
  end
end
