#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

list_bindings() {
  local home="$1"
  local epilogue="${2:-}"

  seed_chrome_tokens "$home"
  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" OMARCHY_PATH="$ROOT" OMARCHY_BINDING_EPILOGUE="$epilogue" lua <<'LUA'
package.path = os.getenv("HOME") .. "/.config/?.lua;" .. os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local function proxy()
  return setmetatable({}, {
    __index = function(self, key)
      local value = proxy()
      rawset(self, key, value)
      return value
    end,
    __call = function()
      return {}
    end,
  })
end

local bindings = {}

hl = setmetatable({
  dsp = proxy(),
  bind = function(keys, dispatcher, opts)
    opts = opts or {}
    table.insert(bindings, {
      keys = keys,
      description = opts.description or "(no description)",
      release = opts.release == true,
    })
  end,
  config = function() end,
  env = function() end,
  monitor = function() end,
  window_rule = function() end,
  workspace_rule = function() end,
  layer_rule = function() end,
  gesture = function() end,
  animation = function() end,
  curve = function() end,
  exec_cmd = function() end,
  dispatch = function() end,
  on = function() end,
  timer = function() end,
  get_config = function() return nil end,
  get_active_window = function() return nil end,
}, {
  __index = function()
    return function()
      return {}
    end
  end,
})

require("default.hypr.omarchy")

local epilogue = os.getenv("OMARCHY_BINDING_EPILOGUE") or ""
if epilogue ~= "" then
  assert(load(epilogue))()
end

-- X11 keycodes are evdev codes plus 8. Only the rows Omarchy binds by code
-- need naming; anything else keeps its code: form and still compares exactly.
local keycode_keysyms = {
  [10] = "1", [11] = "2", [12] = "3", [13] = "4", [14] = "5",
  [15] = "6", [16] = "7", [17] = "8", [18] = "9", [19] = "0",
  [20] = "MINUS", [21] = "EQUAL",
  [34] = "BRACKETLEFT", [35] = "BRACKETRIGHT",
  [47] = "SEMICOLON", [48] = "APOSTROPHE", [49] = "GRAVE", [51] = "BACKSLASH",
  [59] = "COMMA", [60] = "PERIOD", [61] = "SLASH",
}

local function signature(binding)
  local parts = {}
  for raw in (binding.keys .. "+"):gmatch("([^+]*)%+") do
    local part = raw:match("^%s*(.-)%s*$")
    if part ~= "" then
      table.insert(parts, part)
    end
  end

  local key = table.remove(parts) or ""
  local code = tonumber(key:match("^[Cc][Oo][Dd][Ee]:(%d+)$") or "")
  if code and keycode_keysyms[code] then
    key = keycode_keysyms[code]
  end

  for index, modifier in ipairs(parts) do
    parts[index] = modifier:upper()
  end
  table.sort(parts)
  table.insert(parts, key:upper())

  return table.concat(parts, "+") .. (binding.release and " (release)" or "")
end

for _, binding in ipairs(bindings) do
  print(signature(binding) .. "\t" .. binding.keys .. "\t" .. binding.description)
end
LUA
}

duplicate_signatures() {
  cut -f1 | sort | uniq -d
}

allowed_duplicates=(
  "ALT+SHIFT+TAB"
  "ALT+TAB"
)

is_allowed_duplicate() {
  local signature="$1" allowed

  for allowed in "${allowed_duplicates[@]}"; do
    [[ $signature == "$allowed" ]] && return 0
  done

  return 1
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

SEED_PATH="$PATH"

seed_chrome_tokens() {
  local home="$1"

  PATH="$SEED_PATH" mkdir -p "$home/.local/state/omarchy/current"
  PATH="$SEED_PATH" python3 "$ROOT/default/ultimate/design-system/resolve_tokens.py" \
    --colors "$ROOT/themes/ultimate-dark/colors.toml" \
    --chrome-output "$home/.local/state/omarchy/current/chrome-tokens-v0.json" \
    --output "$home/.local/state/omarchy/current/design-tokens-v0.json" >/dev/null ||
    fail "the test could not seed a resolved chrome token adapter"
}
write_mode() {
  local home="$1"
  local mode="$2"
  mkdir -p "$home/.local/state/omarchy/ultimate"
  printf '%s\n' "$mode" >"$home/.local/state/omarchy/ultimate/mode"
}

home="$tmpdir/home"
stub_bin="$tmpdir/bin"
mkdir -p "$home" "$stub_bin"
touch "$stub_bin/voxtype"
chmod +x "$stub_bin/voxtype"

desktop_home="$tmpdir/desktop-home"
mkdir -p "$desktop_home"
desktop_bindings=$(PATH="$stub_bin:$PATH" list_bindings "$desktop_home")
[[ -n $desktop_bindings ]] || fail "desktop bindings load for the conflict check"
grep -Fq $'SUPER + E	Files' <<<"$desktop_bindings" || fail "desktop conflict check sees Win+E"
grep -Fq $'SUPER + A	Agent' <<<"$desktop_bindings" || fail "desktop conflict check sees Win+A"
grep -Fq $'ALT + TAB	Switch windows' <<<"$desktop_bindings" || fail "desktop conflict check sees Alt+Tab"
desktop_duplicates=$(duplicate_signatures <<<"$desktop_bindings")
while read -r signature; do
  [[ -n $signature ]] || continue
  fail "no two desktop bindings claim the same chord" \
    "$(awk -F'\t' -v signature="$signature" '$1 == signature { print $2 " -> " $3 }' <<<"$desktop_bindings")"
done <<<"$desktop_duplicates"
pass "desktop mode bindings have no colliding chords"

write_mode "$home" "power-user"
bindings=$(PATH="$stub_bin:$PATH" list_bindings "$home")
[[ -n $bindings ]] || fail "default bindings load for the conflict check"

grep -Fq $'SUPER + RETURN\tTerminal' <<<"$bindings" || fail "conflict check sees the essential bindings"
grep -Fq $'SUPER + SHIFT + A\tChatGPT' <<<"$bindings" || fail "conflict check sees the preinstalled bindings"
grep -Fq $'F9\tStart dictation (push-to-talk)' <<<"$bindings" || fail "conflict check sees the Voxtype bindings"
pass "conflict check covers the full default binding set"

duplicates=$(duplicate_signatures <<<"$bindings")

while read -r signature; do
  [[ -n $signature ]] || continue
  is_allowed_duplicate "$signature" && continue
  fail "no two default bindings claim the same chord" \
    "$(awk -F'\t' -v signature="$signature" '$1 == signature { print $2 " -> " $3 }' <<<"$bindings")"
done <<<"$duplicates"
pass "no two default bindings claim the same chord"

for allowed in "${allowed_duplicates[@]}"; do
  grep -Fqx "$allowed" <<<"$duplicates" ||
    fail "every allowed duplicate chord is still stacked on purpose" "$allowed"
done
pass "allowed duplicate chords are still stacked on purpose"

(( $(grep -c $'^F9\t' <<<"$bindings") == 1 )) ||
  fail "press and release bindings on one key do not read as a conflict"
(( $(grep -c $'^F9 (release)\t' <<<"$bindings") == 1 )) ||
  fail "release bindings keep their own signature"
pass "press and release bindings on one key do not read as a conflict"

probe=$(PATH="$stub_bin:$PATH" list_bindings "$home" \
  'o.bind("SUPER + 1", "Conflict probe", "true")' | duplicate_signatures)
grep -Fqx "SUPER+1" <<<"$probe" ||
  fail "the conflict check catches a keysym colliding with a bound keycode"

probe=$(PATH="$stub_bin:$PATH" list_bindings "$home" \
  'o.bind("SUPER + ALT + SHIFT + RIGHT", "Conflict probe", "true")' | duplicate_signatures)
grep -Fqx "ALT+SHIFT+SUPER+RIGHT" <<<"$probe" ||
  fail "the conflict check ignores modifier order"
pass "the conflict check catches collisions across keycodes and modifier order"
