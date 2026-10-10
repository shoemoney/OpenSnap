# End-to-end audit: method, inventory and launcher

Owner authorization (2026-10-09 23:27 CDT): audit every option and every icon, ask whether each looks as good as it can and uses space well, act autonomously. The plan is `docs/design/e2e-audit-plan.md`; this folder is its infrastructure.

| File | What it is |
|---|---|
| `inventory.json` | Every window, menu, control, icon, preference, sheet, alert, shortcut and state, each with a stable audit ID. Generated. |
| `coverage-matrix.md` | One row per audit ID: where the evidence goes. Descriptive columns generated, evidence columns filled while auditing and preserved across regenerates. |
| `harness-seen.json` | What the screenshot harness rendered and exposed through AX (surfaces and controls). The harness half of the inventory. |
| `tools/e2e-session.sh` | The safe interactive launcher a driver clicks through. |
| `tools/e2e-inventory.py` | Regenerates the inventory and matrix from the sources and `harness-seen.json`. |
| `tools/test-e2e-session-guard.py` | Can-fail proofs for the launcher and the inventory (runs inside `tools/test.py`). |

## Method

A screenshot is not an interaction and an AX dump is not VoiceOver. Every row says which kind of evidence backs it, and the kinds are never merged:

| Evidence class | Meaning |
|---|---|
| `E2E` | A real interaction in an isolated session: a real click or key through the computer-use tools, the resulting state change observed, and a screenshot actually looked at. A suppressed or negative behaviour needs a positive control (the same step shown to work when it should). |
| `rendered` | A harness capture (`tools/eye-dump-audit.sh`): the app drew this state in-process. Proves how it looks, not that a user can reach it. |
| `unit/source` | An existing named test proves the behaviour. The row names the test, and `tools/test-e2e-session-guard.py` fails if that test text disappears. Pre-filled only where the test really covers the row's expectation. |
| `unverified` | Nothing yet. Every row starts here. |

Each row also carries an `exercise` verdict from the inventory: `e2e` (fully real-click exercisable), `e2e-partial` (the app-owned part is real-click, the named gap is the rest) or `gap` (not exercisable in an isolated session). Gap reasons: needs Screen Recording permission; Photos library; OS-owned panel content; multi-display or 1x hardware; VoiceOver speech; global hotkeys while the app is in the background; real printer; and `system-setting` (a system appearance or display option cannot be changed in an E2E session, so only harness-injected rendered evidence exists). Gaps are reported, never relabelled as passes.

Audit IDs are `E2E-<AREA>-<nnn>`. They are stable: a regenerate reuses the ID of every entry already in `inventory.json` (keyed by area, surface, name and type) and only appends new numbers. `HARN` entries are controls the harness saw that no source table accounts for; there should be none.

### Regenerating

```sh
sh tools/build.sh
sh tools/eye-dump-audit.sh /tmp/e2e-inv --groups main,more,overlays,states,pairs --appearances light --icons sf --no-wait-gui
python3 -I tools/e2e-inventory.py --harness /tmp/e2e-inv    # rewrites inventory.json, harness-seen.json, coverage-matrix.md
python3 -I tools/e2e-inventory.py --check                    # what the guard test runs: fails when the sources moved and the files did not
```

Menu items are parsed from `Sources/App.swift`; every menu selector must be classified in `SEM` inside the generator, so a new menu item fails generation until someone decides how it is audited. New `FAIcon` cases and `MenuSymbols` entries appear as icon entries automatically.

## The launcher

```sh
sh tools/e2e-session.sh start [--app PATH] [--seed empty|history|destinations|all] [--aws]
sh tools/e2e-session.sh status
sh tools/e2e-session.sh stop [SESSION_ID|APP_PID]
```

`start` copies the built app (default `build/OpenSnap.app`) into a temp dir, re-identifies the copy as `com.shoemoney.opensnap.e2e-<pid>`, ad-hoc re-signs it and launches only the copy under `env -i` with throwaway `HOME`, `CFFIXED_USER_HOME`, `TMPDIR` and `OPENSNAP_APP_SUPPORT`. Because `OPENSNAP_APP_SUPPORT` is set the migration is skipped and secrets stay in memory (no Keychain item is read or written). It prints the pid so a driver can use `mcp__kimi-cu__get_app_state pid=<pid>`.

- `--seed history` writes six synthetic History entries (real `.opensnap` documents with previews, three of them "Shared" with fake `*.example.test` links). `--seed destinations` writes four destinations on fake hosts with no secret. `--seed all` does both. `--seed empty` (default) writes nothing.
- `--aws` also exports `AWS_SHARED_CREDENTIALS_FILE=$HOME/.aws/credentials` to the child so the app's own S3 profile reader uses the owner's default profile in place, and seeds the S3 destination (bucket `cdn.shoemoney.com`, region `us-east-1`, prefix `pics`, profile `default`, public base `https://cdn.shoemoney.com/pics`) as the default. The launcher checks that the file exists and nothing more: it never reads, copies, prints or logs a credential. The upload itself is a separate, controlled step.
- `stop` sends SIGTERM (never AppleScript), SIGKILL after `E2E_STOP_TIMEOUT` seconds (default 10), drops the throwaway defaults domain, removes the temp dir, and only then compares the real stores. It exits non-zero if any watched real store changed or a throwaway plist was left behind.
- There is deliberately no sandbox fence: it would block the normal UI. The isolation environment and the real-store guard are the protection.
- Injectable for tests: `E2E_DEFAULTS` (the `defaults` binary), `E2E_STATE_DIR` (session registry, default `$TMPDIR/opensnap-e2e-sessions`), `E2E_STOP_TIMEOUT`, `E2E_LAUNCH_WAIT`.

### Safety model

1. The throwaway id is `com.shoemoney.opensnap.e2e-<digits>` and nothing else; it is validated before any trap or cleanup exists, and re-validated every time something destructive is about to use it (including an id read back from a session file on disk). Both real ids (current and retired) cannot match.
2. Cleanup helpers each re-check their own target: the defaults drop re-validates the id and removes only `<valid id>.plist`; the temp dir is removed only if it is `<tmp>/e2e-session.<6 chars>` and carries a marker naming its own id; a pid is signalled only if its command line is that session's own app copy.
3. All cleanup runs before the final real-store compare, so damage cleanup could do to a real store is visible to the compare, never hidden after it. The guard test proves this with an evil `defaults` stand-in that damages a real store during cleanup.
4. The real stores (`tools/real_store_guard.py`: the previous app's support folder, the new app's folder, both defaults plists) are hashed at start and compared at stop. Contents are never printed.
5. Never run a mutated copy of the launcher against the real HOME or the real `/usr/bin/defaults`. The guard test runs every script copy with a scratch HOME and TMPDIR and a fake `defaults` recorder, and checks that it did (see `can-fail-proofs-destructive-cleanup` in the project memory: a mutated harness once ran its EXIT cleanup for real and deleted the real defaults domain).

## Known limits

- Light appearance, Reduce Transparency, Increase Contrast, Differentiate Without Color and Reduce Motion cannot be changed in an E2E session (no global accessibility or appearance changes). The harness injects them inside its throwaway copy; that is `rendered` evidence only.
- `tools/real_store_guard.py` does not list the `e2e-` prefix among its throwaway-plist prefixes, so its "left behind" check does not cover this launcher; `stop` makes the same check itself for its own id.
- The History glass/text polish request in `QUEUE.md` is deferred: audit History fully, but do not activate that feature.
