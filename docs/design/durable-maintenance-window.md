# Durable maintenance window

## Purpose

Hermes updates and setup flows may rewrite `config.yaml` more than once. A
Guardian attention signal for every intermediate serialization is noisy and can
tempt a person to decide while the writer still holds an in-memory copy.

A maintenance window groups those writes into one deliberate human transaction
without granting the updater approval authority.

## Human surface

The initial Hermes-specific labels are:

- **Begin Hermes update**
- **End update and review**

The underlying contract is generic enough to become **Begin maintenance** for
other guarded files later.

## Preconditions

Guardian may begin a maintenance window only when:

- the watched file exactly matches the approved fingerprint;
- the approved snapshot can be read and independently rehashed;
- the YAML parses successfully;
- no proposal or earlier maintenance window is pending.

Failure of any precondition leaves Guardian in its prior state.

## Durable state

Beginning maintenance writes an owner-only manifest and checkpoint into
Guardian's private state directory:

```text
maintenance/current.json
maintenance/checkpoints/pre-update-<timestamp>-<hash>.yaml
maintenance/observed-proposals.jsonl
```

The manifest records format version, watched path, start time, approved hash,
checkpoint filename, and maintenance reason. It never contains credentials or
configuration values. The checkpoint contains the exact approved bytes and is
mode `0600`.

This state must survive Guardian crashes, application upgrades, logout, and Mac
restart. Memory-only maintenance state is not authoritative.

## Behavior while active

Guardian continues watching and hashing every distinct proposal. It appends
timestamp and fingerprint metadata to the maintenance observation log, but it
does not accept any proposal and does not replace the approved snapshot.

Repeated sound and window interruptions are suppressed. The menu-bar state and
review window remain visibly marked **Maintenance active** with the start time.
Invalid YAML, unreadable files, or a missing target remain visible immediately;
maintenance is not permission to hide damage.

## Ending maintenance

**End update and review** waits for the target to remain stable through the
normal debounce interval, then compares the final bytes with the pre-update
checkpoint.

Guardian presents:

- exact fingerprint transition;
- YAML validity;
- semantic setting changes;
- type transitions;
- byte-only rewrites;
- the number of distinct intermediate proposals observed;
- documentation-grounded clarification where evidence exists.

The human may then:

- **Accept final version** — make the final stable bytes the new approved
  snapshot;
- **Reject and restore checkpoint** — restore the exact pre-update bytes;
- **Keep reviewing** — leave maintenance active and make no file change.

No timeout or successful updater exit automatically accepts the final file.

## Compatibility warning

After a Hermes update, the prior configuration may use a retired schema while
the new file may contain a required migration. Guardian must therefore warn
before exact restoration:

> Restoring preserves your pre-update intent and bytes, but the updated Hermes
> version may no longer accept this schema. Guardian has not proven runtime
> compatibility.

Future versions may offer a read-only Hermes validation command, but a passing
validator still does not become approval.

## Recovery and forgotten windows

On launch, a durable maintenance manifest restores the active state. Guardian
does not silently discard it. A visibly active window can be ended normally or
abandoned only through a human-confirmed action that first performs the same
final comparison.

The interface should display elapsed maintenance time. A long-running window is
a reminder, not an automatic failure and never an automatic approval.

## Required tests

- refuse maintenance from a pending or invalid baseline;
- survive process restart with the same checkpoint and manifest;
- record several rapid atomic replacements without repeated interruption;
- compare only after the final file is stable;
- preserve invalid final bytes for review while keeping the checkpoint intact;
- accept the final version only after an explicit human action;
- restore the exact checkpoint and record a rejection receipt;
- expose a schema-compatibility warning before restoration;
- recover cleanly when the update makes no byte change;
- recover cleanly when only YAML mapping order changes.
