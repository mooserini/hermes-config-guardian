# Hermes Guardian — vNext Candidate Brief

## Mission

Build a local candidate of the existing **Hermes Config Guardian** macOS menu-bar app. Its user-facing name is now **Hermes Guardian** because its authority boundary has grown beyond one `config.yaml` file.

This is a narrow extension, not a new product:

- preserve the existing config.yaml protection, review flow, maintenance window, privacy posture, receipts, and behavior;
- add visible monitoring for two existing Hermes skill-state surfaces;
- preserve the app's restrained, native, compact visual language;
- do not add dashboards, provider abstractions, remote services, schedulers, model calls, skill editing, skill approval actions, or automatic repairs.

The design rule is minimum sufficient mechanism: surface state honestly, reconcile it deterministically, and leave authority with the human.

## Isolated-candidate boundaries

This checkout is an isolated candidate copy. Work only here.

Do **not**:

- modify `/Users/thomaskenny/Developer/Github Candidate/hermes-config-guardian`;
- add, restore, or use a Git remote; commit, push, publish, release, or create a PR;
- access credentials, change Hermes configuration, modify any active skill, approve/reject pending skills, or restore any watched state;
- install the finished app into Applications or alter login-item settings.

Reading the live Hermes skill directories is in scope solely so the app can monitor them when it runs.

## Rename

Rename user-facing app strings from **Hermes Config Guardian** to **Hermes Guardian** wherever that is appropriate for this candidate: visible labels, menu-bar/help text, README, package/app display naming, build artifact naming, and test expectations.

Do not casually invalidate existing local Guardian state. Keep the current Application Support state location readable/compatible for this candidate unless a small, verified migration is necessary. If you introduce a new state location, migration must be explicit, one-way-safe, and covered by tests. Prefer compatibility over a cosmetic filesystem rename.

## Existing state model — retain it

The existing app protects an enrolled Hermes config file. It keeps an approved exact-byte snapshot outside Hermes, compares hashes, presents changes for human review, and may restore only that approved configuration after a human chooses Reject.

Do not weaken or generalize that config approval behavior as part of this task.

The new skill monitors are **read-only indicators**. They are not pre-write firewalls. They observe completed filesystem state and must never mutate either directory.

## Add exactly two skill-state indicators

The app already has an existing small native UI. Add two adjacent, visually coherent indicator rows/sections to the clean/normal monitored-state presentation. Keep each row compact, tappable/clickable only if a useful existing details window pattern already supports it, and accessible with concise VoiceOver labels/values.

### 1. Pending Skills indicator

Monitor this directory:

```text
~/.hermes/pending/skills/
```

This is Hermes' file-backed queue for staged skill-write proposals. It contains pending record JSON files.

Required behavior:

- Directory absent or empty: show a quiet clean state such as `Pending skills — none`.
- One or more pending records: show an attention state with the exact pending-record count, e.g. `Pending skills — 2 awaiting review`.
- Changes should be detected from directory events plus existing-style periodic reconciliation; do not depend on events alone.
- Do not parse, display, send, approve, reject, delete, or replay pending payloads. The indicator is a human-facing visibility signal only.
- The indicator may contribute to the Guardian's overall attention state, but it must be clearly distinguishable from an unapproved config.yaml rewrite.
- Avoid repeated alert noise: a durable unchanged nonzero count should not repeatedly ring/raise a window at every reconciliation.

### 2. Active Skills Integrity indicator

Monitor this directory recursively:

```text
~/.hermes/skills/
```

Required behavior:

- Build a deterministic manifest of regular files beneath the directory: normalized relative path → SHA-256 of file bytes.
- Treat added, removed, renamed/replaced, and byte-modified files as integrity drift. A mere timestamp change with identical bytes is clean.
- The first baseline must be explicitly human-recorded. Do not silently declare whatever happens to be present on first launch as trusted.
- Before a baseline exists, render an ordinary neutral status such as `Skills integrity — baseline not recorded`, with one clearly labeled action to record the current manifest. This action stores only local Guardian state and must explain that it does not approve pending skill writes or change skills.
- Once baselined, show a compact clean status when the manifest matches.
- On drift, show an attention state with a truthful summary count. Preserve enough local metadata for the user to inspect which relative paths were added, changed, or removed. Do not store source file bodies in Guardian state and do not expose their contents in the compact menu-bar view.
- Provide a deliberate human action to replace the baseline with the current manifest only after the user has seen the drift. It must be plainly worded as recording the current skill state, not “auto-approve.” No automatic baseline advancement, restoration, deletion, or modification of any skill file.
- Detect changes from directory events plus periodic checksum reconciliation. Hashing must occur off the main UI path so the app stays responsive.
- Handle an unreadable/missing skills directory as an explicit error/unavailable state, never as a clean empty manifest. Fail soft and explain the local condition.

## Overall behavior

- Keep the config.yaml sentinel semantics exactly as they are.
- The three concerns must remain visually and semantically distinct:
  1. configuration approval state;
  2. pending skill-write queue visibility;
  3. active skills manifest integrity.
- A pending skill queue and a skills-manifest drift may both be present simultaneously. The UI must make that legible rather than collapsing them into one vague warning.
- Do not invent a global auto-approval policy. The human remains the authority.
- Use the existing `DirectoryWatcher` / reconciliation approach where it fits, instead of introducing a new dependency or watch framework.
- Keep runtime data private and owner-only according to the app's existing conventions.

## Tests and verification

Add focused deterministic tests for the new core behavior, including at minimum:

1. pending skills empty vs nonempty record count;
2. skills manifest is deterministic and hashes regular files by relative path;
3. a timestamp-only change with identical bytes does not produce drift;
4. added, changed, and removed files each produce correct drift classification;
5. no baseline is treated as unapproved/neutral rather than clean;
6. a recorded baseline is stable across reload;
7. unreadable or missing skills directory is not reported clean;
8. new functionality performs no writes to `~/.hermes/pending/skills/` or `~/.hermes/skills/`.

Run the repository's canonical test suite:

```sh
swift test
```

Then build the candidate app through the repository build script:

```sh
./scripts/build-app.sh
```

Do not install it.

## Completion

When the job is done:

1. leave all work and test/build receipts inside this isolated checkout;
2. make sure the candidate app bundle exists and is locally runnable;
3. open the final candidate app on the desktop in the frontmost window;
4. return a concise summary listing changed files, tests/build result, candidate app path, and any limitations or follow-ups.
