defmodule Hcaptcha.TestAdapter do
  @moduledoc false

  def run(request), do: Application.fetch_env!(:hcaptcha, :test_adapter).(request)

  def install(fun) do
    original = Application.fetch_env(:hcaptcha, :req_options)
    Application.put_env(:hcaptcha, :test_adapter, fun)
    Application.put_env(:hcaptcha, :req_options, adapter: __MODULE__)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:hcaptcha, :test_adapter)

      case original do
        {:ok, value} -> Application.put_env(:hcaptcha, :req_options, value)
        :error -> Application.delete_env(:hcaptcha, :req_options)
      end
    end)
  end
end
