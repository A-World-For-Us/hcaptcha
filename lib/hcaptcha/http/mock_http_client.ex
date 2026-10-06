defmodule Hcaptcha.Http.MockClient do
  @moduledoc """
  An offline HTTP client for tests. It never calls the network.

  It accepts only two tokens, and only with the test secret from `Hcaptcha.TestKeys`:

    * `Hcaptcha.TestKeys.token/0` and `"valid_response"`: success
    * any other token, `"invalid_response"` included: `invalid-input-response`

  Any other secret returns `{:error, [:mock_requires_test_secret]}`, so a mock left in
  production with a real secret lets nobody through.

      config :hcaptcha,
        http_client: Hcaptcha.Http.MockClient,
        secret: Hcaptcha.TestKeys.secret()
  """

  @behaviour Hcaptcha.HttpClient

  alias Hcaptcha.TestKeys

  @valid_tokens [TestKeys.token(), "valid_response"]

  @impl Hcaptcha.HttpClient
  def request_verification(body, _options \\ []) do
    params = URI.decode_query(body)
    test_secret = TestKeys.secret()

    case params do
      %{"secret" => ^test_secret, "response" => token} when token in @valid_tokens ->
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
