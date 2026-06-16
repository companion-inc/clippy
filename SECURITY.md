# Security

Clippy is a local desktop app that can read screen context, listen to the
microphone when voice mode is active, and run approved computer-use actions.
Security reports are important.

## Reporting

Do not open public issues for vulnerabilities involving credentials, local files,
screen capture, microphone capture, app signing, release artifacts, or desktop
automation. Use GitHub's private vulnerability reporting for this repository
when available.

## Handling Secrets

Do not commit:

- API keys or provider tokens.
- CLI auth files.
- `.netrc`.
- Keychain exports.
- App support databases.
- Full screenshots or screen recordings from private desktops.

Clippy should report credential status as `present` or `missing`; it should not
print token values or token prefixes.
