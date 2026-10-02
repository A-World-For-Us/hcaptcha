# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Changed

- Require Elixir 1.17 or later and Erlang/OTP 26 or later. OTP 26 is the floor of `quic`, which `hackney` 4 depends on. CI covers Elixir 1.17 / OTP 27 and Elixir 1.20 / OTP 29.
- Update `httpoison` to `~> 3.0`, which uses `hackney` 4. This removes `hackney` 1.x, which has known security advisories.
- Install from Git: `{:hcaptcha, github: "A-World-For-Us/hcaptcha", branch: "master"}`. The package is not published on Hex.

## 0.1.0

State of the fork at the time it was taken from [sebastiangrebe/hcaptcha](https://github.com/sebastiangrebe/hcaptcha).

- `Hcaptcha.verify/2` checks a response token against the hCaptcha API with HTTPoison.
- `Hcaptcha.Template.display/1` renders the widget script and container, checkbox or invisible.
- `Hcaptcha.Http.MockClient` for tests without network access.
- Keys read from application config or from environment variables with `{:system, "VAR"}`.
