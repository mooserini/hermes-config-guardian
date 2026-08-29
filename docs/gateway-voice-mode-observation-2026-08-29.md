# Gateway voice-mode observation — 2026-08-29

## Verdict

`/voice tts` is not a global `config.yaml` setting change. It is a durable,
per-chat gateway override stored separately in `gateway_voice_mode.json` under
the Hermes home directory.

This was discovered while using Guardian's normal `config.yaml` observation
method. The absence of a `config.yaml` write was correct evidence, not a missed
file event.

## Direct observations

### Global configuration pass

A read-only observer watched the active Hermes `config.yaml` while `/voice tts`
and `/voice off` were issued from Discord, with unrelated commands mixed in.

- No `config.yaml` byte change was observed.
- `voice.auto_tts` remained `false` on physical line 191.
- The `config.yaml` fingerprint stayed unchanged for the entire pass.

### Per-chat voice-mode pass

A second read-only observer watched `gateway_voice_mode.json`. It recorded
13 writes over 87 seconds.

The file alternated between exactly two byte-for-byte fingerprints:

| State summary | Meaning |
| --- | --- |
| 1 `off`, 1 `voice_only` | One remembered chat opted out; another opted in. |
| 2 `voice_only` | The tested chat opted in through `/voice tts`. |

Every rapid toggle returned to one of those same two known byte sequences. No
third remembered chat appeared, no malformed JSON was observed, and no
serialization/order drift was detected. The test ended with both remembered
chats in `voice_only` mode.

Discord chat identifiers were deliberately not recorded in this document.

## Source confirmation

The installed Hermes gateway source independently confirms the observed shape:

- `gateway_voice_mode.json` is the gateway's voice-mode persistence file.
- `/voice on` and `/voice tts` set a per-chat auto-TTS opt-in even when global
  `voice.auto_tts` is false.
- `/voice off` records a per-chat opt-out.
- The gateway restores those persisted mode records into the live platform
  adapter when it starts.

This explains why a Discord slash command can produce durable behavior without
rewriting the global YAML configuration.

## Guardian implication — deliberately not implemented

`gateway_voice_mode.json` is a credible future optional monitored file. It is
also a different class of state from global configuration: it changes more
often, is scoped to individual chats, and contains identifiers that Guardian
must not casually expose.

Any future enrollment should therefore preserve the current contract:

- explicit human enrollment;
- identifier-redacted summaries;
- exact-byte evidence and rollback semantics considered separately from
  notification behavior;
- no assumption that a routine chat-level toggle deserves the same interruption
  level as a global configuration rewrite.

This note records an observed seam and its evidence. It does not add support
for monitoring the file.
