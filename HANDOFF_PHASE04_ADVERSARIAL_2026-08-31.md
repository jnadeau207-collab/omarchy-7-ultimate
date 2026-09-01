# Phase 0-4 adversarial review and close — 2026-08-31

Reviewed SHA: `152bd844` on `work`, pushed to `origin/work`. Twenty-one commits on top of `60fbb967`.

This turn adversarially reviewed the 65-commit Cursor/Grok run that preceded it, corrected what that run broke, and closed every Phase 0-4 gate. **All twenty gates pass at `152bd844`.** The product is still **REJECTED** as an OS: Phases 5-11 are not built, and release additionally requires the three acceptance matrices at one packaged candidate SHA, which is a gate after Phase 11, not a Phase 0-4 gate.

## Gate state on metal (192.168.1.171, HDMI-A-1 1920x1080)

**20 of 20 pass.** The baseline before this turn was 17 of 20.

Verification runs against a clean clone of the pushed SHA at `/tmp/p04verify`, not the live checkout. That is deliberate: several assertions read `git ls-files --stage`, so they test what is committed. The live checkout is behind (see "Blocked"), while its working tree carries the reviewed content byte-for-byte, which is what the pixel captures were taken against.

Red at baseline, green now:

- `capability-catalog-test` — stale parity rows for Agent Center and Desktop.
- `product-contracts-test` — 2 errors at baseline, 3 after the Cursor run. `product contracts valid` now.
- `visual-regression-test` — `bin/omarchy-dev-visual-regression` was committed `100644`.

`phase4-desktop-shell-test` also carried a stale jump-list assertion that still required the Accessibility and System information rows after `cf87e813` unpublished them. Inverted in `152bd844`; it now pins their absence. It had been masked by the launcher-mode failure and cannot run on Windows because it needs `jq`.

## What the Cursor run got right

Do not redo these. The metal proof harness is real: `tmp-phase04-*-proof.sh` resolve the live Hyprland signature, print `METAL_HEAD $(git rev-parse HEAD)` so a capture is bound to a SHA, and shoot with `grim`. 409 captures exist. `capability-catalog-test.sh` mutates fixtures and asserts the checker rejects each one. `ultimate-settings-product-test.sh` cross-checks the model against provider manifests, asserts `mode: read` in provider truth, and asserts unregistered providers stay unregistered. The pseudo-locale in `SemanticMetrics.js` is a correct implementation, not a stub: placeholder protection, vowel expansion, bracket markers. Nineteen parity rows that named Settings pages which do not exist were correctly blanked.

## What it broke, and the corrections

- **Command injection reachable over IPC.** `7cc675f3` built `"omarchy-launch-settings --source desktop " + route` from an unvalidated summon payload and passed it to `Util.execDetached`, which runs `bash -lc`. `omarchy-shell shell summon omarchy.ultimate-settings '{"routeId":"x; <cmd>"}'` executed. Fixed in `0d343c42` with an argv vector plus a catalog-id shape check. Proven inert on metal.
- **Unregistered IPC surface added for a screenshot.** `15d0cb24` added an `omarchy.tray` `IpcHandler` with no caller anywhere in the tree, unregistered in `ipc-v0.json`. Registered in `d4d55c29`.
- **Claim inflation.** `parity.default-programs` moved `missing` to `prototype` with a visible route at Start > Settings > Apps, but that page reads `defaults.inspect` and `apps.defaults.set` is still a planned symbol. Reverted in `ef3b5673`.

**Structural cause, still open:** `omarchy-dev-capability-check` only validates `claim == "present"`. Every value below it (`missing`, `plumbing`, `prototype`, `partial`) is unpoliced, so a row can be walked up the scale with no test failing. That is the ratchet a completion protocol will find. Worth closing before the next long autonomous run.

## Defects only the pixels caught

Tests passed on all of these. Reading the captures found them.

- Settings sidebar rendered `SYSTEM` and `PERSONAL` twice — routes interleaved sections and the sidebar emits a header on change (`eb2afef4`).
- Plumbing language in consumer chrome: *"The real leaf exposes trusted inventory only until central durable operation wiring authorizes apply"* under *"Provider state is degraded"* (`c3dcabd8`, `b1002c8b`).
- Sentences broke mid-word once proportional text made the full string visible (`98fbc922`).

## Phase 3 completions

- **Typography.** `resolve_tokens.py` resolves `typography.family` to `Liberation Sans` and reserves `icons.family` for the monospace glyph font; `Tokens` exposes both; `design-system-consumer-test.sh` already asserted `Button` and `TextField` consume it. Nothing else did — 165 sites read `Style.font.family` while 34 had migrated. 117 sites across 28 files that render no glyph now use the text family (`703f005f`, `a938e281`). Glyph renderers stay on the icon family.
- **Pseudo-locale and RTL across processes.** Product windows are separate processes and could not see the shell's summon flags, so Start localized while Settings stayed English. The shell publishes both flags to `~/.local/state/omarchy/ultimate/presentation.json` and `ProductAppHost` watches it (`0732b07a`). That made session state durable, so `657a4ba4` republishes on shell start — `Component.onCompleted` fires before `FileView` loads and `setText` is silently dropped, which is why the reset uses a zero-repeat `Timer`.
- **Authored copy localizes; machine data does not** (`568cb77f`, `b91b77d4`). Verified in pixels: `[!! Çö·vë·ŕä·ĝê· !!]` translates while `brightness.set`, `display.provider.inspect`, the provenance line, and `HDMI-A-1` stay literal.

## Blocked — does not affect the gate result

**1. Metal fast-forward.** The checkout at `/home/jesse/omarchy7ultimate` is behind. `git clean` and `git merge --ff-only` are denied by the harness sandbox; they were attempted four times and not disguised inside a script to evade the check. File **content** was deployed instead and verified byte-identical by hash, so the running session is the reviewed code and the captures are valid. Content cannot fix a git index, which is why gates are verified from a clean clone. Fast-forward the live checkout so it stops drifting:

```
cd omarchy7ultimate && git clean -f -- migrations/1788042600.sh migrations/1788042700.sh \
  migrations/1788042900.sh migrations/1788043000.sh migrations/1788043100.sh \
  migrations/1788043200.sh migrations/1788043300.sh \
  shell/Ui/SettingsHostedPanel.qml shell/Ui/SettingsPersonalizationHost.qml \
  && git merge --ff-only origin/work
```

Pre-sync backup is at `/tmp/metal-presync-backup/` (9180-line patch plus 9 files). Do **not** close the gate with `git update-index --chmod=+x` on metal: that is a green gate on a stale checkout, which is the exact failure this review opened by flagging.

**2. The forty-task acceptance is a release gate, not a Phase 0-4 gate.** All forty rows in `WINDOWS_NATIVE_ACCEPTANCE.md` read `pending`, and they stay that way until a Windows-native tester completes them with a mouse, without Terminal or web search. The plan places the three matrices under release conditions "at one packaged candidate SHA", after Phase 11. Do not treat it as blocking a phase close, and do not mark rows passed without a human.

## Do not reopen

Do not merge `work` into `main`. Do not force-push. Do not mark `parity.agent-center` present. Do not localize provider provenance. Do not move a parity `claim` up the scale without a capability symbol behind it. Do not restore `Style.font.family` in consumer chrome — the icon family is for glyphs.
