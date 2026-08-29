# Security

## Reporting a vulnerability

Please use this repository's private GitHub Security Advisory reporting flow rather than opening a public issue containing exploit details, credentials, or configuration contents.

## Sensitive runtime material

Hermes Config Guardian intentionally stores approved configuration bytes and integrity metadata in its state directory. That directory may contain sensitive values and local file paths even though the review interface redacts likely credentials.

- Keep runtime state out of source control and support bundles.
- Test changes against a disposable configuration and isolated state directory.
- Never publish snapshots, receipts, documentation caches, or a live Hermes configuration.
- Review the current sentry boundary: Guardian detects completed writes; it does not prevent the original write from occurring.
