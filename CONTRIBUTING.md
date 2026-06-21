# Contributing

Thanks for helping improve Sidekick.

## Start Here

Before changing runtime behavior, read:

- `Docs/STATUS.md`
- `Docs/Handbook/README.md`
- `Docs/Handbook/04-runtime-contracts.md`
- `Docs/Handbook/05-verification-matrix.md`

Those files describe the current product boundary, verification expectations,
and known implementation contracts.

## Development

```sh
swift test
swift build
```

For a packaged app:

```sh
Scripts/package-sidekick-app.sh release
open -n .build/release/Sidekick.app
```

## Pull Requests

- Keep changes focused.
- Include tests for behavior changes.
- Update docs when user-visible behavior, permissions, packaging, or release
  assets change.
- Do not commit local credentials, screenshots, auth files, `.netrc`, app
  support databases, or generated research clones.

## Public Runtime Boundary

Sidekick is a local-first desktop app, not a hosted assistant service. Keep secrets
on the user's machine, keep approvals explicit, and make any desktop action
traceable to a user-visible request.
