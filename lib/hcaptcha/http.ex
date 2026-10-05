defmodule Hcaptcha.Http do
  @moduledoc """
  Sends verification requests to the hCaptcha API with `Req`.

  Config keys: `:verify_url`, `:timeout` (5000 ms) and `:req_options`, extra options for
  `Req.new/1` such as a proxy or `plug: {Req.Test, Hcaptcha.Http}` in tests.

  `:req_options` cannot change the request itself, its retries or its redirects, so the secret
  goes only to the configured URL.
  """

  @behaviour Hcaptcha.HttpClient

  @default_verify_url "https://api.hcaptcha.com/siteverify"
  @default_timeout 5000

  @doc """
  Posts the form-encoded `body` to the verify URL.

  Returns the decoded JSON object, or `{:error, atoms}`: the transport reason (`:timeout`, ...),
  `:http_error`, `:invalid_response_body` or `:unexpected_status`.

  The `:timeout` option, in ms, is both the connect and the receive timeout.
  """
  @impl Hcaptcha.HttpClient
  def request_verification(body, options \\ []) do
    timeout = options[:timeout] || Application.get_env(:hcaptcha, :timeout, @default_timeout)
    user_options = Application.get_env(:hcaptcha, :req_options, [])
    connect_options = Keyword.put(user_options[:connect_options] || [], :timeout, timeout)

    user_options
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
      decode_body: false,
      into: nil
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
