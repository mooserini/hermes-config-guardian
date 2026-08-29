# First live validation — 2026-08-29

## Verdict

Hermes Config Guardian completed its first trial against a real, actively used
`config.yaml`. It detected both a meaningful wizard change and a byte-only
rewrite, preserved the independently approved snapshot, and restored the exact
approved bytes after human rejection.

This report deliberately separates direct evidence from inference. Guardian is
a detection, explanation, approval, and exact-restoration boundary. It does not
currently prevent Hermes from reading unapproved bytes during the interval
between a write and the human decision.

## Boundary

- Watched target: the user's live Hermes `config.yaml`.
- Approved snapshot: private Guardian state, mode `0600`.
- Emergency backup: separate owner-only copy, not used during either recovery.
- Human decisions: performed through the production menu-bar application.
- Published evidence: hashes, timestamps, changed paths, and behavioral results
  only. Local usernames, absolute paths, configuration contents, and screenshot
  pixels are not committed here.

## Approved baseline

The recorded approval manifest, Guardian snapshot, and live file began and
ended the campaign with the same SHA-256 fingerprint:

```text
7a5cd028c1e9c6d5989f91de293b155072cd13cca702e8e4a88694a0d4a98f73
```

## Live trial 1: meaningful wizard change

The Hermes agent-settings wizard changed one setting:

```text
display.tool_progress: all -> verbose
```

Guardian sounded its attention signal and recorded the proposal fingerprint:

```text
755fbf375fe6042e148dbf9a2feea8ed677d00e05735cbf72336f67319cedbda
```

Clarification attempted the configured Nous-free stateless route and fell back
to Apple on-device inference. The timing matched Guardian's 45-second Hermes
timeout, but the application discarded the underlying error at this revision;
therefore timeout is a strong inference, not a persisted diagnostic fact.

The human rejected the proposal. Guardian wrote a rejection receipt containing
the rejected and restored fingerprints plus the changed path, then restored the
approved bytes exactly.

## Live trial 2: byte-only wizard rewrite

The same wizard rejected an invalid tool-progress answer and accepted no new
setting value. It nevertheless rewrote the file. Guardian observed:

- proposed fingerprint:
  `b5cae7d73b3dcef22c73590d5547fb8a8584e0c8455e1d086364de9d1a17c76b`;
- identical file size: 20,903 bytes;
- identical line count: 986 lines;
- parsed YAML semantic equality;
- one unchanged mapping entry moved from line 222 to line 235;
- no added, removed, or modified setting paths.

The moved entry remained at the same semantic path:

```text
moa.presets.default.enabled
```

Guardian first rendered the event as zero setting changes. The wording was then
refined and exercised in a second live reproduction:

> The file's bytes changed, but Guardian found no configuration setting changes
> after parsing the YAML. There are no changed setting paths to review. Accept
> approves the rewritten byte layout; Reject restores the exact approved bytes.

No external or on-device model was invoked for this explanation. The human
rejected both byte-only proposals. Each rejection receipt recorded an empty
`changedPaths` list and the exact restored baseline fingerprint.

## Attention controls

The live app verified both persisted interruption controls:

- play attention sound;
- open the review window automatically.

The first defaults to on and the second to off. With both enabled, a subsequent
wizard rewrite sounded the alert and opened the review window.

## Human-visible receipt fingerprints

The original screenshots remain with the human operator because they contain a
local username and filesystem path. Their hashes preserve the identity of those
unmodified source artifacts without publishing the pixels.

| Visible result | SHA-256 |
| --- | --- |
| Clean approved state and Attention menu | `90d6b9c4b195d8097a1b4352a693abdf3a7615edb9a3afe978b787f8f90c3a3c` |
| Original zero-setting deterministic explanation | `ddcdebacd0c3847d28b4ed676b6b14726d095568c3dfcc571c0ec2dfb8aae488` |
| Refined byte-only explanation | `378a68f81220fa067f0281554efcfdbc3f46e5a4f83c62494d36af8cecfe1b1f` |
| macOS Open at Login registration | `c72b85322a53670cb169ef0db989daa0bca2147f241adbaeb82cb0242df17606` |

## Launch at Login registration

The installed application opted into macOS Launch at Login from its stable
location under the human operator's Applications directory. macOS presented a
normal login-item notification and opened the relevant System Settings page,
where Hermes Config Guardian was visibly listed and could be disabled by the
human.

The operating system's background-task record independently reported the item
as `enabled`, `allowed`, and `notified`, with bundle identifier:

```text
org.hermesconfigguardian.app
```

The running process was also verified to originate from that installed
application bundle rather than a temporary build product.

## Cold-start validation

The human operator then closed other applications, left Guardian running, and
restarted macOS normally. Guardian was not launched manually after login.

Machine timestamps recorded:

```text
macOS boot:       2026-08-29 03:23:34 EDT
Guardian launch: 2026-08-29 03:23:54 EDT
```

Guardian therefore relaunched from its installed application bundle 20 seconds
after boot through the registered login item. The human observed its menu-bar
icon before another ordinary menu-bar application had completed startup. After
launch, the live Hermes configuration and the durable approved snapshot still
shared the exact baseline SHA-256 fingerprint.

## Machine receipts

Guardian's private append-only receipt directory contained:

- one approval receipt at `2026-08-29T06:25:07Z`;
- a meaningful-change rejection at `2026-08-29T06:31:59Z`;
- byte-only rejections at `2026-08-29T06:58:05Z` and
  `2026-08-29T07:04:49Z`.

The receipts remain private because they include the watched source path. Their
safe fields were independently checked after each decision.

## What this proves

- Guardian detects a real Hermes wizard write.
- It distinguishes byte identity from parsed YAML meaning.
- It does not invent changed settings or documentation evidence.
- It can degrade from external inference to an on-device explanation without
  changing approval state.
- Reject restores the exact approved bytes and records the decision.
- Human-selectable interruption behavior works in the production app.
- Launch at Login is registered, enabled, human-visible, and reversible through
  macOS System Settings.
- Guardian survives a real restart, relaunches without human intervention, and
  recovers its durable approved state.

## What this does not prove

- Guardian does not yet block unapproved bytes from being read before review.
- One successful restart does not yet establish behavior across macOS upgrades,
  damaged login-item state, or repeated long-term restarts.
- The Nous failure reason was not persisted at the tested revision.
- One guarded file does not establish safe semantics for directories or
  multi-file transactions.
