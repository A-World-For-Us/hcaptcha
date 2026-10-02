defmodule Hcaptcha do
  @moduledoc """
  Verifies hCaptcha response tokens on the server.

  See the [hCaptcha documentation](https://docs.hcaptcha.com/) and the README.

  ## Configuration

  Set these in `config/runtime.exs`:

    * `:secret` - the account secret
    * `:public_key` - the sitekey, read by `Hcaptcha.Template`
    * `:http_client` - a `Hcaptcha.HttpClient` (default `Hcaptcha.Http`)
    * `:verify_url` - default `https://api.hcaptcha.com/siteverify`
    * `:timeout` - request timeout in ms (default 5000)

  ## Error atoms

  `verify/2` returns `{:error, atoms}`. The atoms come from the API error
  codes (`"missing-input-secret"` becomes `:missing_input_secret`), plus:

    * `:missing_input_response` - no token was given, and no request was made.
      The widget script was probably blocked or did not run.
    * `:invalid_input_response` - the API rejected the token
    * `:missing_input_secret` - no secret is configured, and no request was made
    * `:challenge_failed` - the API answered `success: false` with no error code
    * `:unknown_error` - the API sent an error code this library does not know
    * `:unexpected_response` - the API answer has no known shape
    * `:invalid_response_body`, `:unexpected_status`, `:http_error`, or a
      transport reason such as `:timeout` - see `Hcaptcha.Http`
    * `:mock_requires_test_secret` - from `Hcaptcha.Http.MockClient`
  """

  alias Hcaptcha.Http
  alias Hcaptcha.Http.MockClient
  alias Hcaptcha.Response

  @error_codes %{
    "missing-input-secret" => :missing_input_secret,
    "invalid-input-secret" => :invalid_input_secret,
    "missing-input-response" => :missing_input_response,
    "invalid-input-response" => :invalid_input_response,
    "expired-input-response" => :expired_input_response,
    "already-seen-response" => :already_seen_response,
    "invalid-or-already-seen-response" => :invalid_or_already_seen_response,
    "bad-request" => :bad_request,
    "missing-remoteip" => :missing_remoteip,
    "invalid-remoteip" => :invalid_remoteip,
    "not-using-dummy-passcode" => :not_using_dummy_passcode,
    "not-using-dummy-secret" => :not_using_dummy_passcode,
    "sitekey-secret-mismatch" => :sitekey_secret_mismatch
  }

  @type option ::
          {:timeout, timeout()}
          | {:secret, String.t()}
          | {:remote_ip, String.t() | :inet.ip_address()}
          | {:sitekey, String.t()}

  @type error :: atom()

  @doc """
  Verifies the `h-captcha-response` token of a submitted form.

  A `nil`, empty or non-binary token returns `{:error, [:missing_input_response]}`
  without a request. A rejected token returns `{:error, [:invalid_input_response]}`.

  ## Options

    * `:timeout` - request timeout in ms (default: config `:timeout`, then 5000)
    * `:secret` - overrides the configured secret
    * `:remote_ip` - the user's IP, as a string or an `:inet` tuple
    * `:sitekey` - the sitekey the token must have been issued for

  ## Example

      case Hcaptcha.verify(params["h-captcha-response"], remote_ip: ip) do
        {:ok, %Hcaptcha.Response{}} -> :ok
        {:error, [:missing_input_response]} -> :captcha_blocked
        {:error, _errors} -> :captcha_failed
      end
  """
  @spec verify(term(), [option()]) :: {:ok, Response.t()} | {:error, [error()]}
  def verify(token, options \\ [])

  def verify(token, options) when is_binary(token) and token != "" do
    client = http_client()
    secret = Keyword.get_lazy(options, :secret, fn -> Application.get_env(:hcaptcha, :secret) end)

    if blank?(secret) and client != MockClient do
      {:error, [:missing_input_secret]}
    else
      body = request_body(token, secret, options)

      body
      |> client.request_verification(Keyword.take(options, [:timeout]))
      |> map_result()
    end
  end

  def verify(_token, _options), do: {:error, [:missing_input_response]}

  defp request_body(token, secret, options) do
    URI.encode_query(
      Enum.reject(
        [
          secret: secret,
          response: token,
          remoteip: format_ip(options[:remote_ip]),
          sitekey: options[:sitekey]
        ],
        fn {_key, value} -> is_nil(value) end
      )
    )
  end

  defp format_ip(nil), do: nil
  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()

  defp map_result({:ok, %{"success" => true} = body}) do
    {:ok,
     %Response{
       challenge_ts: string_or_empty(body["challenge_ts"]),
       hostname: string_or_empty(body["hostname"])
     }}
  end

  defp map_result({:ok, %{"success" => false} = body}) do
    case body["error-codes"] do
      [_ | _] = codes -> {:error, Enum.map(codes, &atomise_api_error/1)}
      _ -> {:error, [:challenge_failed]}
    end
  end

  defp map_result({:ok, _body}), do: {:error, [:unexpected_response]}
  defp map_result({:error, [_ | _] = errors}), do: {:error, errors}
  defp map_result(_other), do: {:error, [:unexpected_response]}

  defp atomise_api_error(code), do: Map.get(@error_codes, code, :unknown_error)

  defp string_or_empty(value) when is_binary(value), do: value
  defp string_or_empty(_value), do: ""

  defp blank?(value), do: not is_binary(value) or value == ""

  defp http_client, do: Application.get_env(:hcaptcha, :http_client, Http)
end
