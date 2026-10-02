# Contributing

## Pull requests

1. Fork the project
2. Create a topic branch
3. Make logically-grouped commits with clear commit messages (Conventional Commits)
4. Push commits to your fork
5. Open a pull request against `master`

## Issues

If you believe there is a bug, give the maintainers enough detail to reproduce it,
or a link to an app that shows the problem.

## Development

1. Install the versions in `.tool-versions` (for example with [asdf](https://asdf-vm.com)).
   The library supports Elixir 1.17 and later.
2. `mix deps.get && mix compile`

Checks to run before you open a pull request:

1. `mix format --check-formatted`
2. `mix compile --warnings-as-errors`
3. `mix test`
4. `mix credo --strict`
5. `mix dialyzer` (the first run builds the PLTs and is slow)

`.git-blame-ignore-revs` lists commits that only change formatting. To skip them in `git blame`:

```
git config blame.ignoreRevsFile .git-blame-ignore-revs
```
