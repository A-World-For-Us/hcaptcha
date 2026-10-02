case Application.get_env(:hcaptcha, :req_options, [])[:plug] do
  {Req.Test, _name} ->
    :ok

  other ->
    raise "config/test.exs must set req_options: [plug: {Req.Test, ...}], got plug: #{inspect(other)}. " <>
            "Without it the suite would call the real hCaptcha API."
end

ExUnit.start()
