defmodule Hcaptcha.Template do
  @moduledoc """
  Renders the HTML that shows an hCaptcha widget.

  `display/1` returns a string. In Phoenix templates, wrap it with `raw/1`.

  The output holds a container `<div>` and an inline `<script>`. The script loads the hCaptcha
  API once per page, then renders the widget in the container. Several calls on one page work:
  they share one API script. The `:hl` option of the first call on a page sets the language.

  The template is for forms rendered by controllers. LiveView `phx-submit` forms are not
  supported. Do not load `api.js` yourself on a page that uses `display/1`.
  """

  @script_path Path.join(__DIR__, "template.js")
  @external_resource @script_path
  @script File.read!(@script_path)

  @api_url "https://js.hcaptcha.com/1/api.js"
  @data_options [:theme, :type, :tabindex, :size, :badge]

  @doc """
  Returns the HTML of an hCaptcha widget.

  ## Options

    * `:public_key` - the site key. Defaults to `:public_key` from the `:hcaptcha` config.
    * `:theme`, `:type`, `:tabindex`, `:size`, `:badge` - written as `data-*` attributes and
      passed to hCaptcha. Options that are `nil` are left out.
    * `:hl` - language of the widget. Only the first call on a page has an effect.
    * `:onload` - name of a global JavaScript function, called once without arguments when the
      hCaptcha API is ready, before the first widget that names it renders.
    * `:callback` - name of a global JavaScript function, called with the token when the
      challenge succeeds. In `"invisible"` mode the form is submitted after it returns.
    * `:class` - CSS class of the container. The container has no class by default.
    * `:nonce` - CSP nonce, set on the inline script and on the script that loads the API.

  ## Invisible mode

  With `size: "invisible"` the widget runs when the form that contains it is submitted. The
  submit event of other forms is untouched. The challenge runs once per submit, then the form
  is sent again with the token and the clicked button. If the hCaptcha script fails to load,
  is not ready within 10 seconds, or fails to render the widget, the form is sent without a
  token.
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
        for(key <- @data_options, do: {:"data-#{key}", options[key]}) ++
        if(invisible?, do: [], else: [{:"data-callback", options[:callback]}])

    container =
      ~s(<div#{attributes(attributes)}></div>)

    config =
      "{id: #{js(id)}, invisible: #{invisible?}, src: #{js(api_url(options))}, " <>
        "nonce: #{js(nonce)}, callback: #{js(invisible? && options[:callback])}, " <>
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
  defp js(false), do: "null"

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
