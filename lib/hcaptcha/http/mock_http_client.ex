defmodule Hcaptcha.Http.MockClient do
  @moduledoc """
  An offline HTTP client for tests. It never calls the network.

  It copies what the hCaptcha API does with the
  [test keys](https://docs.hcaptcha.com/#integration-testing-test-keys)
  (see `Hcaptcha.TestKeys`):

    * test secret and test token: success
    * test secret and any other token: `invalid-input-response`
    * any other secret: `{:error, [:mock_requires_test_secret]}`

  The last rule makes it safe to configure in any environment. A real secret
  never validates a token through the mock, so a mock left in production
  rejects every user instead of letting them through. With the test secret the
  real API also accepts the test token, so the mock is never more permissive
  than `Hcaptcha.Http`.

  `Hcaptcha.verify/2` returns `{:error, [:missing_input_secret]}` before it calls
  any client when no secret is set, so the mock never sees an empty secret. The
  `:secret` option of `verify/2` takes precedence over the config, here too.
  The mock sends no message and records nothing, so a mock installed by mistake
  does not disturb the calling process.

      config :hcaptcha,
        http_client: Hcaptcha.Http.MockClient,
        secret: Hcaptcha.TestKeys.secret()
  """

  @behaviour Hcaptcha.HttpClient

  alias Hcaptcha.TestKeys

  @impl Hcaptcha.HttpClient
  def request_verification(body, _options \\ []) do
    params = URI.decode_query(body)
    test_secret = TestKeys.secret()
    test_token = TestKeys.token()

    case params do
      %{"secret" => ^test_secret, "response" => ^test_token} ->
        {:ok,
         %{
           "success" => true,
           "credit" => false,
           "hostname" => "dummy-key-pass",
           "challenge_ts" =>
             DateTime.utc_now() |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()
         }}

      %{"secret" => ^test_secret} ->
        {:ok, %{"success" => false, "error-codes" => ["invalid-input-response"]}}

      _ ->
        {:error, [:mock_requires_test_secret]}
    end
  end
end
