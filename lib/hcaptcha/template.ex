defmodule Hcaptcha.Template do
  @moduledoc """
  Renders an hCaptcha widget for forms rendered by controllers, not LiveView `phx-submit` forms.

  The API script loads once per page, so several widgets can share a page. Do not load `api.js`
  yourself on such a page.
  """

  @script_path Path.join(__DIR__, "template.js")
  @external_resource @script_path
  @script File.read!(@script_path)

  @api_url "https://js.hcaptcha.com/1/api.js"
  @data_options [:theme, :type, :tabindex, :size, :badge]

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
  token. If the script does not load, or the challenge neither answers nor opens within 10
  seconds, the form is sent without a token.
  """
  @spec display(keyword()) :: String.t()
  def display(options \\ []) do
    id = "h-captcha-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    invisible? = options[:size] == "invisible"
    nonce = if options[:nonce] == "", do: nil, else: options[:nonce]

    attributes =
      [
        class: options[:class],
        id: id,
        "data-sitekey": options[:public_key] || Hcaptcha.public_key()
      ] ++
        for(key <- @data_options, do: {:"data-#{key}", options[key]})

    container =
      ~s(<div#{attributes(attributes)}></div>)

    config =
      "{id: #{js(id)}, invisible: #{invisible?}, src: #{js(api_url(options))}, " <>
        "nonce: #{js(nonce)}, callback: #{js(options[:callback])}, " <>
        "onload: #{js(options[:onload])}}"

    script =
      "<script#{attributes(nonce: nonce)}>\n" <>
        String.replace(@script, "__CONFIG__", fn _ -> config end) <> "</script>"

    container <> "\n" <> script
  end

  defp api_url(options) do
    query =
      [render: "explicit", onload: "hcaptchaElixirTemplateOnload"] ++
        if(options[:hl], do: [hl: options[:hl]], else: [])

    @api_url <> "?" <> URI.encode_query(query)
  end

  defp attributes(attributes) do
    for {name, value} <- attributes, not is_nil(value), into: "" do
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

  defp js(nil), do: "null"

  defp js(value) do
    escaped =
      for <<char::utf8 <- utf8!(value)>>, into: "" do
        case char do
          ?" -> "\\\""
          ?\\ -> "\\\\"
          c when c in [?<, ?>, ?&, ?', 0x2028, 0x2029] or c < 0x20 -> unicode_escape(c)
          c -> <<c::utf8>>
        end
      end

    ~s("#{escaped}")
  end

  defp utf8!(value) do
    string = to_string(value)

    if String.valid?(string) do
      string
    else
      raise ArgumentError, "hcaptcha template option is not valid UTF-8: #{inspect(string)}"
    end
  end

  defp unicode_escape(char) do
    "\\u" <> String.pad_leading(Integer.to_string(char, 16), 4, "0")
  end
end
