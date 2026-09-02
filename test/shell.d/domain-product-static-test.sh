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
grep -Fq 'Trash write plane exists but is not shell-authorizable' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner states Trash is not shell-authorizable"
grep -Fq 'CHANGES UNAVAILABLE' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner names CHANGES UNAVAILABLE for Trash"
grep -Fq 'Restore, empty Recycle Bin, permanent delete, and files.trash.manage remain unavailable' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner keeps Restore and files.trash.manage unavailable"
grep -Fq 'files.trash.manage remain unavailable' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" || fail "Files mutation-boundary banner does not invent files.trash.manage"
grep -Fq 'readonly property bool trashAuthorized: false' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files pins trashAuthorized false; Trash is not LIVE under the shell principal"
grep -Fq 'readonly property bool createEnabled: createVisible && !operationBusy && host !== null && host.fabricReady' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files keeps New folder createEnabled LIVE"
if grep -Eq 'trashAuthorized:\s*true' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml"; then
  fail "Files must not authorize shell consequential trash"
fi
if grep -Eq 'files-entry-trash.*helper only|The actual blocker is the schema family' "$ROOT/HANDOFF_WRITERS_2026-09-01.md"; then
  fail "HANDOFF_WRITERS must not claim entry.trash is helper-only or schema-blocked after the v1 directory family widen"
fi
grep -Fq 'grant.shell-consequential' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS names the SHELL consequential refuse for entry.trash"
grep -Fq 'files.trash.manage' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS keeps files.trash.manage unavailable"
grep -Fq 'trashAuthorized=false' "$ROOT/HANDOFF_WRITERS_2026-09-01.md" || fail "HANDOFF_WRITERS residual names Files Trash UI gated trashAuthorized=false"
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
pass "Domain products explain trust, provenance, and unavailable mutation boundaries"
