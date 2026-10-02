defmodule Hcaptcha.Http do
  @moduledoc """
  Sends verification requests to the hCaptcha API with `Req`.

  Application config:

    * `:verify_url` - defaults to `https://api.hcaptcha.com/siteverify`
    * `:timeout` - default for the `:timeout` option (5000)
    * `:req_options` - transport options for `Req.new/1`, for example a proxy
      (`connect_options: [proxy: ...]`), a connection pool (`finch`), an
      `adapter`, or `plug: {Req.Test, Hcaptcha.Http}` to stub the API in tests

  The library sets `method`, `url`, `body`, `headers`, `retry`, `redirect`,
  `decode_body`, `into` and `receive_timeout` itself. `:req_options` cannot
  change them. A `connect_options` list is kept, and its `:timeout` is
  replaced. The request is never retried and redirects are not followed, so
  the secret goes only to the configured URL.
  """

  @behaviour Hcaptcha.HttpClient

  @default_verify_url "https://api.hcaptcha.com/siteverify"
  @default_timeout 5000
  @owned_options [
    :method,
    :url,
    :body,
    :headers,
    :retry,
    :redirect,
    :decode_body,
    :into,
    :receive_timeout
  ]

  @doc """
  Posts the form-encoded `body` to the verify URL.

  Returns the decoded JSON object, or `{:error, atoms}`:

    * the transport reason (`:timeout`, `:econnrefused`, ...) when the connection fails
    * `:http_error` for any other client failure
    * `:invalid_response_body` when a 200 answer is not a JSON object
    * `:unexpected_status` when the status is not 200 (a redirect included) and the
      body has no `error-codes`

  ## Options

    * `:timeout` - in ms. Sets the connect timeout and the receive timeout. The receive timeout
      limits each wait for data, so the whole request can take longer than this value.
  """
  @impl Hcaptcha.HttpClient
  def request_verification(body, options \\ []) do
    timeout = options[:timeout] || Application.get_env(:hcaptcha, :timeout, @default_timeout)
    user_options = Application.get_env(:hcaptcha, :req_options, [])
    connect_options = Keyword.put(user_options[:connect_options] || [], :timeout, timeout)

    user_options
    |> Keyword.drop([:connect_options | @owned_options])
    |> Keyword.merge(
      method: :post,
      url: Application.get_env(:hcaptcha, :verify_url, @default_verify_url),
      body: body,
      headers: [
        {"content-type", "application/x-www-form-urlencoded"},
        {"accept", "application/json"}
      ],
      receive_timeout: timeout,
      connect_options: connect_options,
      retry: false,
      redirect: false,
      decode_body: false
    )
    |> Req.request()
    |> handle_result()
  end

  defp handle_result({:ok, %Req.Response{status: status, body: body}}) do
    case {status, Jason.decode(body)} do
      {200, {:ok, %{} = data}} -> {:ok, data}
      {_, {:ok, %{"error-codes" => _} = data}} -> {:ok, data}
      {200, _} -> {:error, [:invalid_response_body]}
      _ -> {:error, [:unexpected_status]}
    end
  end

  defp handle_result({:error, %Req.TransportError{reason: reason}}) when is_atom(reason),
    do: {:error, [reason]}

  defp handle_result({:error, _exception}), do: {:error, [:http_error]}
end
