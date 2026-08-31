# Security

## Reporting a vulnerability

Please use this repository's private GitHub Security Advisory reporting flow rather than opening a public issue containing exploit details, credentials, or configuration contents.

## Sensitive runtime material

Hermes Guardian intentionally stores approved configuration bytes and integrity metadata in its state directory. That directory may contain sensitive values and local file paths even though the review interface redacts likely credentials.

- Keep runtime state out of source control and support bundles.
- Test changes against a disposable configuration and isolated state directory.
- Never publish snapshots, receipts, documentation caches, or a live Hermes configuration.
- Review the current sentry boundary: Guardian detects completed writes; it does not prevent the original write from occurring.

## Clarification inference boundary

Clarify retrieves public Hermes documentation separately from model inference. The documentation server receives no configuration contents. The selected inference provider receives bounded documentation excerpts plus redacted semantic changes, never the complete configuration file. Redaction reduces exposure but cannot guarantee that every structurally sensitive value or path is removed; provider retention and training terms may apply. Do not press Clarify for a proposed change whose redacted review still contains information you are unwilling to transmit.
