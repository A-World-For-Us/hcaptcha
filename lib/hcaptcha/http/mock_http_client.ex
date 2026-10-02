defmodule Hcaptcha.Http.MockClient do
  @moduledoc """
  An offline HTTP client for tests. It never calls the network.

  It copies what the hCaptcha API does with the
  [test keys](https://docs.hcaptcha.com/#integration-testing-test-keys)
  (see `Hcaptcha.TestKeys`):

    * test secret and test token: success
    * test secret and any other token: `invalid-input-response`
    * any other secret, or none: `{:error, [:mock_requires_test_secret]}`

  The last rule makes it safe to configure in any environment. A real secret
  never validates a token through the mock, so a mock left in production
  rejects every user instead of letting them through. With the test secret the
  real API also accepts the test token, so the mock is never more permissive
  than `Hcaptcha.Http`.

  Each call sends `{:request_verification, body, options}` to the calling
  process, so tests can assert on the request.

      config :hcaptcha,
        http_client: Hcaptcha.Http.MockClient,
        secret: Hcaptcha.TestKeys.secret()
  """

  @behaviour Hcaptcha.HttpClient

  alias Hcaptcha.TestKeys

  @impl Hcaptcha.HttpClient
  def request_verification(body, options \\ []) do
    send(self(), {:request_verification, body, options})

    params = URI.decode_query(body)
    test_secret = TestKeys.secret()
    test_token = TestKeys.token()

    case params do
      %{"secret" => ^test_secret, "response" => ^test_token} ->
        {:ok,
         %{
           "success" => true,
           "challenge_ts" => DateTime.to_iso8601(DateTime.utc_now()),
           "hostname" => "dummy-key-pass"
         }}

      %{"secret" => ^test_secret} ->
        {:ok, %{"success" => false, "error-codes" => ["invalid-input-response"]}}

      _ ->
        {:error, [:mock_requires_test_secret]}
    end
  end
end
