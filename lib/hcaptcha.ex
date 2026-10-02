defmodule Hcaptcha do
  @moduledoc """
  Verifies hCaptcha response tokens on the server.

  See the [hCaptcha documentation](https://docs.hcaptcha.com/) and the README.

  ## Configuration

  Set these in `config/runtime.exs`:

    * `:secret` - the account secret
    * `:public_key` - the sitekey, read by `Hcaptcha.Template`
    * `:http_client` - a `Hcaptcha.HttpClient` (default `Hcaptcha.Http`)

  `Hcaptcha.Http` lists the transport keys: `:verify_url`, `:timeout` and `:req_options`.

  ## Error atoms

  `verify/2` returns `{:error, atoms}`. The atoms come from the API error
  codes (`"missing-input-secret"` becomes `:missing_input_secret`), plus:

    * `:missing_input_response` - no token was given, and no request was made.
      The widget script was probably blocked or did not run.
    * `:invalid_input_response` - the API rejected the token
    * `:expired_input_response` - the token expired (120 s by default)
    * `:already_seen_response` - the token was already verified once
    * `:sitekey_secret_mismatch` - the sitekey does not belong to the secret
    * `:missing_input_secret` - no secret is configured, and no request was made
    * `:challenge_failed` - the API answered `success: false` with no error code
    * `:unknown_error` - the API sent an error code this library does not know
    * `:unexpected_response` - the API answer has no known shape
    * `:invalid_response_body`, `:unexpected_status`, `:http_error`, or a
      transport reason such as `:timeout` - see `Hcaptcha.Http`
    * `:mock_requires_test_secret` - from `Hcaptcha.Http.MockClient`
  """

  alias Hcaptcha.Http
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
  without a request. A missing, empty or non-binary secret returns
  `{:error, [:missing_input_secret]}` without a request, with any client. The module doc lists
  every error atom.

  ## Options

    * `:timeout` - connect and receive timeout in ms, see `Hcaptcha.Http`
      (default: config `:timeout`, then 5000)
    * `:secret` - takes precedence over the configured secret, with every client
    * `:remote_ip` - the user's IP, as a string or an `:inet` tuple
    * `:sitekey` - the sitekey the token must have been issued for

  A bad option value is a programming error and raises `ArgumentError`: a
  `:remote_ip` that is not a string or a valid `:inet` address, a `:sitekey`
  that is not a string, or a `:timeout` that is not a non-negative integer or
  `:infinity`.

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
    options = validate_options!(options)
    secret = Keyword.get_lazy(options, :secret, fn -> Application.get_env(:hcaptcha, :secret) end)

    if blank?(secret) do
      {:error, [:missing_input_secret]}
    else
      token
      |> request_body(secret, options)
      |> http_client().request_verification(Keyword.take(options, [:timeout]))
      |> map_result()
    end
  end

  def verify(_token, _options), do: {:error, [:missing_input_response]}

  @doc """
  Returns the configured sitekey (`:public_key`), or `nil` when it is not set.
  """
  @spec public_key() :: String.t() | nil
  def public_key, do: Application.get_env(:hcaptcha, :public_key)

  defp validate_options!(options) do
    Keyword.update(options, :remote_ip, nil, &validate_ip!/1)
    |> validate!(:sitekey, &(is_nil(&1) or is_binary(&1)), "a string")
    |> validate!(
      :timeout,
      &(is_nil(&1) or &1 == :infinity or (is_integer(&1) and &1 >= 0)),
      "a non-negative integer or :infinity"
    )
  end

  defp validate!(options, key, valid?, expected) do
    value = options[key]

    if valid?.(value) do
      options
    else
      raise ArgumentError,
            "Hcaptcha.verify/2: #{inspect(key)} must be #{expected}, got: #{inspect(value)}"
    end
  end

  defp validate_ip!(nil), do: nil
  defp validate_ip!(ip) when is_binary(ip), do: ip

  defp validate_ip!(ip) when is_tuple(ip) do
    case :inet.ntoa(ip) do
      {:error, _reason} -> raise_bad_ip(ip)
      charlist -> to_string(charlist)
    end
  end

  defp validate_ip!(ip), do: raise_bad_ip(ip)

  defp raise_bad_ip(ip) do
    raise ArgumentError,
          "Hcaptcha.verify/2: :remote_ip must be a string or an :inet address tuple, got: #{inspect(ip)}"
  end

  defp request_body(token, secret, options) do
    [secret: secret, response: token, remoteip: options[:remote_ip], sitekey: options[:sitekey]]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> URI.encode_query()
  end

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
