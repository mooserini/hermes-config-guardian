# Hermes Config Guardian

Hermes Config Guardian is an independent macOS menu-bar sentry for human-approved changes to a Hermes Agent `config.yaml` file.

It preserves an exact approved snapshot outside Hermes, detects raw and semantic changes, explains the relevant settings with official Hermes documentation, and waits for a human to accept, review, clarify, or reject the change. Reject restores the last approved bytes immediately.

The design is deliberately small: protect one consequential file well before expanding the boundary.

> [!IMPORTANT]
> This is an experimental, independent project. It is not affiliated with or endorsed by Nous Research or the Hermes Agent project.

## Current boundary

- Watches one explicitly configured YAML file.
- Never modifies Hermes source code.
- Requires explicit enrollment; the first file observed is not silently trusted.
- Stores exact approved snapshots and append-only approval or rejection receipts outside Hermes.
- Verifies snapshots with SHA-256 before restoration.
- Detects semantic YAML changes while redacting likely credential values in reviews.
- Offers `Accept`, `Review`, `Clarify`, and one-click `Reject` decisions.
- Binds clarification to the proposed file hash so a late explanation cannot attach to a newer edit.
- Uses directory events plus periodic checksum reconciliation; routine checks invoke no model.

Guardian currently detects completed writes. It is not a privileged pre-write firewall and cannot prevent another process from briefly writing the watched file before detection.

## Documentation-grounded clarification

Clarify searches the Hermes documentation installed with the local Hermes build first, then checks the official hosted `llms-full.txt` corpus.

- Only bounded passages matching changed setting paths are given to Apple's on-device Foundation Model.
- The exact evidence and official source link remain visible beneath the explanation.
- Guardian reports whether installed and hosted passages agree.
- If no exact passage is found, Guardian does not ask the model to infer the setting's behavior.
- The hosted corpus is capped at 10 MB, cached for six hours with owner-only permissions, and refreshed using `ETag` and `Last-Modified` validators.
- Configuration contents are never sent to the documentation server. The only network request retrieves public documentation.

Foundation Models are optional. On unsupported systems, Guardian falls back to deterministic behavior.

## Build and test

Requirements:

- macOS 14 or newer
- Swift 6 toolchain

Run the tests:

```sh
swift test
```

Build the locally signed menu-bar application:

```sh
./scripts/build-app.sh
```

The bundle is created at `build/Hermes Config Guardian.app`.

## Disposable-file trial

Test with a disposable YAML file and isolated state directory before pointing Guardian at a real configuration:

```sh
HCG_TARGET_CONFIG=/absolute/path/to/test-config.yaml \
HCG_STATE_DIR=/absolute/path/to/test-state \
swift run HermesConfigGuardian
```

Click the shield in the menu bar, enroll the disposable configuration, edit the YAML, and reopen the shield. Guardian should show the changed paths and four decision buttons.

`HCG_RECONCILE_INTERVAL` may be set to a shorter number of seconds for testing. The default is 30 seconds.

## Verified prototype behavior

The current test suite covers:

- snapshot verification and exact-byte restoration;
- append-only approval and rejection receipts;
- sensitive-value redaction;
- invalid YAML rejection;
- atomic file replacement detection;
- clean scalar presentation;
- exact documentation extraction and canonical source preservation.

An end-to-end disposable trial also verified that a clarification and its evidence survive repeated checksum reconciliation.

## Roadmap

The immediate goal is to make the one-file contract boringly reliable. A later version may generalize the same human-approval boundary to other silently rewritten Hermes state, including skill and pending-skill directories, without moving authority back inside the harness being watched.

## Runtime privacy

Guardian's state directory contains approved configuration bytes, watched-file paths, hashes, and receipts. Treat that directory as private runtime data. Do not commit or publish it.

## License

MIT
