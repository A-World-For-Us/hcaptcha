# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Changed

- Require Elixir 1.17 or later. CI runs on Elixir 1.17 / OTP 27 and Elixir 1.20 / OTP 29.
- Update dependencies. `httpoison` is now `~> 3.0`, which removes the vulnerable `hackney` 1.x.
- Format the code with the default line length (98).
- Package links point to `A-World-For-Us/hcaptcha` and the upstream repository.
- Documentation: install from Git, configure through `config/runtime.exs`.

### Added

- `CHANGELOG.md`, ExDoc configuration, Credo configuration (strict) and a Dialyzer ignore file.
- Dependabot updates for GitHub Actions.

### Removed

- ExCoveralls, Travis CI configuration and the `build_embedded` Mix option.

## 0.1.0

Fork of [sebastiangrebe/hcaptcha](https://github.com/sebastiangrebe/hcaptcha).

- `Hcaptcha.verify/2` checks a response token against the hCaptcha API with HTTPoison.
- `Hcaptcha.Template.display/1` renders the widget script and container, checkbox or invisible.
- `Hcaptcha.Http.MockClient` for tests without network access.
- Keys read from application config or from environment variables with `{:system, "VAR"}`.
