defmodule Hcaptcha.TemplateTest do
  use ExUnit.Case, async: true

  alias Hcaptcha.Template

  defp ids(html), do: Regex.scan(~r/id="(h-captcha-[0-9a-f]+)"/, html) |> Enum.map(&List.last/1)

  test "renders options as data attributes and leaves out nil ones" do
    html =
      Template.display(
        public_key: "my_key",
        theme: "dark",
        type: "audio",
        tabindex: 1,
        size: "compact",
        callback: "enableBtn",
        badge: "inline",
        class: "my-captcha"
      )

    assert html =~ ~s|<div class="my-captcha" id=|

    for attribute <- ~w(sitekey theme type tabindex size badge) do
      assert html =~ "data-#{attribute}="
    end

    assert html =~ ~s(callback: "enableBtn")
    refute html =~ "data-callback"

    bare = Template.display()
    assert bare =~ ~s(data-sitekey="#{Application.get_env(:hcaptcha, :public_key)}")
    refute bare =~ ~r/data-(theme|type|tabindex|size|badge|callback)|class=|=""/
  end

  test "gives each call a unique id, passed to the script as the widget id" do
    html = Template.display(size: "invisible") <> Template.display(size: "invisible")
    [id1, id2] = ids(html)

    assert id1 != id2
    assert html =~ ~s(id: "#{id1}")
    assert html =~ ~s(id: "#{id2}")
  end

  test "escapes option values in attributes" do
    html =
      Template.display(
        theme: "\"><script>alert(1)</script>",
        public_key: "a'b&c",
        class: "a\"b"
      )

    refute html =~ "\"><script>alert"
    assert html =~ ~s|data-theme="&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"|
    assert html =~ ~s(data-sitekey="a&#39;b&amp;c")
    assert html =~ ~s|class="a&quot;b"|
  end

  test "escapes values written into JavaScript" do
    html = Template.display(nonce: "\"><script>x</script>", onload: "a</script>b\u{2028}")

    refute html =~ "</script>b"
    refute html =~ "<script>x"
    assert html =~ "nonce: \"\\\"\\u003E\\u003Cscript\\u003Ex\\u003C/script\\u003E\""
    assert html =~ "onload: \"a\\u003C/script\\u003Eb\\u2028\""
    assert length(Regex.scan(~r/<\/script>/, html)) == 1
  end

  test "raises on input that is not valid UTF-8" do
    assert_raise ArgumentError, fn -> Template.display(theme: <<255, 254>>) end
    assert_raise ArgumentError, fn -> Template.display(nonce: "ab" <> <<255>> <> "cd") end
  end

  test "sets the nonce on the inline script and in its config; an empty nonce is no nonce" do
    html = Template.display(nonce: "abc")
    assert html =~ ~s(<script nonce="abc">)
    assert html =~ ~s(nonce: "abc")

    for options <- [[], [nonce: ""]] do
      html = Template.display(options)
      assert html =~ "<script>"
      assert html =~ "nonce: null"
    end
  end

  test "writes the API URL, hl, the invisible flag and the callback names into the config" do
    html = Template.display(hl: "fr&x=1")

    assert html =~
             "https://js.hcaptcha.com/1/api.js?render=explicit\\u0026onload=hcaptchaElixirTemplateOnload\\u0026hl=fr%26x%3D1"

    refute Template.display() =~ "hl="

    assert Template.display(size: "invisible") =~ "invisible: true"
    assert Template.display(size: "compact") =~ "invisible: false"

    html = Template.display(size: "invisible", onload: "myLoad", callback: "myCallback")
    assert html =~ ~s(onload: "myLoad")
    assert html =~ ~s(callback: "myCallback")

    html = Template.display(size: "compact", callback: "myCallback")
    assert html =~ ~s(callback: "myCallback")
    refute html =~ "data-callback"
  end
end
