#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const search = requireFromRoot('shell/services/AppSearch.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
const appLibraryQml = fs.readFileSync(path.join(root, 'shell/services/AppLibrary.qml'), 'utf8')

const entries = [
  {
    name: 'Google Contacts',
    genericName: 'Address Book',
    comment: 'Manage contacts',
    keywords: ['contacts', 'address book', 'people'],
    id: 'google-contacts.desktop'
  },
  {
    name: 'Calculator',
    genericName: 'Calculator',
    comment: 'Perform arithmetic, scientific or financial calculations',
    keywords: ['calculation', 'arithmetic', 'scientific', 'financial'],
    id: 'org.gnome.Calculator.desktop'
  },
  {
    name: 'OBS Studio',
    genericName: 'Streaming/Recording Software',
    comment: 'Free and Open Source Streaming/Recording Software',
    keywords: ['streaming', 'recording', 'capture'],
    id: 'com.obsproject.Studio.desktop'
  },
  {
    name: 'Aether',
    genericName: '',
    comment: 'Minimal internet radio player',
    keywords: ['audio', 'music', 'radio'],
    id: 'io.github.taqi.aether.desktop'
  },
  {
    name: 'Xournal++',
    genericName: 'Notetaking',
    comment: 'Take handwritten notes',
    keywords: ['notes', 'pdf', 'annotation'],
    id: 'com.github.xournalpp.xournalpp.desktop'
  },
  {
    name: 'RustDesk',
    genericName: 'Remote Desktop',
    comment: 'Remote desktop control',
    keywords: ['remote', 'desktop', 'control'],
    id: 'com.rustdesk.RustDesk.desktop'
  }
]

const contactMatches = search.sortedEntries(entries, 'contact').map(row => search.entryName(row.entry))
assertDeepEqual(contactMatches, ['Google Contacts'], 'contact search only returns direct contact matches')

assert(
  search.fuzzyScore(entries[1], 'contact') < 0,
  'calculator does not match contact as a loose subsequence'
)

const acronymMatches = search.sortedEntries(entries, 'gc').map(row => search.entryName(row.entry))
assertEqual(acronymMatches[0], 'Google Contacts', 'short acronym matching still works')

const directMatches = search.sortedEntries(entries, 'obs').map(row => search.entryName(row.entry))
assertEqual(directMatches[0], 'OBS Studio', 'direct app-name matching still works')

const foot = {
  name: 'Foot',
  genericName: 'Terminal',
  id: 'foot',
  categories: 'System;TerminalEmulator;',
  icon: 'foot'
}
const chromium = {
  name: 'Chromium',
  genericName: 'Web Browser',
  id: 'chromium',
  categories: 'Network;WebBrowser;',
  icon: 'chromium'
}
assert(search.isDeveloperTool(foot), 'foot is a developer tool')
assert(!search.isDeveloperTool(chromium), 'chromium is a consumer app')
const idle = search.visibleEntries(
  search.sortedEntries([foot, chromium], '', function() { return false }),
  '',
  true
).map(entry => search.entryName(entry))
assertDeepEqual(idle, ['Chromium'], 'idle Start hides terminal emulators and keeps the browser')
const searched = search.visibleEntries(
  search.sortedEntries([foot, chromium], 'foot', function() { return false }),
  'foot',
  true
).map(entry => search.entryName(entry))
assertDeepEqual(searched, ['Foot'], 'search still finds Foot')
assertEqual(search.unwrapEntry({ entry: foot, score: 1 }), foot, 'unwrapEntry reads the desktop entry off a sort row')
assertDeepEqual(search.withRecent(['vim'], 'Chrome.desktop'), ['chrome', 'vim'], 'Start recents put the launched id first')
assertDeepEqual(search.withRecent(['chrome', 'files'], 'chrome'), ['chrome', 'files'], 'Start recents do not duplicate a launch')
assertEqual(search.withRecent(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'], 'i').length, 8, 'Start recents stay bounded')
assertDeepEqual(search.parseRecents(search.serializeRecents(['chrome'])), ['chrome'], 'Start recents round-trip')
const grouped = search.programRows([
  { id: '1password', name: '1Password' },
  { id: 'aether', name: 'Aether' },
  { id: 'basecamp', name: 'Basecamp' }
], '')
assertEqual(grouped[0].kind, 'letter', 'All programs inserts a letter row')
assertEqual(grouped[0].letter, '#', 'names that are not A-Z share one bucket')
assertEqual(grouped[1].kind, 'app', 'the app follows its letter')
assertEqual(grouped[2].letter, 'A', 'Aether opens the A bucket')
assertEqual(search.programRows([{ id: 'aether', name: 'Aether' }], 'ae')[0].kind, 'app', 'search results stay a flat list')
assertEqual(search.recentEntries(['chromium', 'missing'], [chromium, foot], 6, []).map(e => e.id).join(','), 'chromium', 'recents resolve live desktop entries only')
assertEqual(search.recentEntries(['chromium'], [chromium], 6, ['chromium']).length, 0, 'recents do not repeat a pinned app')

assertEqual(search.searchDestinations('', []).length, 0, 'idle Start does not inject destinations')
const destApps = [
  { id: 'org.omarchy.Settings', name: 'Settings' },
  { id: 'org.omarchy.Files', name: 'Files' },
  { id: 'org.omarchy.AgentCenter', name: 'Agent Center' }
]
const dispDest = search.searchDestinations('disp', destApps).map(row => row.name)
assert(dispDest.indexOf('Display') >= 0, 'disp search includes Settings Display')
assert(dispDest.indexOf('Accessibility') < 0, 'disp search does not invent Accessibility')
const personDest = search.sortedEntries(destApps.concat(search.searchDestinations('person', destApps)), 'person')
assertEqual(search.entryName(personDest[0].entry), 'Personalization', 'person ranks Personalization first')
assertEqual(personDest[0].entry.actionId, 'Personalization', 'Personalization uses the Settings jump action')
const pictDest = search.sortedEntries(destApps.concat(search.searchDestinations('pict', destApps)), 'pict')
assertEqual(search.entryName(pictDest[0].entry), 'Pictures', 'pict ranks Pictures first')
assertEqual(pictDest[0].entry.actionId, 'Pictures', 'Pictures uses the Files jump action')
const computerDest = search.sortedEntries(destApps.concat(search.searchDestinations('this pc', destApps)), 'this pc')
assertEqual(search.entryName(computerDest[0].entry), 'Computer', 'this pc ranks Computer / This PC')
assertEqual(computerDest[0].entry.actionId, 'ThisPC', 'Computer uses the Files This PC action')
const destNames = search.START_DESTINATIONS.map(row => row.name)
assert(destNames.indexOf('Display') >= 0, 'destinations include Display')
assert(destNames.indexOf('Sound') >= 0, 'destinations include Sound')
assert(destNames.indexOf('Network & Internet') >= 0, 'destinations include Network')
assert(destNames.indexOf('Bluetooth & devices') >= 0, 'destinations include Bluetooth')
assert(destNames.indexOf('Power & battery') >= 0, 'destinations include Power')
assert(destNames.indexOf('Personalization') >= 0, 'destinations include Personalization')
assert(destNames.indexOf('Apps') >= 0, 'destinations include Apps')
assert(destNames.indexOf('Update') >= 0, 'destinations include Update')
assert(destNames.indexOf('Recovery') >= 0, 'destinations include Recovery')
assert(destNames.indexOf('Input') >= 0, 'destinations include Input')
assert(destNames.indexOf('Pictures') >= 0, 'destinations include Pictures')
assert(destNames.indexOf('Computer') >= 0, 'destinations include Computer')
assert(destNames.indexOf('Accessibility') < 0, 'destinations do not invent Accessibility')
const appsDest = search.sortedEntries(destApps.concat(search.searchDestinations('default', destApps)), 'default')
assertEqual(search.entryName(appsDest[0].entry), 'Apps', 'default ranks Settings Apps / Default Programs')
assertEqual(appsDest[0].entry.actionId, 'Apps', 'Apps uses the Settings jump action')
const updateDest = search.sortedEntries(destApps.concat(search.searchDestinations('update', destApps)), 'update')
assertEqual(search.entryName(updateDest[0].entry), 'Update', 'update ranks Settings Update')
assertEqual(updateDest[0].entry.actionId, 'Update', 'Update uses the Settings jump action')
const soundDest = search.sortedEntries(destApps.concat(search.searchDestinations('sound', destApps)), 'sound')
assertEqual(search.entryName(soundDest[0].entry), 'Sound', 'sound ranks Settings Sound')
assertEqual(soundDest[0].entry.actionId, 'Sound', 'Sound uses the Settings jump action')
const skipped = search.searchDestinations('files', destApps).map(row => row.name)
assert(skipped.indexOf('Files') < 0, 'Files destination is not duplicated when the app exists')
assert(search.searchDestinations('files', []).some(row => row.name === 'Files'), 'Files destination exists when the app is absent')
assert(
  !search.START_DESTINATIONS.some(row => /content|full.?text|file.?search/i.test(JSON.stringify(row))),
  'destinations are launch paths, not file-content search'
)

// The menu's Apps submenu is the launcher now: app rows launch and uninstall
// through the shared app library instead of running commands themselves.
const activateMatch = menuQml.match(/function activateIndex\(index, fromPointer\) \{([\s\S]*?)\n  \}/)
assert(activateMatch, 'menu activateIndex function exists')
assert(
  activateMatch[1].includes('root.appLibrary.launch('),
  'menu routes app launch through the shared app library'
)
assert(
  !activateMatch[1].includes('entry.execute()'),
  'menu does not execute desktop entries directly'
)

const confirmDeleteMatch = menuQml.match(/function confirmDelete\(\) \{([\s\S]*?)\n  \}/)
assert(confirmDeleteMatch, 'menu confirmDelete function exists')
assert(
  confirmDeleteMatch[1].includes('root.appLibrary.remove('),
  'menu delete routes through the shared app library'
)
assert(
  confirmDeleteMatch[1].includes('root.cancel()'),
  'menu delete closes the menu after confirmation'
)

assert(
  /function remove\(desktopId, name\) \{[\s\S]*?omarchy-remove-launcher-entry[\s\S]*?\n  \}/.test(appLibraryQml),
  'app library remove runs the remover through the shell'
)

assert(
  /function launch\(desktopId, name\) \{[\s\S]*?uwsm-app[\s\S]*?\n  \}/.test(appLibraryQml) &&
    appLibraryQml.includes('Util.execDetached("uwsm-app -- gtk-launch "') &&
    appLibraryQml.includes('JumpList.actionCommand(root.entryByDesktopId(id))') &&
    appLibraryQml.includes('root.launchCommand(command)') &&
    appLibraryQml.includes('root.recordLaunch(id)'),
  'app library launches omarchy-* Exec through OMARCHY_PATH and other entries through gtk-launch'
)

assert(
  /function launchAction\([\s\S]*?uwsm-app -- /.test(appLibraryQml) &&
    appLibraryQml.includes('function launchCommand(command)') &&
    appLibraryQml.includes('root.omarchyPath + "/bin/" + bin') &&
    appLibraryQml.includes('.replace(/\\s+%[A-Za-z@]/g, "")'),
  'app library runs desktop Actions through uwsm and resolves omarchy-* from OMARCHY_PATH'
)

assert(
  appLibraryQml.includes('Util.shellQuote(id + ".desktop")'),
  'app library launches by full file name so ids ending in .desktop (org.telegram.desktop) resolve'
)

assert(
  /function iconIndexScanCommand\(\)[\s\S]*-path "\*\/apps\/\*" -o -path "\*\/devices\/\*"/.test(appLibraryQml),
  'app library fallback icon index includes device icons'
)

assert(
  appLibraryQml.includes('command: ["bash", "-c", root.hiddenEntryScanCommand()]') &&
    appLibraryQml.includes('command: ["bash", "-c", root.iconIndexScanCommand()]') &&
    !appLibraryQml.includes('"-lc"'),
  'app library scans avoid login shells whose profile activation retriggers the desktop-entry watcher'
)

assert(
  /if \(active === "apps"\) \{[\s\S]*?rows\.sort\(function\(a, b\)/.test(menuQml),
  'apps menu enforces alphabetical display order after provider refreshes'
)

const iconSourceMatch = appLibraryQml.match(/function iconSource\(icon\) \{([\s\S]*?)\n  \}/)
assert(iconSourceMatch, 'app library iconSource function exists')
assert(
  iconSourceMatch[1].indexOf('root.iconIndex[value]') < iconSourceMatch[1].indexOf('Quickshell.iconPath(value, true)'),
  'app library prefers indexed app icons over ambiguous themed icons'
)

const beginLaunchMatch = appLibraryQml.match(/function beginLaunchFeedback\(name\) \{([\s\S]*?)\n  \}/)
assert(beginLaunchMatch, 'app library beginLaunchFeedback function exists')
assert(
  !beginLaunchMatch[1].includes('root.launchOsdOpen = false'),
  'app library keeps owning an OSD a previous launch left on screen'
)

const openMatch = menuQml.match(/function openExistingMenu\(initialMenu\) \{([\s\S]*?)\n  \}/)
assert(openMatch, 'menu openExistingMenu function exists')
assert(
  openMatch[1].includes('root.appLibrary.refreshIcons()'),
  'menu refreshes the shared icon index when opened'
)
JS
