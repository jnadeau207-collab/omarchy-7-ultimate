#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

read_limits() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-claude" PAYLOAD="$1" python3 - <<'PY'
import importlib.machinery, importlib.util, io, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

collector.urllib.request.urlopen = lambda request, timeout=None: io.BytesIO(os.environ["PAYLOAD"].encode())

print(json.dumps(collector.probe_limits("token")))
PY
}

limits=$(read_limits '{
  "five_hour": { "utilization": 78.0 },
  "seven_day": { "utilization": 12.0 },
  "seven_day_opus": null,
  "limits": [
    { "kind": "session", "percent": 78, "scope": null },
    { "kind": "weekly_all", "percent": 12, "scope": null },
    { "kind": "weekly_scoped", "percent": 17, "resets_at": "2026-08-15T03:00:00+00:00",
      "scope": { "model": { "id": "claude-fable-5", "display_name": "Fable" }, "surface": null } },
    { "kind": "weekly_scoped", "percent": 99, "scope": { "model": { "display_name": "Fable" } } },
    { "kind": "five_hour_scoped", "percent": 95, "scope": { "model": { "display_name": "Fable" } } },
    { "kind": "weekly_scoped", "percent": 42, "scope": { "model": { "id": "claude-opus-5", "display_name": null } } },
    { "kind": "weekly_scoped", "percent": 5, "scope": { "model": { "display_name": "  " } } },
    { "kind": "weekly_scoped", "percent": "unknown", "scope": { "model": { "display_name": "Opus" } } }
  ]
}')

expected='[{"label":"Session (5-hour)","percent":0.78,"resetsAt":""},{"label":"Weekly (7-day)","percent":0.12,"resetsAt":""},{"label":"Fable Weekly","title":"Fable Weekly","percent":0.17,"resetsAt":"2026-08-15T03:00:00+00:00"},{"label":"Fable Session","title":"Fable Session","percent":0.95,"resetsAt":""},{"label":"claude-opus-5 Weekly","title":"claude-opus-5 Weekly","percent":0.42,"resetsAt":""}]'
[[ $(jq -c '.limits' <<<"$limits") == "$expected" ]] ||
  fail "Claude collector reads every model-scoped window once and drops unusable entries" "$limits"
pass "Claude collector reads every model-scoped window once and drops unusable entries"

fractions=$(read_limits '{
  "five_hour": { "utilization": 0.78 },
  "limits": [
    { "kind": "session", "percent": 0.78, "scope": null },
    { "kind": "weekly_scoped", "percent": 0.42, "scope": { "model": { "display_name": "Fable" } } }
  ]
}')

[[ $(jq -c '[.limits[].percent]' <<<"$fractions") == "[0.78,0.42]" ]] ||
  fail "Claude collector reads scoped percentages on the payload's own scale" "$fractions"
pass "Claude collector reads scoped percentages on the payload's own scale"

for payload in '{"five_hour":{"utilization":78.0},"limits":[{"kind":"session","percent":78,"scope":null}]}' \
  '{"five_hour":{"utilization":78.0},"seven_day":{"utilization":12.0}}'; do
  [[ $(jq -c '[.limits[].label]' <<<"$(read_limits "$payload")") != *" Weekly"* ]] ||
    fail "Claude collector adds no limit when the payload scopes none" "$payload"
done
pass "Claude collector adds no limit when the payload scopes none"

CACHE_HOME=$(mktemp -d)
trap 'rm -rf "$CACHE_HOME"' EXIT

collect_limits() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-claude" TOKEN="$1" EXPIRES_AT="$2" CACHED="$3" \
    XDG_CACHE_HOME="$CACHE_HOME" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os, pathlib

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

cache = collector.cache_root() / "claude-limits.json"
cached = os.environ["CACHED"]
if cached:
  cache.write_text(cached, encoding="utf-8")
elif cache.exists():
  cache.unlink()

def unreachable(request, timeout=None):
  raise OSError("no route to host")

collector.urllib.request.urlopen = unreachable
print(json.dumps(collector.collect_limits(os.environ["TOKEN"], int(os.environ["EXPIRES_AT"]), False)))
PY
}

open_at=$(python3 -c 'import datetime as dt; print((dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=3)).isoformat())')
past_at=$(python3 -c 'import datetime as dt; print((dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=3)).isoformat())')
cache=$(jq -nc --arg open "$open_at" --arg past "$past_at" '{
  fetchedAtMs: 1,
  limits: [
    { label: "Session (5-hour)", percent: 0.31, resetsAt: $past },
    { label: "Weekly (7-day)", percent: 0.11, resetsAt: $open }
  ]
}')

expired=$(collect_limits "token" 1000 "$cache")
[[ $(jq -r '.usageStatusText' <<<"$expired") == "Sign-in expired" ]] ||
  fail "Claude collector reports an expired sign-in" "$expired"
[[ $(jq -r '.authHelpText' <<<"$expired") == *"claude auth login"* ]] ||
  fail "Claude collector says how to refresh an expired sign-in" "$expired"
pass "Claude collector reports an expired sign-in instead of hiding the section"

[[ $(jq -c '[.limits[].label]' <<<"$expired") == '["Weekly (7-day)"]' ]] ||
  fail "Claude collector keeps only cached windows that have not reset" "$expired"
pass "Claude collector keeps only cached windows that have not reset"

stale=$(collect_limits "token" 1000 "$(jq -c '.limits |= [.[0]]' <<<"$cache")")
[[ $(jq -c '.limits' <<<"$stale") == "[]" && $(jq -r '.usageStatusText' <<<"$stale") == "Sign-in expired" ]] ||
  fail "Claude collector drops a wholly reset cache but keeps explaining itself" "$stale"
[[ $(jq -r '.authHelpText' <<<"$stale") != *"last known"* ]] ||
  fail "Claude collector promises no last-known limits when it has none" "$stale"
pass "Claude collector drops a wholly reset cache but keeps explaining itself"

signed_out=$(collect_limits "" 0 "$cache")
[[ $(jq -r '.usageStatusText' <<<"$signed_out") == "Waiting for auth" ]] ||
  fail "Claude collector still reports a missing token" "$signed_out"
[[ $(jq -c '[.limits[].label]' <<<"$signed_out") == '["Weekly (7-day)"]' ]] ||
  fail "Claude collector serves open cached windows without a token" "$signed_out"
pass "Claude collector serves open cached windows without a token"

unreachable=$(collect_limits "token" 0 "$cache")
[[ $(jq -c '[.limits[].label]' <<<"$unreachable") == '["Weekly (7-day)"]' ]] ||
  fail "Claude collector falls back to cache when the probe cannot connect" "$unreachable"
[[ $(jq -r '.retryAdvised' <<<"$unreachable") == "true" ]] ||
  fail "Claude collector advises a retry after a transport failure" "$unreachable"
pass "Claude collector falls back to cache when the probe cannot connect"

probe_with_cache() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-claude" FORCE="$1" CACHED="$2" PAYLOAD="$3" \
    XDG_CACHE_HOME="$CACHE_HOME" python3 - <<'PY'
import importlib.machinery, importlib.util, io, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

cache = collector.cache_root() / "claude-limits.json"
cache.write_text(os.environ["CACHED"], encoding="utf-8")

probes = []

def urlopen(request, timeout=None):
  probes.append(1)
  return io.BytesIO(os.environ["PAYLOAD"].encode())

collector.urllib.request.urlopen = urlopen
result = collector.collect_limits("token", 0, os.environ["FORCE"] == "true")
print(json.dumps({
  "result": result,
  "probes": len(probes),
  "cached": json.loads(cache.read_text(encoding="utf-8")),
}))
PY
}

fresh=$(jq -nc --arg open "$open_at" --argjson now "$(python3 -c 'import time; print(round(time.time() * 1000))')" '{
  fetchedAtMs: $now,
  limits: [{ label: "Weekly (7-day)", percent: 0.11, resetsAt: $open }]
}')
payload='{"five_hour":{"utilization":44.0}}'

reused=$(probe_with_cache false "$fresh" "$payload")
[[ $(jq -r '.probes' <<<"$reused") == "0" && $(jq -c '[.result.limits[].percent]' <<<"$reused") == "[0.11]" ]] ||
  fail "Claude collector reuses a cache younger than the probe interval" "$reused"
pass "Claude collector reuses a cache younger than the probe interval"

forced=$(probe_with_cache true "$fresh" "$payload")
[[ $(jq -r '.probes' <<<"$forced") == "1" ]] ||
  fail "Claude collector re-probes on --force despite a fresh cache" "$forced"
[[ $(jq -c '[.result.limits[].percent]' <<<"$forced") == "[0.44]" ]] ||
  fail "Claude collector returns the forced probe's numbers" "$forced"
pass "Claude collector re-probes on --force despite a fresh cache"

[[ $(jq -c '[.cached.limits[].percent]' <<<"$forced") == "[0.44]" ]] ||
  fail "Claude collector caches a successful probe" "$forced"
pass "Claude collector caches a successful probe"

run_node_test <<'JS'
const fs = require('fs')
const source = fs.readFileSync(root + '/shell/plugins/agents/Panel.qml', 'utf8')
const start = source.indexOf('function windowIsLong')
const end = source.indexOf('// The window that decides')
assert(start > 0 && end > start, 'agents panel exposes its limit-window helpers')
eval(source.slice(start, end))

assertDeepEqual(
  limitWindows({ limits: [
    { label: 'Session (5-hour)', percent: 0.78, resetsAt: '' },
    { label: 'Opus 5 (1M context) Weekly', title: 'Opus 5 (1M context) Weekly', percent: 0.42, resetsAt: '' }
  ] }),
  [
    { title: 'Session', percent: 0.78, resetAt: '' },
    { title: 'Opus 5 (1M context) Weekly', percent: 0.42, resetAt: '' }
  ],
  'agents panel titles a limit off the collector when it states one'
)

assertDeepEqual(
  limitWindows({ limits: [{ label: 'Weekly (7-day)', percent: 0.12, resetsAt: '' }] }),
  [{ title: 'Weekly', percent: 0.12, resetAt: '' }],
  'agents panel still reads a window out of a label that carries no title'
)
JS
