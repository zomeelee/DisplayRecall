# Changelog

All notable changes to DisplayRecall are documented here.

## [Unreleased]

- Added local command URLs for save, restore, and status operations.
- Added machine-readable command results for Codex Skill integration.

## [0.1.7] - 2026-09-23

- Prepared the project for public development and unsigned continuous integration.
- Made the layout data directory follow the app's bundle identifier.
- Kept application-constrained windows clear of left, right, and bottom Docks.
- Added containment verification for restored window frames.

## [0.1.6] - 2026-09-21

- Continued automatic retries when only part of a saved layout was initially available.
- Added Accessibility scan diagnostics.

## [0.1.5] - 2026-09-20

- Preserved the order of similar windows by using public runtime window IDs when available.

## [0.1.4] - 2026-09-20

- Reapplied requested frames after application zoom transitions.

## [0.1.3] - 2026-09-18

- Added automatic restoration when a different external display replaces the saved display.

## [0.1.0] - 2026-09-18

- Added the first macOS menu bar implementation.
