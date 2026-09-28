# DisplayRecall

[简体中文](README.zh-CN.md)

DisplayRecall is a local-first macOS menu bar utility that remembers ordinary window layouts across the built-in display and one external display. When a different external display is connected, it restores windows proportionally within that display's usable area.

## Highlights

- Restores the current desktop's ordinary, non-minimized, non-full-screen windows.
- Reacts to display connection, resolution, and wake changes, with delayed retries for apps that expose their windows late.
- Preserves the order of multiple similar windows when public Core Graphics window IDs remain available.
- Compensates for menu bars, left/right/bottom Docks, and application-enforced minimum window sizes.
- Stores window titles and document URLs only as SHA-256 digests, never as plaintext.
- Runs locally with no network or screen-recording permission.
- Uses public macOS APIs and does not use private Spaces APIs.

See [Privacy](PRIVACY.md) for the exact data fields stored on disk.

## Requirements

- macOS 14 or later
- Xcode 26 or a compatible version
- Accessibility permission when running the app
- XcodeGen 2.45 or later only when regenerating the Xcode project

The generated `DisplayRecall.xcodeproj` is committed, so XcodeGen is not required just to build or test the checked-in project.

## Build and test

Clone the repository, open `DisplayRecall.xcodeproj`, select your own development team, and run the `DisplayRecall` scheme.

For an unsigned CI-style test:

```sh
xcodebuild \
  -project DisplayRecall.xcodeproj \
  -scheme DisplayRecall \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

When changing `project.yml`, regenerate and commit the Xcode project:

```sh
xcodegen generate
```

macOS associates Accessibility authorization with the app's signing identity. A self-built copy may need permission again after its signing identity changes. Official binary releases will use a stable Developer ID identity.

## Use

1. Connect an external display and arrange the windows.
2. Open the DisplayRecall menu bar item.
3. Choose **Save Current Dual-Display Layout**.
4. Connect another external display. DisplayRecall restores the saved layout proportionally.

## Local command interface

DisplayRecall 0.1.8 and later accepts local URL commands for Codex Skills, Shortcuts, and other on-device automation:

    open -g "displayrecall://save?request=my-save"
    open -g "displayrecall://restore?request=my-restore"
    open -g "displayrecall://status?request=my-status"

The installed DisplayRecall app executes commands with its existing Accessibility permission and writes machine-readable results to:

    ~/Library/Application Support/com.zomeelee.DisplayRecall/command-status-v1.json

The interface opens no network listener and does not bypass macOS Accessibility authorization.

### Install the Codex Skill

The repository includes an on-demand controller Skill. Install it into your personal Codex skills directory:

    mkdir -p ~/.codex/skills
    cp -R skills/displayrecall-window-layout ~/.codex/skills/

Then invoke `$displayrecall-window-layout` to inspect readiness, save the current layout, or restore the remembered layout. The native menu bar app remains responsible for Accessibility access and automatic display hot-plug restoration.

## Known limitations

- Only the built-in display plus one external display is supported in the first release.
- macOS does not provide a public API for reliably moving another app's window to a specific Space, so only the currently accessible desktop is covered.
- Full-screen, minimized, modal, and very small utility windows are ignored.
- Some apps may reject requested frames or enforce a minimum size.
- Closed apps are not launched, and window stacking order is not restored.

## Project policy

- No telemetry or network access without prior public design discussion.
- No private macOS APIs.
- Privacy-sensitive changes require tests and documentation updates.

See [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), and [Architecture](docs/ARCHITECTURE.md).

## Releases

Source builds are available from the repository. A notarized official binary will be published only after it is signed with the project's Developer ID certificate. Do not treat unsigned third-party builds as official releases.

## License

DisplayRecall is available under the [MIT License](LICENSE).
