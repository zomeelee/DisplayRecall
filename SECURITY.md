# Security Policy

## Supported versions

Security fixes are provided for the latest released version. DisplayRecall currently targets macOS 14 and later.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could expose private window metadata, misuse Accessibility permission, or compromise release signing.

Use GitHub's private vulnerability reporting for this repository. Include:

- the affected version or commit;
- macOS version and hardware architecture;
- reproduction steps;
- the expected impact;
- a minimal proof of concept with private window titles and user data removed.

If private vulnerability reporting is temporarily unavailable, open a public issue containing no exploit details and ask the maintainer to establish a private channel.

## Official releases

Only binaries attached to this repository's GitHub Releases page and signed by the DisplayRecall maintainer should be treated as official. Source code visibility does not make third-party binaries trustworthy.

Release credentials, Developer ID certificates, notarization credentials, and private keys must never be committed to the repository.
