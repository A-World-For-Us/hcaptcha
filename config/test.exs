import Config

config :hcaptcha,
  secret: "0x0000000000000000000000000000000000000000",
  public_key: "10000000-ffff-ffff-ffff-000000000001",
  req_options: [plug: {Req.Test, Hcaptcha.Http}]
