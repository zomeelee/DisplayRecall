# Privacy

DisplayRecall is designed to work locally. It does not include analytics, telemetry, advertising, crash-upload, or network code.

## Accessibility permission

DisplayRecall needs macOS Accessibility permission to enumerate ordinary application windows and change their position and size. It does not use Accessibility permission to read keystrokes or automate application content.

## Data stored on disk

The current layout and one backup are stored under:

```text
~/Library/Application Support/<bundle-identifier>/layout-v1.json
~/Library/Application Support/<bundle-identifier>/layout-v1.backup.json
~/Library/Application Support/<bundle-identifier>/command-status-v1.json
```

The official build uses `com.zomeelee.DisplayRecall` as its bundle identifier.

The files can contain:

- save time and layout schema version;
- display name, display UUID, role, rotation, and visible frame;
- application name and bundle identifier;
- Accessibility role, subrole, identifier, and window ordinal;
- normalized and source window frames;
- runtime process and Core Graphics window IDs;
- SHA-256 digests of window titles and document URLs.

Window titles and document URLs are not stored as plaintext. A digest still allows equality comparisons and may be guessable when the original value comes from a small, predictable set, so layout files should still be treated as private metadata.

`command-status-v1.json` is overwritten for each local command. It can contain a request UUID, command name, state, timestamps, permission and display readiness, saved external-display name, and aggregate save or restore counts. It does not contain window titles, document URLs, or window geometry.

## Data not collected

DisplayRecall does not store screenshots, screen pixels, window contents, typed text, clipboard data, browser history, or account credentials.

## Network access

The application does not send layout data anywhere and does not require a network connection.

## Logs

Diagnostic logs can include application bundle identifiers, window ordinals, runtime window IDs, restore counts, and window geometry. They do not intentionally log plaintext window titles or document URLs. Review logs before sharing them publicly.

## Deleting data

Use the menu command that reveals the data folder, quit DisplayRecall, and delete the layout and backup JSON files. Disabling or removing the app does not upload or remotely retain a copy.

Privacy-sensitive changes must update this document and include appropriate tests.
