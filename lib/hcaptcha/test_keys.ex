defmodule Hcaptcha.TestKeys do
  @moduledoc """
  The hCaptcha [test keys](https://docs.hcaptcha.com/#integration-testing-test-keys).

  The real API accepts `token/0` when the request uses `secret/0`.
  """

  @doc "Test sitekey. Renders a widget that always passes."
  @spec sitekey() :: String.t()
  def sitekey, do: "10000000-ffff-ffff-ffff-000000000001"

  @doc "Test secret, the match of `sitekey/0`."
  @spec secret() :: String.t()
  def secret, do: "0x0000000000000000000000000000000000000000"

  @doc "Token the test secret accepts."
  @spec token() :: String.t()
  def token, do: "10000000-aaaa-bbbb-cccc-000000000001"
end
