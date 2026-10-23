defmodule Hcaptcha.TemplateTest do
  use ExUnit.Case, async: true

  alias Hcaptcha.Template

  defp ids(html), do: Regex.scan(~r/id="(h-captcha-[0-9a-f]+)"/, html) |> Enum.map(&List.last/1)

  defp config(html) do
    [_, json] = Regex.run(~r/run\((\{.*\})\);\}\)\(\);\n<\/script>\z/s, html)
    Jason.decode!(json)
  end

  test "puts the widget settings in the config and leaves out nil ones" do
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
    refute html =~ "data-"

    assert %{
             "widget" => %{
               "sitekey" => "my_key",
               "theme" => "dark",
               "type" => "audio",
               "tabindex" => "1",
               "size" => "compact",
               "badge" => "inline"
             },
             "callback" => "enableBtn"
           } = config(html)

    bare = Template.display()
    assert config(bare)["widget"] == %{"sitekey" => Application.get_env(:hcaptcha, :public_key)}
    [container | _] = String.split(bare, "\n", parts: 2)
    refute container =~ ~r/class=|=""/
  end

  test "gives each call a unique id, passed to the script as the widget id" do
    html = Template.display(size: "invisible") <> Template.display(size: "invisible")
    [id1, id2] = ids(html)

    assert id1 != id2
    assert html =~ ~s("id":"#{id1}")
    assert html =~ ~s("id":"#{id2}")
  end

  test "escapes class and nonce in attributes" do
    html = Template.display(class: "a\"b<c", nonce: "a'b&c")

    assert html =~ ~s|class="a&quot;b&lt;c"|
    assert html =~ ~s(<script nonce="a&#39;b&amp;c">)
  end

  test "escapes values written into JavaScript" do
    html =
      Template.display(
        nonce: "\"><script>x</script>",
        onload: "a</script>b\u{2028}",
        theme: "\"><script>alert(1)</script>"
      )

    refute html =~ "</script>b"
    refute html =~ "<script>x"
    refute html =~ "<script>alert"
    assert length(Regex.scan(~r/<\/script>/, html)) == 1

    decoded = config(html)
    assert decoded["nonce"] == "\"><script>x</script>"
    assert decoded["onload"] == "a</script>b\u{2028}"
    assert decoded["widget"]["theme"] == "\"><script>alert(1)</script>"
  end

  test "sends every widget setting as a string" do
    widget = config(Template.display(theme: ~c"dark", tabindex: 2, badge: :inline))["widget"]

    assert %{"theme" => "dark", "tabindex" => "2", "badge" => "inline"} = widget
  end

  test "raises on input that is not valid UTF-8" do
    assert_raise Jason.EncodeError, fn -> Template.display(theme: <<255, 254>>) end
    assert_raise ArgumentError, fn -> Template.display(nonce: "ab" <> <<255>> <> "cd") end
    assert_raise ArgumentError, fn -> Template.display(class: <<255>>) end
  end

  test "sets the nonce on the inline script and in its config; an empty nonce is no attribute" do
    html = Template.display(nonce: "abc")
    assert html =~ ~s(<script nonce="abc">)
    assert config(html)["nonce"] == "abc"

    for options <- [[], [nonce: ""]] do
      html = Template.display(options)
      assert html =~ "<script>"
      assert config(html)["nonce"] in [nil, ""]
    end
  end

  test "writes the API URL, hl, the invisible flag and the callback names into the config" do
    assert config(Template.display(hl: "fr&x=1"))["src"] ==
             "https://js.hcaptcha.com/1/api.js?render=explicit&hl=fr%26x%3D1"

    refute config(Template.display())["src"] =~ "hl="

    assert config(Template.display(size: "invisible"))["invisible"] == true
    assert config(Template.display(size: "compact"))["invisible"] == false

    invisible =
      config(Template.display(size: "invisible", onload: "myLoad", callback: "myCallback"))

    assert %{"onload" => "myLoad", "callback" => "myCallback"} = invisible

    checkbox = config(Template.display(size: "compact", callback: "myCallback"))
    assert checkbox["callback"] == "myCallback"
  end
end
