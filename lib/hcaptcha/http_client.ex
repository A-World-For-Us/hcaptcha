defmodule Hcaptcha.HttpClient do
  @moduledoc """
  Behaviour of the module that sends a verification request to hCaptcha.

  Select the implementation with `config :hcaptcha, http_client: MyClient`.
  The default is `Hcaptcha.Http`. `Hcaptcha.Http.MockClient` is an offline
  implementation for tests.
  """

  @typedoc "Options passed by `Hcaptcha.verify/2`."
  @type options :: [timeout: timeout()]

  @doc """
  Sends the form-encoded `body` to the verification endpoint.

  Returns the decoded JSON object of the API, or a list of error atoms when
  the request fails or the answer is not usable.
  """
  @callback request_verification(body :: binary(), options()) ::
              {:ok, map()} | {:error, [atom()]}
end
