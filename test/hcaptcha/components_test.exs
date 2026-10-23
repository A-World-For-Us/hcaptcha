defmodule Hcaptcha.ComponentsTest do
  use ExUnit.Case, async: false

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Hcaptcha.Components

  defp render_widget(assigns) do
    rendered_to_string(~H"<.hcaptcha {@attrs} />")
  end

  defp widget(attrs), do: render_widget(%{attrs: Map.new(attrs)})

  test "renders the element the hook expects" do
    html = widget(id: "captcha")

    assert html =~ ~s(id="captcha")
    assert html =~ ~s(phx-hook="Hcaptcha")
    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(data-sitekey="#{Hcaptcha.TestKeys.sitekey()}")
    assert html =~ ~s(data-src="https://js.hcaptcha.com/1/api.js?render=explicit")
  end

  test "renders each attribute, escaped" do
    cases = [
      {[sitekey: "other"], ~s(data-sitekey="other")},
      {[hl: "fr"], "render=explicit&amp;hl=fr"},
      {[class: "mt-2"], ~s(class="mt-2")},
      {[hl: ~s("><script>)], "hl=%22%3E%3Cscript%3E"}
    ]

    for {attrs, expected} <- cases do
      html = widget([id: "c"] ++ attrs)

      assert html =~ expected
      refute html =~ "<script>"
    end
  end

  test "raises when no sitekey resolves" do
    original = Application.fetch_env!(:hcaptcha, :public_key)
    Application.delete_env(:hcaptcha, :public_key)
    on_exit(fn -> Application.put_env(:hcaptcha, :public_key, original) end)

    assert_raise ArgumentError, ~r/no sitekey/, fn -> widget(id: "c") end
    assert widget(id: "c", sitekey: "given") =~ "given"
  end

  test "execute pushes the event with the widget id" do
    socket = %Phoenix.LiveView.Socket{}

    pushed = execute(socket, "captcha")

    assert pushed.private.live_temp.push_events == [["hcaptcha:execute", %{id: "captcha"}]]
  end
end
