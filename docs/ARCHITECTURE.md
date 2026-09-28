# Architecture

DisplayRecall is a small SwiftUI menu bar application built on public macOS frameworks.

## Main flow

1. `DisplayInventory` captures connected displays, stable display identifiers, roles, geometry, and visible frames.
2. `AccessibilityClient` enumerates restorable windows through Accessibility and associates public Core Graphics runtime window IDs when possible.
3. `RestoreEngine` captures a normalized snapshot or maps saved frames to the current display topology.
4. `WindowMatcher` matches saved and live windows using bundle identity, runtime identity, hashed metadata, and an ordinal fallback.
5. `LayoutStore` atomically writes the current snapshot and one backup under Application Support.
6. `DisplayMonitor` and `AppModel` debounce topology changes and perform delayed retries for apps that expose windows late.

## Local command flow

1. macOS routes `displayrecall://save`, `displayrecall://restore`, or `displayrecall://status` to the installed app.
2. `DisplayRecallAppDelegate` forwards the URL to `AppModel`.
3. `DisplayRecallCommandRequest` accepts only the supported action and an optional request UUID.
4. `AppModel` performs the same save and restore paths used by the menu bar and background monitor.
5. `CommandStatusStore` atomically overwrites `command-status-v1.json` with a pending, completed, or failed result.

The URL scheme is a local control surface, not an authorization boundary. Commands never bypass macOS Accessibility permission, and the app does not open a network listener. Callers should generate a unique request UUID and wait only for the matching result.

## Coordinate model

Saved window frames are normalized against `NSScreen.visibleFrame`, not the full display bounds. Restore maps those ratios into the target display's visible frame and then clamps the result. Additional policies handle menu bar safe areas, application minimum sizes, and Docks on different edges.

## Privacy boundary

Window titles and document URLs are used only to improve matching and are persisted as SHA-256 digests. The app does not capture pixels, window contents, keyboard input, or clipboard data. See `PRIVACY.md` for the complete stored schema.

## Deliberate limitations

- No private Spaces APIs.
- No automatic launch of closed applications.
- No full-screen, minimized, or modal-window restoration.
- No window stacking-order restoration.
- One built-in plus one external display in the first release.

Changes that expand these boundaries should begin with a public design issue.
