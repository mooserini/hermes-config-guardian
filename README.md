# Hermes Guardian

Hermes Guardian is an independent macOS menu-bar sentry for human-approved changes to a Hermes Agent `config.yaml` file, plus read-only visibility into Hermes pending-skill and active-skill filesystem state.

It preserves an exact approved snapshot outside Hermes, detects raw and semantic changes, explains the relevant settings with official Hermes documentation, and waits for a human to accept, review, clarify, or reject the change. Reject restores the last approved bytes immediately.

The design is deliberately small: surface state honestly, reconcile it deterministically, and leave authority with the human.

> [!IMPORTANT]
> This is an experimental, independent project. It is not affiliated with or endorsed by Nous Research or the Hermes Agent project.

## Current boundary

- Watches one explicitly configured YAML file.
- Shows two additional read-only skill-state indicators: the pending-skill queue count and active-skills manifest integrity.
- Never modifies Hermes source code, pending skill records, or active skill files.
- Requires explicit enrollment; the first file observed is not silently trusted.
- Requires an explicit human action before an active-skills integrity baseline is recorded.
- Stores exact approved snapshots and append-only approval or rejection receipts outside Hermes.
- Verifies snapshots with SHA-256 before restoration.
- Detects semantic YAML changes while redacting likely credential values in reviews.
- Redacts credential-shaped values even when they appear beneath unfamiliar or misleading setting names.
- Offers `Accept`, `Review`, `Clarify`, and one-click `Reject` decisions.
- Plays the built-in macOS `Glass` alert once for each newly detected proposal while changing the menu-bar shield to its attention state; repeated checksum reconciliation stays silent.
- Invalid YAML exposes only `Clarify` and `Reject`; Guardian shows the isolated unparsed line locally and never permits acceptance.
- Scalar type changes are called out in Review and receive a deterministic type-safety explanation; Guardian does not ask a model to equate strings, numbers, booleans, or nulls.
- Keeps quick decisions in the menu-bar panel and opens the same live state in a resizable window for longer reviews; explanation and evidence overflow stays inside one scrollable details area.
- Binds clarification to the proposed file hash so a late explanation cannot attach to a newer edit.
- Uses directory events plus periodic checksum reconciliation; routine checks invoke no model.
- Brackets intentional Hermes updates with a durable maintenance window: Guardian seals the approved bytes, records distinct intermediate rewrites without bell spam, survives relaunch, and still requires a final human Accept or Reject decision.

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
- For invalid YAML, Clarify skips documentation and sends only the offending line, capped at 240 characters after local credential, path, email, and high-entropy-token redaction. The fragment is treated as quoted data, never an instruction; nothing is sent until the human presses Clarify.

Hermes stateless inference through Nous' current free auxiliary recommendation is the primary explanation rail. Apple's on-device Foundation Model is an optional fallback, followed by deterministic behavior when neither model is available.

Guardian requests the lowest reasoning level supported by the current Nous route and displays that request beside the actual provider/model. If the live catalog reports no reasoning control, Guardian says so rather than pretending it disabled thinking. This keeps the small documentation-translation task bounded without editing Hermes' own configuration or source.

For controlled comparisons, `HCG_HERMES_CLARIFY_PROVIDER` and `HCG_HERMES_CLARIFY_MODEL` may be set together to pin a single stateless clarification route without changing the watched Hermes configuration. Normal use leaves both unset and follows Nous' live free compaction/summarization recommendation.

## Build and test

Build requirements:

- macOS 14 or newer
- Apple development tools (Xcode or Command Line Tools) providing a macOS SDK and a Swift 6 toolchain

Start from a checkout and confirm the selected toolchain:

```sh
git clone https://github.com/mooserini/hermes-config-guardian.git
cd hermes-config-guardian
swift --version
sw_vers
```

SwiftPM declares the sole external package dependency, [Yams](https://github.com/jpsim/Yams), in `Package.swift`. The committed `Package.resolved` currently pins Yams 6.2.2; retain that file when reproducing a build.

For a fresh checkout, resolve the package dependency from GitHub:

```sh
swift package resolve
```

Build and test commands also resolve dependencies as needed. The explicit resolution step above is suggested setup based on the package configuration; fresh-machine dependency resolution has not yet been validated.

Basic monitoring needs the selected YAML file and Guardian's state directory. Hermes, its Python runtime, and inference credentials are optional runtime requirements for **Hermes-backed Clarify**, rather than build prerequisites. That route needs a Hermes agent directory containing `agent/oneshot.py`, an executable Python runtime (normally its `.venv/bin/python`), and authentication for the inference provider. When that route is unavailable, Guardian can use the optional Apple on-device model where supported, then deterministic fallback explanations.

Run the tests:

```sh
swift test
```

Stop if any test fails before building or installing. The authenticated live-inference test is skipped by default. Set `HCG_LIVE_HERMES_TEST=1` only when deliberately testing a configured Hermes runtime and its provider authentication:

```sh
HCG_LIVE_HERMES_TEST=1 swift test
```

Build the locally signed menu-bar application:

```sh
./scripts/build-app.sh
```

The bundle is created at `build/Hermes Guardian.app`. The script uses an ad-hoc code signature for local use; it does not notarize the application.

After tests, build, and a disposable-file trial pass, install the release bundle in the current user's stable Applications directory:

> [!WARNING]
> The installer rebuilds release and installs to `~/Applications/Hermes Guardian.app` by default. `HCG_INSTALL_ROOT` changes the destination directory. If an app already exists there, it is moved to `Hermes Guardian.previous.app`; an older app at that backup path is deleted first. Preserve any backup you need before running the installer.

```sh
./scripts/install-app.sh
```

The installed app exposes an explicit **Launch at login** toggle in its
App Behavior menu. macOS may require the user to approve the login item in System
Settings. Guardian reports that state instead of treating registration as
successful.

## Intentional Hermes updates

When Guardian reports a clean approved configuration, select **Update
maintenance…** before running a Hermes updater or setup flow. Guardian asks
for confirmation, then creates a
verified owner-only checkpoint and visibly enters maintenance mode. It keeps
watching every distinct rewrite but suppresses repeated sound and window
interruptions.

After the updater is completely finished, select **End update and review**.
Guardian compares the final bytes with the sealed checkpoint. It never accepts
the result automatically:

- **Accept final version** approves only the final stable proposal.
- **Reject and restore checkpoint** writes back the exact pre-update bytes and
  warns that a newer Hermes build may require a migrated schema.
- **Keep updating** returns to maintenance without changing either file.

If Guardian, the login session, or the Mac restarts during maintenance, the
checkpoint, start time, and distinct-proposal count are recovered from private
durable state. When maintenance ends, its manifest and hash-only observation
log move into owner-only history; the corresponding approval or rejection
receipt remains the authority for the final decision.

## Disposable-file trial

After building the app, test with a disposable YAML file and isolated configuration, state, skills, documentation, and runtime paths before pointing Guardian at a real configuration. Overriding only the target file and state directory leaves the other paths at their normal Hermes defaults.

```sh
trial_dir=$(mktemp -d "${TMPDIR:-/tmp}/hermes-guardian-trial.XXXXXX")
mkdir -p "$trial_dir/state" "$trial_dir/pending-skills" \
  "$trial_dir/skills" "$trial_dir/docs"
printf 'dummy_key: baseline\n' > "$trial_dir/config.yaml"

open -n \
  --env HCG_TARGET_CONFIG="$trial_dir/config.yaml" \
  --env HCG_STATE_DIR="$trial_dir/state" \
  --env HCG_PENDING_SKILLS_DIR="$trial_dir/pending-skills" \
  --env HCG_SKILLS_DIR="$trial_dir/skills" \
  --env HCG_HERMES_DOCS_DIR="$trial_dir/docs" \
  --env HCG_HERMES_HOME="$trial_dir/hermes-home" \
  --env HCG_HERMES_AGENT_DIR="$trial_dir/disabled-agent" \
  --env HCG_HERMES_PYTHON="$trial_dir/disabled-python" \
  --env HCG_RECONCILE_INTERVAL=1 \
  --env HCG_AUTO_CLARIFY=0 \
  --env HCG_AUTO_EXPAND_DOCUMENTATION=0 \
  --env HCG_AUTO_EXPAND_REVIEW=0 \
  "build/Hermes Guardian.app"
```

Click the trial app's shield in the menu bar and confirm that its target is `$trial_dir/config.yaml` before enrolling it. In the same shell, change the dummy value:

```sh
printf 'dummy_key: changed\n' > "$trial_dir/config.yaml"
```

Reopen the trial shield. Guardian should show the changed path and four decision buttons. Quit the trial instance when finished. The trial files remain available for inspection; this example does not delete them. The empty documentation directory and nonexistent runtime paths keep Hermes-backed inference unavailable during this monitoring trial.

The path overrides select the defaults shown below. `HCG_HERMES_HOME` changes runtime discovery defaults; it does not redirect the target configuration, Guardian state, skills, or documentation paths.

| Variable | Default when unset |
| --- | --- |
| `HCG_TARGET_CONFIG` | `~/.hermes/config.yaml` |
| `HCG_STATE_DIR` | `~/Library/Application Support/Hermes Config Guardian` |
| `HCG_PENDING_SKILLS_DIR` | `~/.hermes/pending/skills` |
| `HCG_SKILLS_DIR` | `~/.hermes/skills` |
| `HCG_HERMES_DOCS_DIR` | `~/.hermes/hermes-agent/website/docs` |
| `HCG_HERMES_HOME` | `~/.hermes` (Hermes runtime discovery base) |
| `HCG_HERMES_AGENT_DIR` | `hermes-agent` under the selected Hermes home |
| `HCG_HERMES_PYTHON` | `.venv/bin/python` under the selected agent directory |

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
- durable maintenance recovery, distinct rapid rewrites, no-change and
  byte-only update results, invalid final YAML, and exact checkpoint rejection;
- pending-skill empty versus nonempty counts without parsing payloads;
- deterministic active-skills manifests, timestamp-only stability, added/changed/removed drift, missing-directory failure, and human-recorded baselines.

An end-to-end disposable trial also verified that a clarification and its evidence survive repeated checksum reconciliation.

## A note from the lab

The first resizable-window stress test produced an unexpectedly memorable piece of synthetic rhetoric: Grok filled the overflow specimen by repeating, “The human remains the authority.” The screenshot and the distinction between experienced emotion and behavior that resembles it are preserved in [The human remains the authority](docs/lab-notes/the-human-remains-the-authority.md).

The first live Hermes wizard run added a second artifact when speech-to-text confidently renamed a Nous timeout: [Wheat Mouse](docs/lab-notes/wheat-mouse.md) now stands for a fallback provider failing without gaining authority over the protected file.

The evidence and limits from the first trial against a real Hermes configuration are recorded in [First live validation — 2026-08-29](docs/first-live-validation-2026-08-29.md).

## Roadmap

This candidate adds read-only pending-skill and active-skills integrity indicators without granting Guardian authority to approve, reject, restore, or edit skills. Configuration approval remains a separate human decision.

The implemented [durable maintenance window](docs/design/durable-maintenance-window.md) groups the many writes made by an intentional Hermes update into one final human review without granting the updater automatic approval.

## Runtime privacy

Guardian's state directory contains approved configuration bytes, watched-file paths, hashes, and receipts. Treat that directory as private runtime data. Do not commit or publish it.

## License

MIT
