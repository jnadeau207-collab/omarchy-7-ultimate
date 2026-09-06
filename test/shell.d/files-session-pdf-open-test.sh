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
grep -Fq 'including PDF via the tip-true' "$files_app" || fail "Files banner names PDF tip-true open"
grep -Fq 'no MIME association picker invent' "$files_app" || fail "Files banner refuses MIME association picker invent"
grep -Fq 'windows-native.17 stays prototype/pending' "$files_app" || fail "Files banner keeps windows-native.17 pending"
if grep -Eq 'Default Programs' "$files_app"; then
  fail "Files invents Default Programs UI"
fi
if grep -Eq 'Open With' "$files_app"; then
  fail "Files invents Open With UI"
fi
if grep -Eqi 'claim=present' "$files_app"; then
  fail "Files PDF open must not invent claim=present"
fi
grep -Fq 'application/pdf=org.gnome.Evince.desktop' "$mimeapps" ||
  fail "shipped mimeapps associates application/pdf with Evince"
grep -Fq '"application/pdf"' "$associations" ||
  fail "Defaults association catalog lists application/pdf"
grep -Fq 'files-entry-open' "$helper" || fail "session apply owns files-entry-open"
grep -Fq 'XDG_OPEN = "/usr/bin/xdg-open"' "$helper" || fail "open helper pins xdg-open absolute path"

pass "Files reuses tip-true entry.open for PDF mouse open without Open With invent"

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
doc = by_id["files.document.open"]
route = doc["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.document.open route is {route}")
if route.get("path") != "Files > PDF":
    raise SystemExit(f"files.document.open path is {route}")
if route.get("label") != "Open a PDF":
    raise SystemExit(f"files.document.open label is {route}")
if doc.get("source", {}).get("file") != "shell/apps/ultimate-files/FilesApplication.qml":
    raise SystemExit(f"files.document.open source is {doc.get('source')}")
if doc.get("source", {}).get("symbol") != "openEntry":
    raise SystemExit(f"files.document.open source is {doc.get('source')}")
if "nautilus" in str(doc.get("source") or "").lower():
    raise SystemExit(f"files.document.open still names Nautilus: {doc.get('source')}")
if doc.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.document.open must not claim present")
if doc.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.document.open claim is {doc.get('availability')}")
if doc.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"files.document.open human availability is {doc.get('availability')}")
if doc.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"files.document.open agent availability is {doc.get('availability')}")
if doc.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"files.document.open was raised off leftover: {doc.get('provider')}")
if doc.get("provider", {}).get("id") != "files.provider":
    raise SystemExit(f"files.document.open provider is {doc.get('provider')}")

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
native17 = by_job["windows-native.17"]
if native17.get("claim") == "present":
    raise SystemExit("windows-native.17 must not claim present")
if native17.get("claim") != "prototype":
    raise SystemExit(f"windows-native.17 claim is {native17.get('claim')}")
if native17.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.17 sourceStatus is {native17.get('sourceStatus')}")
if native17.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.17 proofStatus is {native17.get('proofStatus')}")
caps = native17.get("capabilityIds") or []
if "files.entry.open" not in caps:
    raise SystemExit("windows-native.17 dropped files.entry.open")
if "files.document.open" not in caps:
    raise SystemExit("windows-native.17 dropped files.document.open")
if native17["humanRoute"].get("path") != "Files > PDF":
    raise SystemExit(f"windows-native.17 path is {native17.get('humanRoute')}")
if native17["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.17 route is {native17.get('humanRoute')}")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "files.document.open" not in legacy.get("capabilityIds", []):
    raise SystemExit("files.document.open is not leftover-direct debt")
if "capability:files.document.open" not in legacy.get("surfaceRefs", []):
    raise SystemExit("files.document.open leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "files.document.open" not in agent.get("capabilityIds", []):
    raise SystemExit("files.document.open is not agent-unavailable debt")
if "capability:files.document.open" not in agent.get("surfaceRefs", []):
    raise SystemExit("files.document.open agent surfaceRef is missing")

if "Honesty addendum 2026-09-06 vs Files Open a PDF leftover plane" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Files Open a PDF addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Files Open a PDF leftover plane", 1)[1].split("Honesty addendum", 1)[0]
if "session leftover recorded" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must record session leftover honesty for PDF open")
if "not product CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse product CLOSED invent")
if "Cloud mocks do not close windows-native.17" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse closing windows-native.17 from Cloud mocks")
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
        raise SystemExit(f"fleet-doctrine-gaps PDF addendum dropped OPEN leftover: {required}")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal leftover CLOSED")
if "Files > PDF" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name Files > PDF")
if "entry.open" not in addendum and "files.entry.open" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name tip-true entry.open")
if "windows-native.17" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.17 pending")
if "Do not invent Open With / MIME association UI product-complete" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Open With invent")
if "| `windows-native.17` | prototype/pending | visible: Files > PDF |" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.17 prototype/pending")
if "Inventing Open With / MIME association UI / claim=present / metal CLOSED from Cloud EXIT 0." not in gaps:
    raise SystemExit("fleet-doctrine-gaps must pin wn.17 invent-mode against Cloud EXIT 0 metal CLOSE")
if "Depends on associations+viewer." in gaps.split("`windows-native.17`", 1)[1][:400]:
    raise SystemExit("fleet-doctrine-gaps must retire tip-false associations+viewer invent cell")

if "Files > PDF" not in parity:
    raise SystemExit("PARITY must name Files > PDF")
if "files.document.open" not in parity:
    raise SystemExit("PARITY must name files.document.open")
if "windows-native.17` stays prototype/pending" not in parity and "windows-native.17` stays prototype/pending" not in parity:
    # tolerate backtick placement variants
    if "windows-native.17" not in parity or "prototype/pending" not in parity:
        raise SystemExit("PARITY must keep windows-native.17 prototype/pending")
explorer_row = ""
for line in parity.splitlines():
    if line.startswith("| Explorer / Computer |"):
        explorer_row = line
        break
if "this row is not present" not in explorer_row or "prototype" not in explorer_row:
    raise SystemExit("PARITY Explorer row must stay not present")
if "Open a PDF reuses tip-true" not in explorer_row and "files.document.open" not in explorer_row:
    raise SystemExit("PARITY Explorer row must name PDF leftover-attach")
if "Open With" in explorer_row and "no Open With" not in explorer_row:
    raise SystemExit("PARITY Explorer row invented Open With UI")

if "Honesty addendum 2026-09-06 vs Files Open a PDF leftover plane" not in handoff:
    raise SystemExit("HANDOFF must add a dated Files Open a PDF addendum")
if "files.document.open" not in handoff:
    raise SystemExit("HANDOFF must name files.document.open")
if "session leftover recorded" not in handoff:
    raise SystemExit("HANDOFF must record session leftover honesty")
if "Cloud mocks do not close windows-native.17" not in handoff:
    raise SystemExit("HANDOFF must refuse closing windows-native.17 from Cloud mocks")
if "not product CLOSED" not in handoff:
    raise SystemExit("HANDOFF must refuse product CLOSED invent")
if "Files › PDF" not in handoff and "Files > PDF" not in handoff:
    raise SystemExit("HANDOFF must name Files > PDF")

if "files.document.open" not in project:
    raise SystemExit("project-ultimate must name files.document.open")
if "windows-native.17" not in project:
    raise SystemExit("project-ultimate must keep windows-native.17 pending")
if "session leftover recorded" not in project:
    raise SystemExit("project-ultimate must record session leftover honesty")
if "Cloud mocks do not close windows-native.17" not in project:
    raise SystemExit("project-ultimate must refuse closing windows-native.17 from Cloud mocks")
if "not product CLOSED" not in project:
    raise SystemExit("project-ultimate must refuse product CLOSED invent")

if "files.document.open" not in files_docs:
    raise SystemExit("files-defaults-provider must name files.document.open")
docs_slice = files_docs.split("files.entry.open", 1)[1][:2200]
if "files.document.open" not in docs_slice:
    raise SystemExit("files-defaults-provider entry.open section must name files.document.open")
if "windows-native.17" not in docs_slice:
    raise SystemExit("files-defaults-provider must keep windows-native.17 pending")
if "Open With" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse Open With invent")
if "session leftover recorded" not in docs_slice:
    raise SystemExit("files-defaults-provider must record session leftover honesty")
if "Cloud mocks do not close" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse closing windows-native.17 from Cloud mocks")

if "files.document.open" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must name files.document.open")
if "windows-native.17" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must keep windows-native.17 pending")
if "Open With" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must refuse Open With invent")

if "including PDF via the tip-true" not in files_app:
    raise SystemExit("Files banner must name PDF tip-true open")
if "no MIME association picker invent" not in files_app:
    raise SystemExit("Files banner must refuse MIME association picker invent")
if "Default Programs" in files_app:
    raise SystemExit("Files invents Default Programs UI")
if "Open With" in files_app:
    raise SystemExit("Files invents Open With UI")
PY

pass "files.document.open stays leftover partial with a visible Files > PDF route soft-attached to entry.open"
