#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
files_docs="$ROOT/docs/files-defaults-provider.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
controlpanel="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-catalog-controlpanel.md"
mimeapps="$ROOT/default/applications/mimeapps.list"
associations="$ROOT/default/ultimate/files/default-associations-v0.json"
helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"

[[ -f $files_app ]] || fail "Files application exists"
[[ -f $helper ]] || fail "session apply helper exists"
[[ -f $mimeapps ]] || fail "mimeapps.list exists"
[[ -f $associations ]] || fail "default associations catalog exists"

grep -Fq 'action: "entry.open"' "$files_app" || fail "Files uses the typed entry.open action"
grep -Fq 'function openEntry' "$files_app" || fail "Files hosts openEntry"
grep -Fq 'key: "open", label: "Open"' "$files_app" || fail "Files shows an Open control"
grep -Fq 'including .txt via the tip-true' "$files_app" || fail "Files banner names text-edit tip-true open"
grep -Fq 'no MIME association picker invent' "$files_app" || fail "Files banner refuses MIME association picker invent"
grep -Fq 'windows-native.18 stays prototype/pending' "$files_app" || fail "Files banner keeps windows-native.18 pending"
if grep -Eq 'Default Programs' "$files_app"; then
  fail "Files invents Default Programs UI"
fi
if grep -Eq 'Open With' "$files_app"; then
  fail "Files invents Open With UI"
fi
if grep -Eqi 'claim=present' "$files_app"; then
  fail "Files text edit must not invent claim=present"
fi
grep -Fq 'text/plain=org.gnome.TextEditor.desktop' "$mimeapps" ||
  fail "shipped mimeapps associates text/plain with TextEditor"
if grep -Eqi '^text/plain=.*(nvim|neovim|vim)\.desktop' "$mimeapps"; then
  fail "shipped mimeapps must not default text/plain to Neovim/vim"
fi
grep -Fq 'not Neovim-as-default' "$files_app" || fail "Files banner refuses Neovim-as-default"
grep -Fq '"text/plain"' "$associations" ||
  fail "Defaults association catalog lists text/plain"
grep -Fq 'files-entry-open' "$helper" || fail "session apply owns files-entry-open"
grep -Fq 'XDG_OPEN = "/usr/bin/xdg-open"' "$helper" || fail "open helper pins xdg-open absolute path"

pass "Files reuses tip-true entry.open for .txt graphical edit without Open With or Neovim-as-default invent"

python3 - "$catalog" "$jobs" "$debt" "$gaps" "$parity" "$files_docs" "$handoff" "$project" "$controlpanel" "$files_app" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
debt = json.loads(open(sys.argv[3], encoding="utf-8").read())
gaps = open(sys.argv[4], encoding="utf-8").read()
parity = open(sys.argv[5], encoding="utf-8").read()
files_docs = open(sys.argv[6], encoding="utf-8").read()
handoff = open(sys.argv[7], encoding="utf-8").read()
project = open(sys.argv[8], encoding="utf-8").read()
controlpanel = open(sys.argv[9], encoding="utf-8").read()
files_app = open(sys.argv[10], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
doc = by_id["files.text.edit"]
route = doc["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.text.edit route is {route}")
if route.get("path") != "Files > Text":
    raise SystemExit(f"files.text.edit path is {route}")
if route.get("label") != "Edit a text file":
    raise SystemExit(f"files.text.edit label is {route}")
if doc.get("source", {}).get("file") != "shell/apps/ultimate-files/FilesApplication.qml":
    raise SystemExit(f"files.text.edit source is {doc.get('source')}")
if doc.get("source", {}).get("symbol") != "openEntry":
    raise SystemExit(f"files.text.edit source is {doc.get('source')}")
if "nautilus" in str(doc.get("source") or "").lower():
    raise SystemExit(f"files.text.edit still names Nautilus: {doc.get('source')}")
if doc.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.text.edit must not claim present")
if doc.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.text.edit claim is {doc.get('availability')}")
if doc.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"files.text.edit human availability is {doc.get('availability')}")
if doc.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"files.text.edit agent availability is {doc.get('availability')}")
if doc.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"files.text.edit was raised off leftover: {doc.get('provider')}")
if doc.get("provider", {}).get("id") != "files.provider":
    raise SystemExit(f"files.text.edit provider is {doc.get('provider')}")
if doc.get("kind") != "writer":
    raise SystemExit(f"files.text.edit kind dual-truth (want writer/launch): {doc.get('kind')}")
if doc.get("effects") != ["launch"]:
    raise SystemExit(f"files.text.edit effects dual-truth (want launch): {doc.get('effects')}")
if doc.get("consent", {}).get("mode") != "implicit":
    raise SystemExit(f"files.text.edit consent dual-truth: {doc.get('consent')}")
if doc.get("idempotency", {}).get("mode") != "non-idempotent":
    raise SystemExit(f"files.text.edit idempotency dual-truth: {doc.get('idempotency')}")
if doc.get("cancellation", {}).get("mode") != "before-apply":
    raise SystemExit(f"files.text.edit cancellation dual-truth: {doc.get('cancellation')}")
if doc.get("recovery", {}).get("mode") != "none":
    raise SystemExit(f"files.text.edit recovery mode dual-truth: {doc.get('recovery')}")
if doc.get("recovery", {}).get("stateFingerprintRequired") is not False:
    raise SystemExit(f"files.text.edit recovery fingerprint invent: {doc.get('recovery')}")
if doc.get("schemas", {}).get("undo", {}).get("$ref", "").endswith("operationUndo"):
    raise SystemExit(f"files.text.edit undo schema invent: {doc.get('schemas')}")
rec = (doc.get("recovery") or {}).get("expectation") or ""
if "openEntry" not in rec or "xdg-open" not in rec:
    raise SystemExit(f"files.text.edit recoveryExpectation dual-truth: {doc.get('recovery')}")
if "fingerprint" in rec.lower() or "undo path" in rec.lower():
    raise SystemExit(f"files.text.edit still invents undo/fingerprint recovery: {doc.get('recovery')}")
if doc.get("schemas", {}).get("preflight", {}).get("$ref", "").endswith("notApplicable"):
    raise SystemExit(f"files.text.edit preflight drifted: {doc.get('schemas')}")

entry_open = by_id["files.entry.open"]
if entry_open.get("provider", {}).get("state") != "present":
    raise SystemExit(f"files.entry.open provider state drifted: {entry_open.get('provider')}")
if entry_open.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.entry.open claim drifted: {entry_open.get('availability')}")
if entry_open.get("source", {}).get("symbol") != "openEntry":
    raise SystemExit(f"files.entry.open source drifted: {entry_open.get('source')}")
if entry_open["humanRoute"].get("path") != "Files > Open":
    raise SystemExit(f"files.entry.open path drifted: {entry_open.get('humanRoute')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native18 = by_job["windows-native.18"]
if native18.get("claim") == "present":
    raise SystemExit("windows-native.18 must not claim present")
if native18.get("claim") != "prototype":
    raise SystemExit(f"windows-native.18 claim is {native18.get('claim')}")
if native18.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.18 sourceStatus is {native18.get('sourceStatus')}")
if native18.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.18 proofStatus is {native18.get('proofStatus')}")
caps = native18.get("capabilityIds") or []
if "files.entry.open" not in caps:
    raise SystemExit("windows-native.18 dropped files.entry.open")
if "files.text.edit" not in caps:
    raise SystemExit("windows-native.18 dropped files.text.edit")
if native18["humanRoute"].get("path") != "Files > Text":
    raise SystemExit(f"windows-native.18 path is {native18.get('humanRoute')}")
if native18["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.18 route is {native18.get('humanRoute')}")
wn18_rec = native18.get("recoveryExpectation") or ""
if "Preserve file history or a guarded undo artifact." in wn18_rec:
    raise SystemExit(f"windows-native.18 still invents undo recovery: {wn18_rec}")
if "openEntry" not in wn18_rec or "xdg-open" not in wn18_rec:
    raise SystemExit(f"windows-native.18 recoveryExpectation not tip-true: {wn18_rec}")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "files.text.edit" not in legacy.get("capabilityIds", []):
    raise SystemExit("files.text.edit is not leftover-direct debt")
if "capability:files.text.edit" not in legacy.get("surfaceRefs", []):
    raise SystemExit("files.text.edit leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "files.text.edit" not in agent.get("capabilityIds", []):
    raise SystemExit("files.text.edit is not agent-unavailable debt")
if "capability:files.text.edit" not in agent.get("surfaceRefs", []):
    raise SystemExit("files.text.edit agent surfaceRef is missing")

if "Honesty addendum 2026-09-06 vs Files Edit a text file leftover plane" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Files Edit a text file addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Files Edit a text file leftover plane", 1)[1].split("Honesty addendum", 1)[0]
if "session leftover recorded" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must record session leftover honesty for text edit")
if "not product CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse product CLOSED invent")
if "Cloud mocks do not close windows-native.18" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse closing windows-native.18 from Cloud mocks")
for required in (
    "Open With / MIME association UI",
    "Files LIVE metal",
    "Win7 visual",
    "Explorer present",
    "Fabric LIVE under SHELL",
    "Settings Power LIVE",
    "End Task LIVE",
    "Software Center present",
    "Update present",
    "claim=present",
):
    if required not in addendum:
        raise SystemExit(f"fleet-doctrine-gaps text-edit addendum dropped OPEN leftover: {required}")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal leftover CLOSED")
if "Files > Text" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name Files > Text")
if "entry.open" not in addendum and "files.entry.open" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name tip-true entry.open")
if "windows-native.18" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.18 pending")
if "Do not invent Open With / MIME association UI product-complete" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Open With invent")
if "Do not invent Neovim-as-default" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Neovim-as-default invent")
if "not Neovim-as-default" not in files_app:
    raise SystemExit("Files banner must refuse Neovim-as-default")
if "| `windows-native.18` | prototype/pending | visible: Files > Text |" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.18 prototype/pending")
if "Inventing Open With / MIME association UI / Neovim-as-default / claim=present / metal CLOSED from Cloud EXIT 0." not in gaps:
    raise SystemExit("fleet-doctrine-gaps must pin wn.18 invent-mode against Cloud EXIT 0 metal CLOSE")
if "Reverting to terminal editor." in gaps.split("`windows-native.18`", 1)[1][:400]:
    raise SystemExit("fleet-doctrine-gaps must retire tip-false Reverting to terminal editor invent cell")

if "Files > Text" not in parity:
    raise SystemExit("PARITY must name Files > Text")
if "files.text.edit" not in parity:
    raise SystemExit("PARITY must name files.text.edit")
if "windows-native.18` stays prototype/pending" not in parity and "windows-native.18` stays prototype/pending" not in parity:
    # tolerate backtick placement variants
    if "windows-native.18" not in parity or "prototype/pending" not in parity:
        raise SystemExit("PARITY must keep windows-native.18 prototype/pending")
explorer_row = ""
for line in parity.splitlines():
    if line.startswith("| Explorer / Computer |"):
        explorer_row = line
        break
if "this row is not present" not in explorer_row or "prototype" not in explorer_row:
    raise SystemExit("PARITY Explorer row must stay not present")
if "Edit a text file reuses tip-true" not in explorer_row and "files.text.edit" not in explorer_row:
    raise SystemExit("PARITY Explorer row must name text-edit leftover-attach")
if "Open With" in explorer_row and "no Open With" not in explorer_row:
    raise SystemExit("PARITY Explorer row invented Open With UI")

if "Honesty addendum 2026-09-06 vs Files Edit a text file leftover plane" not in handoff:
    raise SystemExit("HANDOFF must add a dated Files Edit a text file addendum")
if "files.text.edit" not in handoff:
    raise SystemExit("HANDOFF must name files.text.edit")
if "session leftover recorded" not in handoff:
    raise SystemExit("HANDOFF must record session leftover honesty")
if "Cloud mocks do not close windows-native.18" not in handoff:
    raise SystemExit("HANDOFF must refuse closing windows-native.18 from Cloud mocks")
if "Catalog tip-align 2026-09-06 MUST_FIX" not in handoff or "effects=`launch`" not in handoff or "not mutating invent" not in handoff:
    raise SystemExit("HANDOFF must tip-align files.text.edit writer/launch (not mutating invent)")
if "Catalog tip-align 2026-09-06 MUST_FIX" not in gaps or "effects=`launch`" not in gaps or "not mutating invent" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must tip-align files.text.edit writer/launch")
if "Catalog tip-align 2026-09-06 MUST_FIX" not in parity or "effects=`launch`" not in parity or "not mutating invent" not in parity:
    raise SystemExit("PARITY must tip-align files.text.edit writer/launch")
if "Catalog tip-align 2026-09-06 MUST_FIX" not in project or "effects=`launch`" not in project or "not mutating invent" not in project:
    raise SystemExit("project-ultimate must tip-align files.text.edit writer/launch")
if "Catalog tip-align 2026-09-06 MUST_FIX" not in files_docs or "effects=`launch`" not in files_docs or "not mutating invent" not in files_docs:
    raise SystemExit("files-defaults-provider must tip-align files.text.edit writer/launch")
if "Catalog tip-align 2026-09-06 MUST_FIX" not in controlpanel or "effects=`launch`" not in controlpanel or "not mutating invent" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must tip-align files.text.edit writer/launch")
if "not product CLOSED" not in handoff:
    raise SystemExit("HANDOFF must refuse product CLOSED invent")
if "Files › Text" not in handoff and "Files > Text" not in handoff:
    raise SystemExit("HANDOFF must name Files > Text")

if "files.text.edit" not in project:
    raise SystemExit("project-ultimate must name files.text.edit")
if "windows-native.18" not in project:
    raise SystemExit("project-ultimate must keep windows-native.18 pending")
if "session leftover recorded" not in project:
    raise SystemExit("project-ultimate must record session leftover honesty")
if "Cloud mocks do not close windows-native.18" not in project:
    raise SystemExit("project-ultimate must refuse closing windows-native.18 from Cloud mocks")
if "not product CLOSED" not in project:
    raise SystemExit("project-ultimate must refuse product CLOSED invent")

if "files.text.edit" not in files_docs:
    raise SystemExit("files-defaults-provider must name files.text.edit")
docs_slice = files_docs.split("files.entry.open", 1)[1][:2200]
if "files.text.edit" not in docs_slice:
    raise SystemExit("files-defaults-provider entry.open section must name files.text.edit")
if "windows-native.18" not in docs_slice:
    raise SystemExit("files-defaults-provider must keep windows-native.18 pending")
if "Open With" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse Open With invent")
if "session leftover recorded" not in docs_slice:
    raise SystemExit("files-defaults-provider must record session leftover honesty")
if "Cloud mocks do not close" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse closing windows-native.18 from Cloud mocks")

if "files.text.edit" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must name files.text.edit")
if "windows-native.18" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must keep windows-native.18 pending")
if "Open With" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must refuse Open With invent")

if "including .txt via the tip-true" not in files_app:
    raise SystemExit("Files banner must name text-edit tip-true open")
if "no MIME association picker invent" not in files_app:
    raise SystemExit("Files banner must refuse MIME association picker invent")
if "Default Programs" in files_app:
    raise SystemExit("Files invents Default Programs UI")
if "Open With" in files_app:
    raise SystemExit("Files invents Open With UI")
PY

pass "files.text.edit stays leftover partial with a visible Files > Text route soft-attached to entry.open"
