#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command python3
require_command node

for spec in \
  'Files files org.omarchy.Files omarchy-ultimate-files omarchy-files omarchy.files ultimate-files FilesApplication.qml' \
  'Software software org.omarchy.Software omarchy-ultimate-software omarchy-software omarchy.software ultimate-software SoftwareApplication.qml' \
  'Compatibility compatibility org.omarchy.Compatibility omarchy-ultimate-compatibility omarchy-compatibility omarchy.compatibility ultimate-compatibility CompatibilityApplication.qml'; do
  read -r label application app_id shell_id fabric_id ipc_target directory application_qml <<<"$spec"
  entrypoint="$ROOT/shell/ultimate-$application.qml"
  catalog="$ROOT/shell/apps/$directory/routes-v1.json"
  desktop="$ROOT/applications/$app_id.desktop"
  command="$ROOT/bin/omarchy-launch-$application"

  grep -Fqx "//@ pragma AppId $app_id" "$entrypoint" || fail "$label declares its stable AppId"
  grep -Fqx "//@ pragma ShellId $shell_id" "$entrypoint" || fail "$label declares its isolated ShellId"
  grep -Fqx "//@ pragma DataDir \$BASE/omarchy/$application" "$entrypoint" || fail "$label declares its isolated data directory"
  grep -Fqx "//@ pragma StateDir \$BASE/omarchy/$application" "$entrypoint" || fail "$label declares its isolated state directory"
  grep -Fqx "//@ pragma CacheDir \$BASE/omarchy/$application" "$entrypoint" || fail "$label declares its isolated cache directory"
  grep -Fqx "  fabricIdentity: \"$fabric_id\"" "$entrypoint" || fail "$label declares its Fabric client identity"
  if [[ $application == "files" ]]; then
    grep -Fqx '  fabricAllowedMethods: ["provider.catalog", "provider.read", "operation.preflight", "operation.approve", "operation.start", "operation.get"]' "$entrypoint" ||
      fail "$label has the exact read plus bounded-operation Fabric allowlist"
  else
    grep -Fqx '  fabricAllowedMethods: ["provider.catalog", "provider.read"]' "$entrypoint" || fail "$label has the exact read-only Fabric allowlist"
  fi
  grep -Fqx "  ipcTarget: \"$ipc_target\"" "$entrypoint" || fail "$label declares its distinct IPC target"
  grep -Fqx "  applicationSourcePath: \"apps/$directory/$application_qml\"" "$entrypoint" || fail "$label loads only its own application surface"

  grep -Fqx "StartupWMClass=$app_id" "$desktop" || fail "$label desktop identity matches its AppId"
  grep -Fqx "TryExec=omarchy-launch-$application" "$desktop" || fail "$label desktop entry names its canonical launcher"
  grep -Fq "Exec=omarchy-launch-$application --source desktop" "$desktop" || fail "$label desktop entry routes through its canonical launcher"
  grep -Fqx "MimeType=x-scheme-handler/omarchy-$application;" "$desktop" || fail "$label desktop entry registers its deep-link scheme"
  grep -Fq 'Actions=' "$desktop" || fail "$label desktop entry exposes route actions"

  grep -Fqx '#!/bin/bash' "$command" || fail "$label launcher uses the repository bash shebang"
  grep -Fq '# omarchy:summary=' "$command" || fail "$label launcher declares command metadata"
  grep -Fqx "launch_product_app $application \"\$@\"" "$command" || fail "$label launcher uses the shared single-instance seam"

  python3 - "$catalog" "$application" "$app_id" <<'PY' || fail "$label route catalog identity is closed"
import json
import re
import sys

path, application, app_id = sys.argv[1:]
catalog = json.load(open(path, encoding="utf-8"))
assert set(catalog) == {"schemaVersion", "application", "appId", "scheme", "defaultRoute", "routes", "entityDeepLinks"}
assert catalog["schemaVersion"] == "omarchy.product-routes/v1"
assert catalog["application"] == application
assert catalog["appId"] == app_id
assert catalog["scheme"] == f"omarchy-{application}"
assert catalog["defaultRoute"] in {route["id"] for route in catalog["routes"]}
assert len({route["id"] for route in catalog["routes"]}) == len(catalog["routes"])
assert all(route["providerId"] in {"files.provider", "packages.provider", "compatibility.provider"} for route in catalog["routes"])
assert all(re.fullmatch(r"[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*", route["id"]) for route in catalog["routes"])
PY

  pass "$label joins stable process, compositor, desktop, launcher, IPC, Fabric, and route identities"
done

python3 - "$ROOT" <<'PY' || fail "Domain product route catalogs expose exact deep-link coverage"
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
expected = {
    "ultimate-files": ({"location", "entry", "mount"}, {"files.overview", "files.this-pc", "files.desktop", "files.documents", "files.downloads", "files.pictures", "files.music", "files.videos", "files.recent", "files.search", "files.trash", "files.network"}),
    "ultimate-software": ({"software", "installation", "operation"}, {"software.catalog", "software.installed", "software.adoption", "software.history"}),
    "ultimate-compatibility": ({"deployment"}, {"compatibility.overview", "compatibility.decide", "compatibility.deployments"}),
}
for directory, (entity_types, routes) in expected.items():
    catalog = json.loads((root / "shell/apps" / directory / "routes-v1.json").read_text())
    assert {route["id"] for route in catalog["routes"]} == routes
    assert {link["entityType"] for link in catalog["entityDeepLinks"]} == entity_types
PY
pass "Domain product routes and entity deep links cover the complete reviewed read surface"

python3 - "$ROOT" <<'PY' || fail "Domain product contract registration is incomplete or overprivileged"
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
contracts = root / "default/ultimate/product-contracts"
applications = {entry["id"]: entry for entry in json.loads((contracts / "applications-v0.json").read_text())["applications"]}
endpoints = {entry["target"]: entry for entry in json.loads((contracts / "ipc-v0.json").read_text())["endpoints"]}
processes = {entry["id"]: entry for entry in json.loads((contracts / "processes-v0.json").read_text())["processes"]}
expected = {
    "files": ("org.omarchy.Files", "omarchy.files", "omarchy-files", True),
    "software": ("org.omarchy.Software", "omarchy.software", "omarchy-software", False),
    "compatibility": ("org.omarchy.Compatibility", "omarchy.compatibility", "omarchy-compatibility", False),
}
methods = ["activate", "status", "route", "processId", "fabricClientIdentity", "fabricEndpointPrincipal"]
for application, (desktop_id, ipc_target, scheme, shipped_pin) in expected.items():
    app = applications[f"app.omarchy.{application}"]
    process_id = f"process.omarchy-ultimate-{application}"
    assert app["availability"] == "present-contract"
    assert app["currentPrincipalId"] == "principal.fabric.owner-rpc"
    assert app["processId"] == process_id
    assert app["desktopIds"] == [desktop_id]
    assert app["compositorMatchers"] == [desktop_id]
    assert app["taskbar"] == {"visibility": "dynamic", "shippedPin": shipped_pin, "identityJoin": "stable"}
    assert app["singleInstance"] == {"mode": "reuse-existing", "activation": "deep-link", "state": "contract"}
    assert app["deepLinks"][0]["scheme"] == scheme
    assert app["debtIds"] == ["debt.identity.product-principal-unbound"]

    endpoint = endpoints[ipc_target]
    assert endpoint["sourcePath"] == "shell/apps/shared/ProductAppHost.qml"
    assert endpoint["methods"] == methods
    assert endpoint["processId"] == process_id
    assert endpoint["principalBinding"] == "legacy-owner-socket-only"
    assert endpoint["debtIds"] == ["debt.ipc.caller-unbound"]

    process = processes[process_id]
    assert process["principalId"] == "principal.fabric.owner-rpc"
    assert process["ownerPath"] == f"shell/ultimate-{application}.qml"
    assert process["state"] == "present"
    assert process["debtIds"] == ["debt.identity.product-principal-unbound"]
PY
pass "Domain products are registered as stable standalone apps, isolated IPC endpoints, and read-only Fabric processes"

for directory in ultimate-files ultimate-software ultimate-compatibility; do
  if grep -R -n -E --include='*.qml' '(^|[^A-Za-z])(Process[[:space:]]*\{|Quickshell\.execDetached|execDetached\(|ShellCommand|CommandModel|pkexec|sudo|hyprctl|systemctl|pacman|yay|flatpak|gio[[:space:]]|rm[[:space:]]|mv[[:space:]]|cp[[:space:]])' "$ROOT/shell/apps/$directory"; then
    fail "$directory consumer QML contains a direct command, privilege, or filesystem mutation path"
  fi
  if grep -R -n -E 'provider\.(invoke|preflight)|reference\.operation|managed-work\.query' "$ROOT/shell/apps/$directory" "$ROOT/shell/ultimate-${directory#ultimate-}.qml"; then
    fail "$directory broadens its read-only Fabric contract"
  fi
  grep -R -q --include='*.qml' 'Accessible.role:' "$ROOT/shell/apps/$directory" || fail "$directory declares accessible roles"
  grep -R -q --include='*.qml' 'focusable: true' "$ROOT/shell/apps/$directory" || fail "$directory exposes keyboard-operable controls"
  grep -R -q -E --include='*.qml' 'Text\.WrapAnywhere|Text\.WordWrap' "$ROOT/shell/apps/$directory" || fail "$directory guards long strings"
done
pass "Domain product QML is command-free, least-privilege, accessible, and long-string safe"

for model in \
  "$ROOT/shell/apps/ultimate-files/FilesModel.js" \
  "$ROOT/shell/apps/ultimate-software/SoftwareModel.js" \
  "$ROOT/shell/apps/ultimate-compatibility/CompatibilityModel.js"; do
  grep -q 'MAX_VISIBLE_RECORDS' "$model" || fail "$model bounds visible records"
  grep -q -E 'provider\.changed-during-read|generation' "$model" || fail "$model isolates provider generations"
  grep -q 'rpc.cancelled' "$model" || fail "$model maps interruption explicitly"
  grep -q 'provider.unavailable' "$model" || fail "$model maps unavailable state explicitly"
  grep -q 'client.method-denied' "$model" || fail "$model maps denied state explicitly"
  if grep -n -E 'provider\.(invoke|preflight)|exec\(|spawn\(|child_process|mockData|fallbackData' "$model"; then
    fail "$model contains mutation, process, mock-data, or fallback authority"
  fi
done
pass "Domain controllers bound results, isolate generations, and expose honest failure states"

grep -Fq 'root.width < 900' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files has a narrow responsive layout"
grep -Fq 'contentScroll.availableWidth >= 1050' "$ROOT/shell/apps/ultimate-software/SoftwareApplication.qml" || fail "Software Center has a wide responsive layout"
grep -Fq 'contentScroll.availableWidth >= 760 ? 2 : 1' "$ROOT/shell/apps/ultimate-compatibility/CompatibilityApplication.qml" || fail "Compatibility input form responds across narrow and normal widths"
pass "All three applications define narrow, normal, and wide layout behavior"

for spec in \
  'Software shell/apps/ultimate-software/SoftwareApplication.qml' \
  'Compatibility shell/apps/ultimate-compatibility/CompatibilityApplication.qml'; do
  read -r label application <<<"$spec"
  grep -Fq 'readonly property var productProfile: host && host.productProfile ? host.productProfile : null' "$ROOT/$application" \
    || fail "$label reads the standalone host SemanticProfile"
  grep -A6 'visible: root.canRetry' "$ROOT/$application" | grep -Fq 'semanticProfile: root.productProfile' \
    || fail "$label Reconnect/Retry consumes Semantics.text through Ui.Button"
  grep -Fq 'Shared.FabricStatusBanner { host: root.host; semanticProfile: root.productProfile; Layout.fillWidth: true }' "$ROOT/$application" \
    || fail "$label Try again banner consumes the host SemanticProfile"
done
pass "Software and Compatibility Reconnect/Try again consume the host SemanticProfile"

grep -Fq 'productProfile: root.productProfile' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files passes the host SemanticProfile into Explorer Aero chrome"
grep -Fq 'Semantics.text(root.productProfile, modelData.label)' "$ROOT/shell/apps/ultimate-files/ExplorerCommandBar.qml" \
  || fail "Files command bar verbs route through Semantics.text"
grep -Fq 'Semantics.text(root.productProfile, "Change your view")' "$ROOT/shell/apps/ultimate-files/ExplorerCommandBar.qml" \
  || fail "Files view-menu affordance routes through Semantics.text"
grep -Fq 'index === 0 ? Semantics.text(root.productProfile, modelData.label) : modelData.label' "$ROOT/shell/apps/ultimate-files/ExplorerAddressBar.qml" \
  || fail "Files address-bar route crumb is chrome; path crumbs stay literal"
grep -Fq 'Semantics.text(root.productProfile, "Refresh")' "$ROOT/shell/apps/ultimate-files/ExplorerAddressBar.qml" \
  || fail "Files address-bar Refresh routes through Semantics.text"
grep -Fq 'Semantics.text(root.productProfile, root.searchPlaceholder)' "$ROOT/shell/apps/ultimate-files/ExplorerAddressBar.qml" \
  || fail "Files address-bar Search placeholder routes through Semantics.text"
grep -Fq 'Semantics.text(root.productProfile, root.direction === "back" ? "Back" : "Forward")' "$ROOT/shell/apps/ultimate-files/ExplorerCircleButton.qml" \
  || fail "Files address-bar Back/Forward names route through Semantics.text"
grep -Fq 'Semantics.text(root.productProfile, modelData.label)' "$ROOT/shell/apps/ultimate-files/ExplorerItemView.qml" \
  || fail "Files details view labels route through Semantics.text"
if grep -Fq 'Semantics.text(root.productProfile, detailRow.modelData.title)' "$ROOT/shell/apps/ultimate-files/ExplorerItemView.qml"; then
  fail "Files entry titles are machine data and must not be pseudo-localized"
fi
if grep -Fq 'Semantics.text(root.productProfile, detailRow.modelData.typeLabel)' "$ROOT/shell/apps/ultimate-files/ExplorerItemView.qml"; then
  fail "Files type cells are machine data and must not be pseudo-localized"
fi
pass "Files Explorer Aero chrome routes through Semantics.text; path and entry cells stay literal"

grep -Fq 'USER-DECLARED INPUT' "$ROOT/shell/apps/ultimate-compatibility/CompatibilityApplication.qml" || fail "Compatibility labels unmeasured host input"
grep -Fq 'Deployment remains unavailable' "$ROOT/shell/apps/ultimate-compatibility/CompatibilityModel.js" || fail "Compatibility preserves its plan-only boundary"
grep -Fq 'This surface never invokes a package manager' "$ROOT/shell/apps/ultimate-software/SoftwareApplication.qml" || fail "Software Center states its execution boundary"
grep -Fq 'File contents are never read' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files states its content-read boundary"
grep -Fq 'New folder runs through files.provider' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner names the live New folder writer"
grep -Fq 'Rename runs through files.provider entry.rename' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner names the live Rename writer"
grep -Fq 'Copy and Paste run through files.provider entry.copy' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner names the live Copy writer"
grep -Fq 'The cut/move write plane exists but is not shell-authorizable' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner names the cut/move write plane as not shell-authorizable"
grep -Fq 'The OS clipboard stays unavailable' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner keeps OS clipboard unavailable"
grep -Fq 'readonly property bool cutAuthorized: false' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files pins cutAuthorized false; Cut is not LIVE under the shell principal"
if grep -Eq 'cutAuthorized:\s*true' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml"; then
  fail "Files must not authorize shell consequential move"
fi
grep -Fq 'files.entry.move' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS names files.entry.move"
grep -Fq 'cutAuthorized=false' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS residual names Files Cut UI gated cutAuthorized=false"
grep -Fq '`files.entry.move` is write-plane reachable' "$ROOT/docs/files-defaults-provider.md" \
  || fail "files-defaults-provider names the entry.move write plane"
grep -Fq 'Trash write plane exists but is not shell-authorizable' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner states Trash is not shell-authorizable"
grep -Fq 'CHANGES UNAVAILABLE' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner names CHANGES UNAVAILABLE for Trash"
grep -Fq 'Restore write plane exists but is not shell-authorizable' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner names the Restore write plane as not shell-authorizable"
grep -Fq 'The permanent delete write plane exists but is not shell-authorizable' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner names the permanent delete write plane as not shell-authorizable"
grep -Fq 'Restore UI, empty Recycle Bin, and files.trash.manage remain unavailable' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner keeps Restore UI and files.trash.manage unavailable"
grep -Fq 'readonly property bool deleteAuthorized: false' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files pins deleteAuthorized false; permanent Delete is not LIVE under the shell principal"
if grep -Eq 'deleteAuthorized:\s*true' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml"; then
  fail "Files must not authorize shell consequential permanent delete"
fi
if grep -Eq 'action: "entry.delete"' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml"; then
  fail "Files invents LIVE permanent delete under SHELL"
fi
grep -Fq 'files.entry.delete' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS names files.entry.delete"
grep -Fq 'deleteAuthorized=false' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS residual names Files Delete UI gated deleteAuthorized=false"
grep -Fq 'OS clipboard residual OPEN after PR #60' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" \
  || fail "HANDOFF_WRITERS keeps OS clipboard residual OPEN after PR #60"
grep -Fq 'folder copy CLOSED' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" \
  || fail "HANDOFF_WRITERS names folder copy CLOSED"
grep -Fq 'The permanent delete write plane exists but is not shell-authorizable' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" \
  || fail "HANDOFF_WRITERS keeps permanent delete not shell-authorizable"
grep -Fq '`files.entry.delete` is write-plane reachable' "$ROOT/docs/files-defaults-provider.md" \
  || fail "files-defaults-provider names the entry.delete write plane"
grep -Fq 'files.trash.manage remain unavailable' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner does not invent files.trash.manage"
grep -Fq 'readonly property bool trashAuthorized: false' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files pins trashAuthorized false; Trash is not LIVE under the shell principal"
grep -Fq 'if (key === "delete") { if (!root.trashAuthorized) return; root.trashEntry(root.selectedRecord); return }' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files invoke delete refuses while trashAuthorized is false"
grep -Fq 'else if (event.key === Qt.Key_Delete) { if (!root.trashAuthorized) return; root.trashEntry(root.selectedRecord); event.accepted = true }' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files Key_Delete refuses while trashAuthorized is false"
if grep -Fq 'if (key === "delete") { root.trashEntry(root.selectedRecord); return }' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml"; then
  fail "Files invoke delete must not accept Delete while unauthorized"
fi
if grep -Fq 'else if (event.key === Qt.Key_Delete) { root.trashEntry(root.selectedRecord); event.accepted = true }' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml"; then
  fail "Files Key_Delete must not accept Delete while unauthorized"
fi
grep -Fq 'readonly property bool createEnabled: createVisible && !operationBusy && host !== null && host.fabricReady' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files keeps New folder createEnabled LIVE"
grep -Fq 'readonly property bool renameAuthorized: true' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files pins renameAuthorized true; Rename is SHELL-grantable"
grep -Fq 'readonly property bool copyAuthorized: true' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files pins copyAuthorized true; Copy is SHELL-grantable"
if grep -Eq 'trashAuthorized:\s*true' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml"; then
  fail "Files must not authorize shell consequential trash"
fi
if grep -Eq 'files-entry-trash.*helper only|The actual blocker is the schema family' "$ROOT/HANDOFF_WRITERS_2026-09-01.md"; then
  fail "HANDOFF_WRITERS must not claim entry.trash is helper-only or schema-blocked after the v1 directory family widen"
fi
grep -Fq 'grant.shell-consequential' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS names the SHELL consequential refuse for entry.trash"
grep -Fq 'files.trash.manage' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS keeps files.trash.manage unavailable"
grep -Fq 'trashAuthorized=false' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS residual names Files Trash UI gated trashAuthorized=false"
grep -Fq 'files.entry.rename' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS names files.entry.rename"
grep -Fq 'renameAuthorized=true' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS residual names Files Rename UI gated renameAuthorized=true"
grep -Fq 'files.entry.copy' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS names files.entry.copy"
grep -Fq 'copyAuthorized=true' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS residual names Files Copy UI gated copyAuthorized=true"
grep -Fq '`files.entry.copy` is write-plane reachable' "$ROOT/docs/files-defaults-provider.md" \
  || fail "files-defaults-provider names the entry.copy write plane"
grep -Fq 'Copy maps `EXDEV` errno from `mkdir`/`open` only' "$ROOT/docs/files-defaults-provider.md" \
  || fail "files-defaults-provider names copy EXDEV as errno-only"
if grep -Fq 'unsafe `EXDEV`' "$ROOT/docs/files-defaults-provider.md"; then
  fail "files-defaults-provider still claims copy refuses unsafe EXDEV"
fi
if grep -Fq 'unsafe `EXDEV`' "$ROOT/HANDOFF_WRITERS_2026-09-01.md"; then
  fail "HANDOFF_WRITERS still claims copy refuses unsafe EXDEV"
fi
grep -Fq 'cross-device `EXDEV`' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" \
  || fail "HANDOFF_WRITERS keeps move cross-device EXDEV"
grep -Fq 'Files Copy and Paste use that plane with in-app staging' "$ROOT/docs/files-defaults-provider.md" \
  || fail "files-defaults-provider names in-app staging instead of an OS clipboard"
grep -Fq 'Folder copy CLOSED via `files.entry.copy` directories' "$ROOT/docs/files-defaults-provider.md" \
  || fail "files-defaults-provider names folder copy CLOSED"
grep -Fq 'OS clipboard residual OPEN after PR #60' "$ROOT/docs/files-defaults-provider.md" \
  || fail "files-defaults-provider keeps OS clipboard residual OPEN after PR #60"
grep -Fq 'The permanent delete write plane exists but is not shell-authorizable' "$ROOT/docs/files-defaults-provider.md" \
  || fail "files-defaults-provider keeps permanent delete not shell-authorizable"
grep -Fq 'Recycle / Empty Bin / `files.trash.manage` residual OPEN' "$ROOT/docs/files-defaults-provider.md" \
  || fail "files-defaults-provider keeps Recycle residual OPEN"
if grep -Fq 'No permanent-delete capability exists in this tranche' "$ROOT/docs/files-defaults-provider.md"; then
  fail "files-defaults-provider still underclaims permanent delete after PR #60"
fi
if grep -Fq 'It does not invent cut, copy, paste, or a move-across-directories verb' "$ROOT/docs/files-defaults-provider.md"; then
  fail "files-defaults-provider still claims copy and paste are uninvented"
fi
if grep -Eq 'maximumLineCount:[[:space:]]*2' "$ROOT/shell/apps/ultimate-files/ExplorerDetailsPane.qml"; then
  fail "Files details boundary Text is limited to 2 lines and can clip the unavailable half"
fi
python3 - "$ROOT" <<'PY' || fail "Settings and Administration Coverage honesty Texts still ElideRight-clip"
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
paths = (
    root / "shell/apps/ultimate-settings/SettingsApplication.qml",
    root / "shell/apps/ultimate-administration/AdministrationApplication.qml",
)
for path in paths:
    text = path.read_text(encoding="utf-8")
    start = text.find("id: coverageColumn")
    if start < 0:
        raise SystemExit(f"{path.name}: coverageColumn missing")
    end = text.find("GridLayout", start)
    block = text[start:end] if end > start else text[start : start + 4000]
    if "ElideRight" in block:
        raise SystemExit(f"{path.name}: coverageColumn still uses ElideRight on honesty text")
    coverage = re.search(
        r"query\.coverage[\s\S]{0,500}?maximumLineCount:\s*(\d+)",
        block,
    )
    if coverage and int(coverage.group(1)) < 12:
        raise SystemExit(
            f"{path.name}: coverage Text maximumLineCount {coverage.group(1)} can clip PARTIAL LIVE CONTROL / CHANGES UNAVAILABLE"
        )
    declared = re.search(
        r"Declared provider operations[\s\S]{0,700}?maximumLineCount:\s*(\d+)",
        block,
    )
    if declared and int(declared.group(1)) < 8:
        raise SystemExit(
            f"{path.name}: declared-operations Text maximumLineCount {declared.group(1)} can clip honesty copy"
        )
PY
python3 - "$ROOT" <<'PY' || fail "Settings Personalization honesty/coverage still invent Phase 5 or underclaim the hosted picker"
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
model = (root / "shell/apps/ultimate-settings/SettingsModel.js").read_text(encoding="utf-8")
coverage = re.search(r'routeId: "settings.personalization.overview"[\s\S]*?coverage: "([^"]+)"', model)
honesty = re.search(r'if \(id === "settings.personalization.overview"\) return \{[\s\S]*?honesty: "([^"]+)"', model)
if not coverage:
    raise SystemExit("personalization coverage string missing")
if not honesty:
    raise SystemExit("personalization hosted honesty string missing")
for label, text in (("coverage", coverage.group(1)), ("honesty", honesty.group(1))):
    if re.search(r"phase 5", text, re.I):
        raise SystemExit(f"personalization {label} still invents a Phase 5 fence")
    if re.search(r"remains phase 5", text, re.I):
        raise SystemExit(f"personalization {label} still invents a remains-Phase-5 fence")
    if "image picker" not in text:
        raise SystemExit(f"personalization {label} must name the hosted picker")
    if "unavailable" not in text:
        raise SystemExit(f"personalization {label} must still refuse typed writers")
if "not represented as live state" in coverage.group(1):
    raise SystemExit("personalization coverage underclaims the hosted picker as non-live")
if "No code-owned personalization.provider is registered" not in coverage.group(1):
    raise SystemExit("personalization coverage must not invent a registered typed writer inventory")
PY
python3 - "$ROOT" <<'PY' || fail "PARITY Desktop/Context-menus or project-ultimate Current position still invent a Phase-N fence"
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
parity = (root / "WINDOWS_7_ULTIMATE_PARITY.md").read_text(encoding="utf-8")
plan = (root / "plans/project-ultimate.md").read_text(encoding="utf-8")

def table_row(md, job):
    for line in md.splitlines():
        if line.startswith("| ") and line[2:].startswith(job):
            return line
    raise SystemExit(f"PARITY row missing: {job}")

desktop = table_row(parity, "Desktop (icons")
context = table_row(parity, "Context menus")
explorer = table_row(parity, "Explorer / Computer")
for label, row in (("Desktop", desktop), ("Context menus", context)):
    if re.search(r"remain Phase 6|stay Phase 6|Phase 6", row):
        raise SystemExit(f"{label} row still invents a Phase 6 fence")
    if not re.search(r"unavailable|not product-complete", row, re.I):
        raise SystemExit(f"{label} row must name unavailable / not product-complete")
if "command-bar Delete exists on writable location routes" in context:
    raise SystemExit("Context menus row still invents command-bar Delete as present")
if "trashAuthorized=false" not in context:
    raise SystemExit("Context menus row must gate Delete/Trash at trashAuthorized=false")
if "write plane reachable" not in context or "not shell-authorizable" not in context:
    raise SystemExit("Context menus row must name the trash write plane as reachable but not shell-authorizable")
if "offers Trash" in desktop:
    raise SystemExit("Desktop row still says offers Trash")
if "trashAuthorized=false" not in desktop:
    raise SystemExit("Desktop row must gate Delete/Trash at trashAuthorized=false")
if "Trash applies" in explorer:
    raise SystemExit("Explorer row still says Trash applies")
if "trashAuthorized=false" not in explorer:
    raise SystemExit("Explorer row must gate Delete/Trash at trashAuthorized=false")
if "honest-unavailable" not in desktop:
    raise SystemExit("Desktop row dropped Restore honest-unavailable")
if "files.trash.manage" not in desktop:
    raise SystemExit("Desktop row dropped files.trash.manage missing")
if "Recycle Bin / files.trash.manage residual OPEN after PR #60" not in desktop:
    raise SystemExit("Desktop row dropped Recycle leftover after PR #60")
if "not product-complete" not in desktop:
    raise SystemExit("Desktop row dropped Recycle not product-complete")
if "prototype" not in desktop:
    raise SystemExit("Desktop row dropped prototype claim")
if "Typed Settings services are Phase 5" in plan:
    raise SystemExit("project-ultimate still blankets typed Settings as Phase 5")
scope = None
for line in plan.splitlines():
    if "Jump lists and Agent Center UI" in line and "Peek captures live window thumbnails" in line:
        scope = line
        break
if not scope:
    raise SystemExit("project-ultimate W0/current-program Settings bullet missing")
if re.search(r"Phase 5", scope):
    raise SystemExit("Current position Settings bullet still invents a Phase 5 fence")
needed = ["volume", "Wi-Fi", "brightness", "layout", "default browser"]
missing = [name for name in needed if name.lower() not in scope.lower()]
if missing:
    raise SystemExit(f"Current position Settings bullet missing live-writer split: {missing}")
live_clause = scope.split("Live Settings writers are", 1)
if len(live_clause) < 2:
    raise SystemExit("Current position Settings bullet missing Live Settings writers clause")
live_list = live_clause[1].split(";", 1)[0]
if "Power" in live_list:
    raise SystemExit("Current position Settings bullet still lists Power as a live writer")
if "power" not in scope.lower() or "polkit" not in scope.lower() or "inspect-only" not in scope.lower():
    raise SystemExit("Current position Settings bullet must name Power as inspect-only polkit residual")
if "inspect-only" not in scope.lower() and "hosted" not in scope.lower():
    raise SystemExit("Current position Settings bullet must keep inspect-only / hosted picker")
api = (root / "docs/settings-service-api.md").read_text(encoding="utf-8")
if "Typed writers remain Phase 5" in api or "remain Phase 5" in api:
    raise SystemExit("settings-service-api still blankets typed writers as remaining Phase 5")
if "not yet typed" in api:
    raise SystemExit("settings-service-api still invents that heritage panels mean Settings writers are not yet typed")
needed_api = ["Sound volume", "Network Wi-Fi radio", "Display brightness", "Input layout", "Apps default browser"]
missing_api = [name for name in needed_api if name not in api]
if missing_api:
    raise SystemExit(f"settings-service-api missing live-writer split: {missing_api}")
if "Power profile" not in api or "polkit" not in api:
    raise SystemExit("settings-service-api must name Power profile as a polkit residual")
if "unverified on metal" not in api:
    raise SystemExit("settings-service-api must name the Superbar QS Power leftover unverified on metal")
if "Night light remains a Superbar leftover" not in api:
    raise SystemExit("settings-service-api must keep night light as a Superbar leftover, not Settings LIVE")
if "Live typed writers are Sound volume, Network Wi-Fi radio, Power profile," in api:
    raise SystemExit("settings-service-api still lists Power profile among live typed writers")
if "inspect-only" not in api.lower() and "hosted" not in api.lower():
    raise SystemExit("settings-service-api must keep inspect-only / hosted picker")
if "Accessibility, Input, and System information have no hostable panel" in api:
    raise SystemExit("settings-service-api underclaims Input as having no hostable panel")
if "keyboard-layout" not in api:
    raise SystemExit("settings-service-api must name the Input keyboard-layout writer")
if "Accessibility" not in api or "System information" not in api:
    raise SystemExit("settings-service-api must keep Accessibility and System information honest missing")
if "Process" not in api or "execDetached" not in api:
    raise SystemExit("settings-service-api must keep Personalization Process/execDetached honesty")
if re.search(r"events\.subscribe|MIME associations|Empty Bin|Task Manager LIVE|End Task LIVE", api):
    raise SystemExit("settings-service-api invents MIME, Empty Bin, Task Manager LIVE, End Task LIVE, or events.subscribe")
model = (root / "shell/apps/ultimate-settings/SettingsModel.js").read_text(encoding="utf-8")
honesty_fn = re.search(r"function declaredOpsHonesty\(routeId\) \{[\s\S]*?\n\}", model)
if not honesty_fn:
    raise SystemExit("declaredOpsHonesty missing")
honesty_strings = re.findall(r'"([^"]+)"', honesty_fn.group(0))
if len(honesty_strings) < 2:
    raise SystemExit("declaredOpsHonesty unavailable string missing")
unavailable = honesty_strings[1]
if " yet" in unavailable or re.search(r"phase 5", unavailable, re.I) or re.search(r"remain Phase", unavailable):
    raise SystemExit("declaredOpsHonesty still invents forthcoming writers with yet / Phase 5 / remain Phase")
if "no preflight, approval, or execution control" not in unavailable:
    raise SystemExit("declaredOpsHonesty must keep unavailable / not-exposed honesty")
if "not available yet" in model or " yet." in model:
    raise SystemExit("SettingsModel.js still invents forthcoming writers with not available yet")
footer_fn = re.search(r"function authorityFooter\(\) \{[\s\S]*?\n\}", model)
if not footer_fn:
    raise SystemExit("authorityFooter missing")
footer = footer_fn.group(0)
if "F5" not in footer or "Retry" not in footer or "focused" not in footer:
    raise SystemExit("authorityFooter must name F5 / Retry for focused out-of-band stale")
if "re-read when shown" not in footer or "after local writers" not in footer:
    raise SystemExit("authorityFooter must name surface-visible and post-writer reread")
if "events.subscribe" in footer:
    raise SystemExit("authorityFooter invents events.subscribe")
for sibling, label in (
    ("shell/apps/ultimate-administration/AdministrationModel.js", "Administration"),
    ("shell/apps/ultimate-files/FilesModel.js", "Files"),
):
    sibling_text = (root / sibling).read_text(encoding="utf-8")
    if "not available yet" in sibling_text or "domain yet" in sibling_text:
        raise SystemExit(f"{label} still invents forthcoming writers with not available yet / domain yet")
gaps = (root / "plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md").read_text(encoding="utf-8")
phase5_row = None
for line in gaps.splitlines():
    if "Typed Settings writers remain Phase 5" in line:
        phase5_row = line
        break
if phase5_row is None:
    raise SystemExit("fleet-doctrine-gaps Current position Phase 5 fence row missing")
if "scrubbed" not in phase5_row.lower():
    raise SystemExit("fleet-doctrine-gaps Phase 5 fence row must mark scrubbed in product docs")
if "do-not-reintroduce" not in phase5_row.lower() and "reintroduction" not in phase5_row.lower():
    raise SystemExit("fleet-doctrine-gaps Phase 5 fence row must name remaining invent risk as reintroduction / do-not-reintroduce")
PY
pass "Domain products explain trust, provenance, and unavailable mutation boundaries"
