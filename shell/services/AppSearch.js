var DEVELOPER_TOOL_IDS = {
  "alacritty": true,
  "cmake-gui": true,
  "docker": true,
  "emacs": true,
  "emacsclient": true,
  "foot": true,
  "foot-server": true,
  "footclient": true,
  "gvim": true,
  "helix": true,
  "kitty": true,
  "nano": true,
  "neovim": true,
  "nvim": true,
  "org.freedesktop.xwayland": true,
  "org.gnupg.pinentry-qt": true,
  "org.wezfurlong.wezterm": true,
  "vim": true,
  "wezterm": true
}

function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function unwrapEntry(row) {
  if (row && row.entry) return row.entry
  return row
}

function normalizeEntryId(entry) {
  var id = String((entry && entry.id) || "").trim().toLowerCase()
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

function entryCategories(entry) {
  var cats = entry && entry.categories
  var list = []
  var i
  if (typeof cats === "string") list = cats.split(";")
  else if (cats && typeof cats.length === "number") {
    for (i = 0; i < cats.length; i++) list.push(String(cats[i]))
  }
  return list
}

function isDeveloperTool(entry) {
  if (!entry) return false
  if (DEVELOPER_TOOL_IDS[normalizeEntryId(entry)]) return true
  var generic = String((entry && entry.genericName) || "").toLowerCase()
  if (generic === "terminal" || generic === "terminal emulator") return true
  var cats = entryCategories(entry)
  var i
  for (i = 0; i < cats.length; i++) {
    if (String(cats[i]).replace(/\s+/g, "").toLowerCase() === "terminalemulator") return true
  }
  return false
}

function letterOf(name) {
  var ch = String(name || "").charAt(0).toUpperCase()
  if (ch >= "A" && ch <= "Z") return ch
  return "#"
}

function parseRecents(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    if (parsed && Array.isArray(parsed.ids)) {
      var ids = []
      var i
      for (i = 0; i < parsed.ids.length; i++) {
        var id = normalizeEntryId({ id: parsed.ids[i] })
        if (id) ids.push(id)
      }
      return ids
    }
  } catch (e) {
  }
  return []
}

function serializeRecents(ids) {
  return JSON.stringify({ ids: ids || [] }, null, 2) + "\n"
}

function withRecent(ids, desktopId) {
  var id = normalizeEntryId({ id: desktopId })
  if (!id) return ids || []
  var next = [id]
  var i
  for (i = 0; i < (ids || []).length; i++) {
    if (normalizeEntryId({ id: ids[i] }) !== id) next.push(String(ids[i]))
  }
  return next.slice(0, 8)
}

function recentEntries(ids, values, limit, excludeIds) {
  var cap = Number(limit) > 0 ? Number(limit) : 8
  var skip = ({})
  var byId = ({})
  var i
  for (i = 0; i < (excludeIds || []).length; i++)
    skip[normalizeEntryId({ id: excludeIds[i] })] = true
  for (i = 0; i < (values || []).length; i++) {
    var entry = unwrapEntry(values[i])
    var nid = normalizeEntryId(entry)
    if (nid && !byId[nid]) byId[nid] = entry
  }
  var out = []
  for (i = 0; i < (ids || []).length && out.length < cap; i++) {
    var id = normalizeEntryId({ id: ids[i] })
    if (!id || skip[id] || !byId[id]) continue
    out.push(byId[id])
  }
  return out
}

// Closed Start search destinations: existing Settings pages and Start places.
// Not file-content search. Accessibility is not invented here.
var START_DESTINATIONS = [
  {
    id: "omarchy.start.display",
    name: "Display",
    genericName: "Settings",
    comment: "Open Settings Display",
    keywords: ["display", "monitor", "resolution", "settings"],
    icon: "org.omarchy.Settings",
    desktopId: "org.omarchy.Settings",
    actionId: "Display"
  },
  {
    id: "omarchy.start.sound",
    name: "Sound",
    genericName: "Settings",
    comment: "Open Settings Sound",
    keywords: ["sound", "audio", "volume", "settings"],
    icon: "org.omarchy.Settings",
    desktopId: "org.omarchy.Settings",
    command: "omarchy-launch-settings --source desktop settings.audio.overview"
  },
  {
    id: "omarchy.start.network",
    name: "Network & Internet",
    genericName: "Settings",
    comment: "Open Settings Network",
    keywords: ["network", "internet", "wifi", "ethernet", "settings"],
    icon: "org.omarchy.Settings",
    desktopId: "org.omarchy.Settings",
    actionId: "Network"
  },
  {
    id: "omarchy.start.bluetooth",
    name: "Bluetooth & devices",
    genericName: "Settings",
    comment: "Open Settings Bluetooth",
    keywords: ["bluetooth", "devices", "settings"],
    icon: "org.omarchy.Settings",
    desktopId: "org.omarchy.Settings",
    command: "omarchy-launch-settings --source desktop settings.bluetooth.overview"
  },
  {
    id: "omarchy.start.power",
    name: "Power & battery",
    genericName: "Settings",
    comment: "Open Settings Power",
    keywords: ["power", "battery", "settings"],
    icon: "org.omarchy.Settings",
    desktopId: "org.omarchy.Settings",
    command: "omarchy-launch-settings --source desktop settings.power.overview"
  },
  {
    id: "omarchy.start.personalization",
    name: "Personalization",
    genericName: "Settings",
    comment: "Open Settings Personalization",
    keywords: ["personalization", "theme", "wallpaper", "background", "settings"],
    icon: "org.omarchy.Settings",
    desktopId: "org.omarchy.Settings",
    actionId: "Personalization"
  },
  {
    id: "omarchy.start.files",
    name: "Files",
    genericName: "File Manager",
    comment: "Open Files",
    keywords: ["files", "folders", "explorer"],
    icon: "system-file-manager",
    desktopId: "org.omarchy.Files"
  },
  {
    id: "omarchy.start.pictures",
    name: "Pictures",
    genericName: "Files",
    comment: "Open Pictures",
    keywords: ["pictures", "photos", "images"],
    icon: "folder-pictures",
    desktopId: "org.omarchy.Files",
    actionId: "Pictures"
  },
  {
    id: "omarchy.start.computer",
    name: "Computer",
    genericName: "This PC",
    comment: "Open This PC",
    keywords: ["computer", "this pc", "thispc"],
    icon: "computer",
    desktopId: "org.omarchy.Files",
    actionId: "ThisPC"
  },
  {
    id: "omarchy.start.settings",
    name: "Settings",
    genericName: "System Settings",
    comment: "Open Settings",
    keywords: ["settings"],
    icon: "org.omarchy.Settings",
    desktopId: "org.omarchy.Settings"
  },
  {
    id: "omarchy.start.agent-center",
    name: "Agent Center",
    genericName: "Agents",
    comment: "Open Agent Center",
    keywords: ["agent", "agents", "agent center"],
    icon: "org.omarchy.AgentCenter",
    desktopId: "org.omarchy.AgentCenter"
  }
]

function destinationEntry(spec) {
  return {
    id: spec.id,
    name: spec.name,
    genericName: spec.genericName || "",
    comment: spec.comment || "",
    keywords: spec.keywords || [],
    icon: spec.icon || "",
    desktopId: spec.desktopId,
    actionId: spec.actionId || "",
    command: spec.command || "",
    kind: "destination"
  }
}

function searchDestinations(query, values) {
  if (!String(query || "").trim()) return []
  var haveApp = ({})
  var i
  for (i = 0; i < (values || []).length; i++) {
    var entry = unwrapEntry(values[i])
    if (!entry || entry.noDisplay) continue
    var nid = normalizeEntryId(entry)
    if (nid) haveApp[nid] = true
  }
  var out = []
  for (i = 0; i < START_DESTINATIONS.length; i++) {
    var spec = START_DESTINATIONS[i]
    var coversApp = !spec.actionId && !spec.command
    if (coversApp && haveApp[normalizeEntryId({ id: spec.desktopId })]) continue
    out.push(destinationEntry(spec))
  }
  return out
}

function programRows(entries, query) {
  var rows = []
  var searching = String(query || "").trim().length > 0
  var last = ""
  var i
  for (i = 0; i < (entries || []).length; i++) {
    var entry = unwrapEntry(entries[i])
    if (!entry) continue
    if (!searching) {
      var letter = letterOf(entryName(entry))
      if (letter !== last) {
        rows.push({ kind: "letter", letter: letter })
        last = letter
      }
    }
    rows.push({ kind: "app", entry: entry })
  }
  return rows
}

function visibleEntries(rows, query, hideDeveloperTools) {
  var hide = !!hideDeveloperTools && String(query || "").trim().length === 0
  var out = []
  var i
  for (i = 0; i < (rows || []).length; i++) {
    var entry = unwrapEntry(rows[i])
    if (hide && isDeveloperTool(entry)) continue
    if (entry) out.push(entry)
  }
  return out
}

function entrySubtext(entry) {
  return String((entry && entry.genericName) || "")
}

function entrySortKey(entry) {
  return entryName(entry).toLowerCase()
}

function keywordText(entry) {
  try {
    if (entry && entry.keywords && typeof entry.keywords.join === "function") return entry.keywords.join(" ")
  } catch (e) {
  }
  return ""
}

function entrySearchText(entry) {
  if (!entry) return ""
  return [entry.name, entry.genericName, entry.comment, keywordText(entry), entry.id].join(" ").toLowerCase()
}

function wordText(value) {
  return String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
}

function words(value) {
  var values = wordText(value).split(/[^a-z0-9]+/)
  var result = []
  for (var i = 0; i < values.length; i++) {
    if (values[i]) result.push(values[i])
  }
  return result
}

function entryAcronym(entry) {
  var values = words([entry && entry.name, entry && entry.genericName, keywordText(entry), entry && entry.id].join(" "))
  var result = ""
  for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
  return result
}

function termMatches(entry, term) {
  if (!term) return true

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)

  if (name.indexOf(term) >= 0) return true
  if (id.indexOf(term) >= 0) return true
  if (haystack.indexOf(term) >= 0) return true

  return term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0
}

function allTermsMatch(entry, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termMatches(entry, terms[i])) return false
  }
  return true
}

function fuzzyScore(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0
  if (!allTermsMatch(entry, q)) return -1

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  if (directName === 0) return 10000 - name.length
  if (directId === 0) return 9500 - id.length
  if (directName > 0) return 8000 - directName * 10 - name.length
  if (directId > 0) return 7600 - directId * 10 - id.length

  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return 6000 - hayIndex

  var acronym = entryAcronym(entry)
  var acronymIndex = acronym.indexOf(q)
  if (acronymIndex === 0) return 5000 - acronym.length
  if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length

  return 4000 - name.length
}

function sortedEntries(values, query, hiddenCallback) {
  var q = String(query || "").trim()
  var rows = []

  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || entry.noDisplay) continue
    if (hiddenCallback && hiddenCallback(entry)) continue
    var name = entryName(entry)
    if (!name) continue
    var score = fuzzyScore(entry, q)
    if (score < 0) continue
    rows.push({ entry: entry, score: score, key: entrySortKey(entry), name: name.toLowerCase() })
  }

  rows.sort(function(a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.key < b.key) return -1
    if (a.key > b.key) return 1
    if (a.name < b.name) return -1
    if (a.name > b.name) return 1
    return 0
  })

  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    entryName: entryName,
    entrySubtext: entrySubtext,
    entrySortKey: entrySortKey,
    entrySearchText: entrySearchText,
    entryAcronym: entryAcronym,
    fuzzyScore: fuzzyScore,
    sortedEntries: sortedEntries,
    unwrapEntry: unwrapEntry,
    isDeveloperTool: isDeveloperTool,
    visibleEntries: visibleEntries,
    letterOf: letterOf,
    parseRecents: parseRecents,
    serializeRecents: serializeRecents,
    withRecent: withRecent,
    recentEntries: recentEntries,
    programRows: programRows,
    searchDestinations: searchDestinations,
    START_DESTINATIONS: START_DESTINATIONS
  }
}
