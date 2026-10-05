defmodule Hcaptcha.HttpClient do
  @moduledoc """
  Behaviour of the `:http_client` that sends the verification request.
  """

  @typedoc "Options passed by `Hcaptcha.verify/2`."
  @type options :: [timeout: timeout()]

  @doc """
  Sends the form-encoded `body` and returns the decoded JSON answer or error atoms.
  """
  @callback request_verification(body :: binary(), options()) ::
              {:ok, map()} | {:error, [atom()]}
end
