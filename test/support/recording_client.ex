defmodule Hcaptcha.RecordingClient do
  @moduledoc false
  @behaviour Hcaptcha.HttpClient

  @impl true
  def request_verification(body, options) do
    send(self(), {:request_verification, body, options})
    {:ok, %{"success" => true}}
  end
end
