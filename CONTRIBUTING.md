# Contributing

Thanks for helping improve DisplayRecall.

## Before opening an issue

- Search existing issues.
- Confirm the problem on the latest version or `main`.
- Remove private window titles, document names, account information, and unrelated desktop content from screenshots and logs.
- Include the macOS version, Mac model/architecture, display resolutions and arrangement, Dock position, and affected app bundle identifier.

## Development setup

1. Open `DisplayRecall.xcodeproj` in Xcode 26 or a compatible version.
2. Select your own Apple development team if you need to run the app.
3. Grant the locally built app Accessibility permission.
4. Run the `DisplayRecallTests` test target before submitting a change.

Unsigned command-line test:

```sh
xcodebuild \
  -project DisplayRecall.xcodeproj \
  -scheme DisplayRecall \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

`project.yml` is the project definition. If targets, source groups, build settings, or version fields change, run `xcodegen generate` and commit the generated Xcode project too.

## Pull requests

- Keep changes focused and explain the user-visible behavior.
- Add or update tests for matching, display mapping, retry policy, and frame handling.
- Preserve the local-only privacy model unless a public design discussion explicitly approves a change.
- Do not add private macOS APIs, hidden Spaces APIs, telemetry, or network access without prior maintainer approval.
- Update `README.md`, `README.zh-CN.md`, `PRIVACY.md`, and `CHANGELOG.md` when behavior or stored data changes.
- Do not commit signing identities, provisioning profiles, certificates, notarization credentials, personal layout files, or DerivedData.

By submitting a contribution, you agree that it is licensed under the repository's MIT License.
