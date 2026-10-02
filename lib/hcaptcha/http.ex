defmodule Hcaptcha.Http do
  @moduledoc """
  Sends verification requests to the hCaptcha API with `Req`.

  Application config:

    * `:verify_url` - defaults to `https://api.hcaptcha.com/siteverify`
    * `:timeout` - default timeout in ms (5000)
    * `:req_options` - extra options for `Req.request/1`, for example
      `[plug: {Req.Test, Hcaptcha.Http}]` to stub the API in tests
  """

  @behaviour Hcaptcha.HttpClient

  @default_verify_url "https://api.hcaptcha.com/siteverify"
  @default_timeout 5000

  @doc """
  Posts the form-encoded `body` to the verify URL.

  Returns the decoded JSON object, or `{:error, atoms}`:

    * the transport reason (`:timeout`, `:econnrefused`, ...) when the connection fails
    * `:http_error` for any other client failure
    * `:invalid_response_body` when the body is not a JSON object
    * `:unexpected_status` when the status is not 200 and the body has no `error-codes`

  ## Options

    * `:timeout` - connect and receive timeout in ms
  """
  @impl Hcaptcha.HttpClient
  def request_verification(body, options \\ []) do
    timeout = options[:timeout] || Application.get_env(:hcaptcha, :timeout, @default_timeout)

    [
      method: :post,
      url: Application.get_env(:hcaptcha, :verify_url, @default_verify_url),
      body: body,
      headers: [
        {"content-type", "application/x-www-form-urlencoded"},
        {"accept", "application/json"}
      ],
      receive_timeout: timeout,
      connect_options: [timeout: timeout],
      retry: false,
      decode_body: false
    ]
    |> Keyword.merge(Application.get_env(:hcaptcha, :req_options, []))
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
