defmodule Hcaptcha.TemplateTest do
  use ExUnit.Case, async: true

  alias Hcaptcha.Template

  defp ids(html), do: Regex.scan(~r/id="(h-captcha-[0-9a-f]+)"/, html) |> Enum.map(&List.last/1)

  describe "display/1 container" do
    test "renders every option as a data attribute" do
      html =
        Template.display(
          public_key: "my_key",
          theme: "dark",
          type: "audio",
          tabindex: 1,
          size: "compact",
          callback: "enableBtn",
          badge: "inline"
        )

      assert html =~ ~s(class="h-captcha")
      assert html =~ ~s(data-sitekey="my_key")
      assert html =~ ~s(data-theme="dark")
      assert html =~ ~s(data-type="audio")
      assert html =~ ~s(data-tabindex="1")
      assert html =~ ~s(data-size="compact")
      assert html =~ ~s(data-callback="enableBtn")
      assert html =~ ~s(data-badge="inline")
    end

    test "reads the public key from the application config by default" do
      key = Application.get_env(:hcaptcha, :public_key)
      assert Template.display() =~ ~s(data-sitekey="#{key}")
    end

    test "leaves out data attributes whose option is nil" do
      html = Template.display(public_key: "k")

      refute html =~ "data-theme"
      refute html =~ "data-type"
      refute html =~ "data-tabindex"
      refute html =~ "data-size"
      refute html =~ "data-badge"
      refute html =~ "data-callback"
      refute html =~ ~s(="")
    end

    test "gives each call a unique id" do
      [id1] = ids(Template.display())
      [id2] = ids(Template.display())
      assert id1 != id2
    end

    test "escapes option values in attributes" do
      html = Template.display(theme: "\"><script>alert(1)</script>", public_key: "a'b&c")

      refute html =~ "\"><script>alert"
      assert html =~ ~s|data-theme="&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"|
      assert html =~ ~s(data-sitekey="a&#39;b&amp;c")
    end
  end

  describe "display/1 script" do
    test "loads the API with explicit render and a fixed onload name" do
      html = Template.display()

      assert html =~
               "https://js.hcaptcha.com/1/api.js?render=explicit\\u0026onload=hcaptchaOnload"

      refute html =~ "hl="
    end

    test "url-encodes hl" do
      html = Template.display(hl: "fr&x=1")
      assert html =~ "hl=fr%26x%3D1"
    end

    test "passes onload and callback names to the script" do
      html = Template.display(size: "invisible", onload: "myLoad", callback: "myCallback")
      assert html =~ ~s(onload: "myLoad")
      assert html =~ ~s(callback: "myCallback")
      refute html =~ "data-callback"
    end

    test "sets the nonce on the inline script and on the script it adds" do
      html = Template.display(nonce: "abc")
      assert html =~ ~s(<script nonce="abc">)
      assert html =~ ~s(nonce: "abc")
      assert html =~ "script.nonce = cfg.nonce"
    end

    test "has no nonce attribute without the option" do
      html = Template.display()
      assert html =~ "<script>"
      assert html =~ "nonce: null"
    end

    test "escapes values written into JavaScript" do
      html = Template.display(nonce: "\"><script>x</script>", onload: "a</script>b\u{2028}")

      refute html =~ "</script>b"
      refute html =~ "<script>x"
      assert html =~ "nonce: \"\\\"\\u003E\\u003Cscript\\u003Ex\\u003C/script\\u003E\""
      assert html =~ "onload: \"a\\u003C/script\\u003Eb\\u2028\""
      assert length(Regex.scan(~r/<\/script>/, html)) == 1
    end
  end

  describe "display/1 invisible mode" do
    test "enables the invisible flow only for size invisible" do
      assert Template.display(size: "invisible") =~ "invisible: true"
      assert Template.display(size: "compact") =~ "invisible: false"
      assert Template.display() =~ "invisible: false"
    end

    test "listens on the form of the widget only" do
      html = Template.display(size: "invisible")

      assert html =~ ~s|el.closest("form")|
      refute html =~ ~s|querySelectorAll("form")|
      refute html =~ ~s|div[class="h-captcha"]|
    end

    test "releases the guard when the challenge expires or closes" do
      html = Template.display(size: "invisible")
      assert html =~ ~s|"chalexpired-callback"|
      assert html =~ ~s|"close-callback"|
    end

    test "defines no global function other than hcaptchaOnload and hcaptchaLoader" do
      html = Template.display(size: "invisible")

      refute html =~ "function hcaptchaCallback"
      refute html =~ "function onSubmit"
      assert html =~ "w.hcaptchaOnload = function"
      assert html =~ "w.hcaptchaLoader"
    end

    test "two calls share the loader and keep separate widget ids" do
      html = Template.display(size: "invisible") <> Template.display(size: "invisible")
      [id1, id2] = ids(html)

      assert id1 != id2
      assert html =~ ~s(id: "#{id1}")
      assert html =~ ~s(id: "#{id2}")
    end
  end
end
