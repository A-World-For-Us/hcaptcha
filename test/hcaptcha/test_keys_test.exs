defmodule Hcaptcha.TestKeysTest do
  use ExUnit.Case, async: true

  alias Hcaptcha.TestKeys

  test "returns the documented hCaptcha test keys" do
    assert TestKeys.sitekey() == "10000000-ffff-ffff-ffff-000000000001"
    assert TestKeys.secret() == "0x0000000000000000000000000000000000000000"
    assert TestKeys.token() == "10000000-aaaa-bbbb-cccc-000000000001"
  end
end
