defmodule Hcaptcha.ConfigTest do
  use ExUnit.Case, async: false

  alias Hcaptcha.Config

  setup do
    on_exit(fn -> Application.delete_env(:hcaptcha, :config_test_key) end)
  end

  test "get_env/3 reads application config" do
    Application.put_env(:hcaptcha, :config_test_key, "value")

    assert Config.get_env(:hcaptcha, :config_test_key) == "value"
  end

  test "get_env/3 returns the default for a missing key" do
    assert Config.get_env(:hcaptcha, :config_test_key) == nil
    assert Config.get_env(:hcaptcha, :config_test_key, :default) == :default
  end

  test "get_env/3 returns {:system, _} tuples unchanged" do
    Application.put_env(:hcaptcha, :config_test_key, {:system, "HOME"})

    assert Config.get_env(:hcaptcha, :config_test_key) == {:system, "HOME"}
  end
end
