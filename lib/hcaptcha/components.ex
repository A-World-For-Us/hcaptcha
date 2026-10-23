if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Hcaptcha.Components do
    @moduledoc """
    Invisible hCaptcha widget for LiveView `phx-submit` forms, run by the `Hcaptcha` JavaScript
    hook. See the README.
    """

    use Phoenix.Component

    @doc """
    Makes the hook of the widget `id` run the challenge, then post the form.

    Do not call it in the render that adds the widget: the hook is not mounted yet.
    """
    @spec execute(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
    def execute(socket, id) do
      Phoenix.LiveView.push_event(socket, "hcaptcha:execute", %{id: id})
    end

    @doc """
    Renders the widget inside a `<form>` that posts to a controller.

    Raises `ArgumentError` when neither the `sitekey` attribute nor `:public_key` is set.
    """
    attr(:id, :string, required: true)
    attr(:sitekey, :string, default: nil)
    attr(:hl, :string, default: nil)
    attr(:class, :string, default: nil)
    attr(:rest, :global)

    @spec hcaptcha(map()) :: Phoenix.LiveView.Rendered.t()
    def hcaptcha(assigns) do
      sitekey = assigns.sitekey || Hcaptcha.public_key()

      if is_nil(sitekey) do
        raise ArgumentError,
              "hcaptcha: no sitekey. Pass the sitekey attribute or set :public_key in the config"
      end

      assigns =
        assigns
        |> assign(:sitekey, sitekey)
        |> assign(:src, Hcaptcha.Template.api_url(hl: assigns.hl))

      ~H"""
      <div
        id={@id}
        class={@class}
        phx-hook="Hcaptcha"
        phx-update="ignore"
        data-sitekey={@sitekey}
        data-src={@src}
        {@rest}
      >
      </div>
      """
    end
  end
end
