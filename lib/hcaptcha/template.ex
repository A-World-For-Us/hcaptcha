defmodule Hcaptcha.Template do
  @moduledoc """
  Renders an hCaptcha widget for forms rendered by controllers, not LiveView `phx-submit` forms.

  The API script loads once per page, so several widgets can share a page. Do not load `api.js`
  yourself on such a page.
  """

  @script_path Path.join(__DIR__, "template.js")
  @external_resource @script_path
  [script_head, script_tail] = String.split(File.read!(@script_path), "__CONFIG__")
  @script_head script_head
  @script_tail script_tail

  @api_url "https://js.hcaptcha.com/1/api.js"
  @widget_options [:theme, :type, :tabindex, :size, :badge]

  @doc """
  Returns the widget HTML as a string. In a HEEx template, write
  `{Hcaptcha.Template.display(size: "invisible") |> raw()}`.

  ## Options

    * `:public_key` - the sitekey (default `Hcaptcha.public_key/0`)
    * `:theme`, `:type`, `:tabindex`, `:size`, `:badge` - hCaptcha widget settings
    * `:hl` - widget language. The first call on a page sets it.
    * `:onload` - global JavaScript function called when the API is ready. The first call on a
      page sets it.
    * `:callback` - global JavaScript function called with the token
    * `:class` - CSS class of the container
    * `:nonce` - CSP nonce for the inline script and the API script

  With `size: "invisible"`, submitting the form runs the challenge, then sends the form with the
  token. If the script does not load within 10 seconds, or the challenge neither answers nor opens
  within 20 seconds, the form is sent without a token. Use one widget per form.

  Raises when `:class`, `:nonce` or a value sent to the script is not valid UTF-8.
  """
  @spec display(keyword()) :: String.t()
  def display(options \\ []) do
    id = "h-captcha-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)

    config = %{
      id: id,
      invisible: options[:size] == "invisible",
      src: api_url(options),
      nonce: options[:nonce],
      callback: options[:callback],
      onload: options[:onload],
      widget: widget(options)
    }

    IO.iodata_to_binary([
      "<div",
      attributes(class: options[:class], id: id),
      "></div>\n<script",
      attributes(nonce: options[:nonce]),
      ">\n",
      @script_head,
      Jason.encode!(config, escape: :html_safe),
      @script_tail,
      "</script>"
    ])
  end

  defp widget(options) do
    options
    |> Keyword.take(@widget_options)
    |> Map.new()
    |> Map.put(:sitekey, options[:public_key] || Hcaptcha.public_key())
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {key, to_string(value)} end)
  end

  defp api_url(options) do
    query =
      [render: "explicit"] ++ if(options[:hl], do: [hl: options[:hl]], else: [])

    @api_url <> "?" <> URI.encode_query(query)
  end

  defp attributes(attributes) do
    for {name, value} <- attributes, value not in [nil, ""], into: "" do
      ~s( #{name}="#{escape_html(utf8!(value))}")
    end
  end

  defp escape_html(string) do
    for <<char <- string>>, into: "" do
      case char do
        ?& -> "&amp;"
        ?< -> "&lt;"
        ?> -> "&gt;"
        ?" -> "&quot;"
        ?' -> "&#39;"
        _ -> <<char>>
      end
    end
  end

  defp utf8!(value) do
    string = to_string(value)

    if String.valid?(string) do
      string
    else
      raise ArgumentError, "hcaptcha template option is not valid UTF-8: #{inspect(string)}"
    end
  end
end
