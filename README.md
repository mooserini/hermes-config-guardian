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
- Keeps quick decisions in the menu-bar panel and opens the same live state in a resizable window for longer reviews; explanation and evidence overflow stays inside one scrollable details area.
- Binds clarification to the proposed file hash so a late explanation cannot attach to a newer edit.
- Uses directory events plus periodic checksum reconciliation; routine checks invoke no model.

Guardian currently detects completed writes. It is not a privileged pre-write firewall and cannot prevent another process from briefly writing the watched file before detection.

## Documentation-grounded clarification

Clarify searches the Hermes documentation installed with the local Hermes build first, then checks the official hosted `llms-full.txt` corpus.

- Only bounded passages matching changed setting paths are given to Hermes' stateless model-call helper.
- Nous' current free model recommendation for short auxiliary summaries is resolved at call time and used without loading tools, memory, rules, skills, a conversation, or a session.
- The exact evidence and official source link remain visible beneath the explanation.
- Guardian reports whether installed and hosted passages agree.
- If no exact passage is found, Guardian does not ask the model to infer the setting's behavior.
- The hosted corpus is capped at 10 MB, cached for six hours with owner-only permissions, and refreshed using `ETag` and `Last-Modified` validators.
- Configuration contents are never sent to the documentation server; that request retrieves only public documentation.
- When the user presses Clarify, the selected inference provider receives bounded documentation excerpts and the redacted semantic changes, not the complete configuration file. Provider retention and training terms may still apply to that payload.

Hermes stateless inference through Nous' current free auxiliary recommendation is the primary explanation rail. Apple's on-device Foundation Model is an optional fallback, followed by deterministic behavior when neither model is available.

Guardian requests the lowest reasoning level supported by the current Nous route and displays that request beside the actual provider/model. If the live catalog reports no reasoning control, Guardian says so rather than pretending it disabled thinking. This keeps the small documentation-translation task bounded without editing Hermes' own configuration or source.

For controlled comparisons, `HCG_HERMES_CLARIFY_PROVIDER` and `HCG_HERMES_CLARIFY_MODEL` may be set together to pin a single stateless clarification route without changing the watched Hermes configuration. Normal use leaves both unset and follows Nous' live free compaction/summarization recommendation.

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
- numeric token-budget visibility alongside credential redaction;
- explicit low-reasoning requests for supported Nous clarification routes;
- invalid YAML rejection;
- atomic file replacement detection;
- clean scalar presentation;
- exact documentation extraction and canonical source preservation.

An end-to-end disposable trial also verified that a clarification and its evidence survive repeated checksum reconciliation.

## A note from the lab

The first resizable-window stress test produced an unexpectedly memorable piece of synthetic rhetoric: Grok filled the overflow specimen by repeating, “The human remains the authority.” The screenshot and the distinction between experienced emotion and behavior that resembles it are preserved in [The human remains the authority](docs/lab-notes/the-human-remains-the-authority.md).

## Roadmap

The immediate goal is to make the one-file contract boringly reliable. A later version may generalize the same human-approval boundary to other silently rewritten Hermes state, including skill and pending-skill directories, without moving authority back inside the harness being watched.

## Runtime privacy

Guardian's state directory contains approved configuration bytes, watched-file paths, hashes, and receipts. Treat that directory as private runtime data. Do not commit or publish it.

## License

MIT
