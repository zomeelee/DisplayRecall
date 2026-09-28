# DisplayRecall Skill troubleshooting

## Installed app is missing

The Skill expects `/Applications/DisplayRecall.app`. Build and install DisplayRecall 0.1.8 or later, or set `DISPLAYRECALL_APP_PATH` to another installed app bundle.

## Command interface is missing

The installed `Info.plist` must register the `displayrecall` URL scheme. An older app can still restore automatically but cannot receive Skill commands.

## Command times out

1. Run the bundled `inspect` command.
2. Confirm the installed app exposes the command interface.
3. Launch DisplayRecall once.
4. Confirm the process is running.
5. Run `status` once.

Do not loop indefinitely. A timeout can mean Launch Services has not registered the new app version, the app is not running, or the command result file could not be written.

## Accessibility permission is false

DisplayRecall requires macOS System Settings > Privacy & Security > Accessibility. Grant permission to the installed DisplayRecall app. Signing identity changes can cause macOS to require permission again.

The Skill must not reset TCC or attempt to bypass permission.

## External display is false

Save and restore require the supported topology: the Mac built-in display plus one external display. Connect the external display and wait for macOS to finish publishing the topology.

## No saved layout

Arrange the desired windows first, then ask the user whether to save. Saving replaces the active layout snapshot and rotates the previous file to DisplayRecall's local backup.

## Partial restore

Report `savedWindowCount`, `matchedWindowCount`, `restoredWindowCount`, and `failedWindowCount` separately. A partial result may mean:

- a saved app is closed
- a window is minimized or full-screen
- the window is on an inaccessible Space
- the app exposed its window late
- the app rejected the requested frame or enforced a minimum size

Do not call a partial result complete.
