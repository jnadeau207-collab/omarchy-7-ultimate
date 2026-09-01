import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.audio"
  ipcTarget: "omarchy.audio"
  property bool chromeVisible: true
  property Item hostAnchor: null
  property bool embedMode: false

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activeMediaPlayer: mediaService ? mediaService.activePlayer : null

  readonly property var candidateSinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream) list.push(n)
    }
    return list
  }

  readonly property var candidateSources: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && !n.isSink && !n.isStream && isAudioSource(n)) {
        var name = n.name || ""
        if (name === "quickshell") continue
        list.push(n)
      }
    }
    return list
  }

  readonly property var candidateStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !isPlaybackStream(n)) continue
      if (String(n.name || "").indexOf("omarchy_speaker_tuning") === 0) continue
      list.push(n)
    }
    return list
  }

  property var sinkAvailability: ({})
  property bool sinkAvailabilityLoaded: false

  function isPlaybackStream(node) {
    return Model.isPlaybackStream(node)
  }

  function isAudioSource(node) {
    return Model.isAudioSource(node)
  }

  property var cachedAudioSinks: []
  property var cachedAudioSources: []

  readonly property var rawAudioSinks: {
    var list = []
    for (var i = 0; i < candidateSinks.length; i++)
      if (sinkAvailable(candidateSinks[i])) list.push(candidateSinks[i])
    if (sink && list.indexOf(sink) < 0) list.unshift(sink)
    return list
  }

  readonly property var rawAudioSources: {
    var list = candidateSources.slice()
    if (source && list.indexOf(source) < 0) list.unshift(source)
    return list
  }

  readonly property var audioSinks: rawAudioSinks.length > 0 ? rawAudioSinks : cachedAudioSinks
  readonly property var audioSources: rawAudioSources.length > 0 ? rawAudioSources : cachedAudioSources

  readonly property var audioStreams: {
    var list = []
    for (var i = 0; i < candidateStreams.length; i++)
      if (candidateStreams[i].audio) list.push(candidateStreams[i])
    return list
  }

  property var displayAudioSinks: []
  property var displayAudioSources: []
  property var displayAudioStreams: []

  property string volumeSinkName: ""

  property real wheelAccumulator: 0

  readonly property var volumeSink: {
    if (volumeSinkName === "" || !sink) return sink
    if (volumeSinkName === String(sink.name)) return sink
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && String(n.name) === volumeSinkName && n.audio)
        return n
    }
    return sink
  }

  onSinkChanged: resolveVolumeSink()

  function resolveVolumeSink() {
    if (!volumeSinkProc.running) volumeSinkProc.running = true
  }

  readonly property real outputVolume: volumeSink && volumeSink.audio ? volumeSink.audio.volume : 0
  readonly property bool outputMuted: volumeSink && volumeSink.audio ? volumeSink.audio.muted : false
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false

  onRawAudioSinksChanged: if (rawAudioSinks.length > 0) cachedAudioSinks = rawAudioSinks
  onRawAudioSourcesChanged: if (rawAudioSources.length > 0) cachedAudioSources = rawAudioSources

  property string focusSection: "output"
  property int selectedIndex: -1
  property bool cursorActive: false

  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  readonly property bool hasOutput: !!(volumeSink && volumeSink.audio)
  readonly property bool hasInput: !!(source && source.audio)
  readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInput && !inputMuted)
  readonly property string toggleHint: anyAudible ? "Mute" : "Unmute"

  readonly property color hoverFill: bar
    ? Style.hoverFillFor(bar.foreground, Color.accent)
    : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Color.accent)
    : "transparent"

  function sectionCount(section) {
    if (section === "output") return displayAudioSinks.length
    if (section === "input") return displayAudioSources.length
    if (section === "streams") return displayAudioStreams.length
    return 0
  }

  function sectionVisible(section) {
    if (section === "output") return true
    if (section === "input") return displayAudioSources.length > 0 || !!source
    if (section === "streams") return displayAudioStreams.length > 0
    return false
  }

  function sectionHasSlider(section) {
    if (section === "output") return true
    if (section === "input") return !!source
    return false
  }

  readonly property var visibleSections: {
    var list = []
    if (sectionVisible("output")) list.push("output")
    if (sectionVisible("input")) list.push("input")
    if (sectionVisible("streams")) list.push("streams")
    return list
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (sections.length === 0) return
    if (focusSection === "header") {
      if (delta > 0) { focusSection = sections[0]; selectedIndex = sectionHasSlider(sections[0]) ? -1 : 0 }
      return
    }
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; selectedIndex = sectionHasSlider(focusSection) ? -1 : 0; return }

    var idx = selectedIndex
    var max = sectionCount(focusSection) - 1
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0

    if (delta > 0) {
      if (idx < max) { selectedIndex = idx + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      }
    } else {
      if (idx > floor) { selectedIndex = idx - 1; return }
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        var prevMax = sectionCount(focusSection) - 1
        selectedIndex = prevMax >= 0 ? prevMax : (sectionHasSlider(focusSection) ? -1 : 0)
      } else {
        focusSection = "header"
      }
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    selectedIndex = -1
  }

  function moveSection(delta) {
    var sections = visibleSections
    if (sections.length === 0) return
    var current = sections.indexOf(focusSection)
    if (current < 0) current = delta > 0 ? -1 : 0
    var next = (current + delta + sections.length) % sections.length
    focusSection = sections[next]
    selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
    cursorActive = true
  }

  function adjustVolume(delta) {
    if (focusSection === "output" && selectedIndex === -1) {
      setOutputVolume(outputVolume + delta)
      return
    }
    if (focusSection === "input" && selectedIndex === -1) {
      setInputVolume(inputVolume + delta)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0 && selectedIndex < displayAudioStreams.length) {
      var s = displayAudioStreams[selectedIndex]
      if (s && s.audio) s.audio.volume = Math.max(0, Math.min(1.5, s.audio.volume + delta))
    }
  }

  function activateCursor() {
    if (focusSection === "header") { toggleAllMuted(); return }
    if (focusSection === "output") {
      if (selectedIndex === -1) { toggleOutputMute(); return }
      var sink = displayAudioSinks[selectedIndex]
      if (sink) setDefaultSink(sink)
      return
    }
    if (focusSection === "input") {
      if (selectedIndex === -1) { toggleInputMute(); return }
      var src = displayAudioSources[selectedIndex]
      if (src) setDefaultSource(src)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0) {
      var st = displayAudioStreams[selectedIndex]
      if (st && st.audio) st.audio.muted = !st.audio.muted
    }
  }

  onOpenedChanged: {
    if (opened) {
      refreshDisplayAudioModels()
      focusSection = "output"
      selectedIndex = -1
      cursorActive = false
      Qt.callLater(resetScroll)
    } else {
      clearDisplayAudioModels()
    }
  }

  onAudioSinksChanged: scheduleDisplayAudioModelRefresh()
  onAudioSourcesChanged: scheduleDisplayAudioModelRefresh()
  onAudioStreamsChanged: scheduleDisplayAudioModelRefresh()

  function listSnapshot(list) {
    return Model.listSnapshot(list)
  }

  function refreshDisplayAudioModels() {
    if (!opened) return
    displayAudioSinks = listSnapshot(audioSinks)
    displayAudioSources = listSnapshot(audioSources)
    displayAudioStreams = listSnapshot(audioStreams)
    clampCursor()
  }

  function scheduleDisplayAudioModelRefresh() {
    if (!opened) return
    audioModelRefreshTimer.restart()
  }

  function clearDisplayAudioModels() {
    audioModelRefreshTimer.stop()
    displayAudioSinks = []
    displayAudioSources = []
    displayAudioStreams = []
  }

  function resetScroll() {
    if (!scrollArea) return
    var flick = scrollArea.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = 0
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var margin = 6
    var maxY = Math.max(0, (flick.contentHeight || 0) - flick.height)
    if (maxY <= Style.space(24) || (root.focusSection === "output" && root.selectedIndex === -1)) {
      flick.contentY = 0
      return
    }
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    if (top < viewTop + margin) flick.contentY = Math.max(0, Math.min(maxY, top - margin))
    else if (bottom > viewBottom - margin)
      flick.contentY = Math.max(0, Math.min(maxY, bottom + margin - flick.height))
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (focusSection === "header") return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = visibleSections[0]
      selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      return
    }
    var count = sectionCount(focusSection)
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0
    if (selectedIndex > count - 1) selectedIndex = Math.max(floor, count - 1)
    if (selectedIndex < floor) selectedIndex = floor
  }

  function outputIcon(volume) {
    if (!sink || !sink.audio) return "\u2205"
    if (isHeadphones(sink)) return "\u0298"
    if (outputMuted) return "\u2205"
    var v = volume === undefined ? outputVolume : volume
    if (v >= 0.67) return "\u266B"
    if (v >= 0.34) return "\u266B"
    if (v > 0) return "\u266A"
    return "\u2205"
  }

  function inputIcon() {
    if (!source || !source.audio) return "\u2715"
    return inputMuted ? "\u2715" : "\u25CF"
  }

  function outputVolumeName(volume, muted) {
    return Model.outputVolumeName(volume, muted)
  }

  function setOutputVolume(v) {
    if (!volumeSink || !volumeSink.audio) return outputVolume
    var volume = Math.max(0, Math.min(1, v))
    volumeSink.audio.volume = volume
    return volume
  }

  function showVolumeOsd(volume) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: outputIcon(volume),
      value: Math.round(volume * 100)
    }))
  }

  function setInputVolume(v) {
    if (!source || !source.audio) return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleOutputMute() {
    if (volumeSink && volumeSink.audio) volumeSink.audio.muted = !volumeSink.audio.muted
  }

  function toggleInputMute() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  function toggleAllMuted() {
    var mute = anyAudible
    if (hasOutput) volumeSink.audio.muted = mute
    if (hasInput) source.audio.muted = mute
  }

  function setDefaultSink(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached([
        "omarchy-audio-output-set-default",
        String(node.id),
        String(node.name)
      ])
    }
  }

  function setDefaultSource(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSource = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached([
        "omarchy-audio-input-set-default",
        String(node.id),
        String(node.name)
      ])
    }
  }

  function sinkAvailable(node) {
    if (!node || !node.name || !sinkAvailabilityLoaded) return true
    var name = String(node.name)
    return sinkAvailability[name] !== false
  }

  function updateSinkAvailability(raw) {
    sinkAvailability = Model.parseSinkAvailability(raw)
    sinkAvailabilityLoaded = true
  }

  function friendlyDeviceLabel(text) {
    return Model.friendlyDeviceLabel(text)
  }

  function nodeLabel(node) {
    return Model.nodeLabel(node)
  }

  function nodeProps(node) {
    return Model.nodeProps(node)
  }

  function isHeadphones(node) {
    return Model.isHeadphones(node)
  }

  function sinkGlyph(node) {
    return Model.sinkGlyph(node)
  }

  function sourceGlyph(node) {
    return Model.sourceGlyph(node)
  }

  function friendlyStreamLabel(label) {
    return Model.friendlyStreamLabel(label)
  }

  function streamLabelKey(label) {
    return Model.streamLabelKey(label)
  }

  function streamLabelIsGeneric(label) {
    return Model.streamLabelIsGeneric(label)
  }

  function rawStreamLabel(node) {
    return Model.rawStreamLabel(node)
  }

  function mprisPlayerLabel(player) {
    return Model.mprisPlayerLabel(player)
  }

  function mprisPlayerIsProxy(player) {
    return Model.mprisPlayerIsProxy(player)
  }

  function streamRepresentsMprisPlayer(streamLabel, playerLabel) {
    return Model.streamRepresentsMprisPlayer(streamLabel, playerLabel)
  }

  function mprisLabelsFor(predicate) {
    return Model.mprisLabelsFor(mprisPlayers, predicate)
  }

  function matchingMprisStreamLabel(label) {
    return Model.matchingMprisStreamLabel(label, mprisPlayers)
  }

  function unmatchedMprisStreamLabel(label) {
    return Model.unmatchedMprisStreamLabel(label, mprisPlayers, displayAudioStreams)
  }

  function streamLabel(node) {
    return Model.streamLabel(node, mprisPlayers, displayAudioStreams)
  }

  function streamRepresentsPlayer(node, player) {
    return Model.streamRepresentsPlayer(node, player, mprisPlayers, displayAudioStreams)
  }

  implicitWidth: embedMode ? (parent ? parent.width : 0) : (chromeVisible ? button.implicitWidth : 0)
  implicitHeight: embedMode ? (parent ? parent.height : 0) : (chromeVisible ? button.implicitHeight : 0)
  anchors.fill: embedMode ? parent : undefined

  function adoptOverlayPage() {
    if (root.embedMode || !root.chromeVisible) return
    var overlay = overlayLoader.item
    if (!overlay || !overlay.pageHost) return
    keyCatcher.parent = overlay.pageHost
    keyCatcher.anchors.fill = overlay.pageHost
  }

  Timer {
    id: overlayArm
    interval: 0
    onTriggered: {
      if (!root.embedMode && root.chromeVisible)
        root.overlayReady = true
    }
  }

  property bool overlayReady: false

  Component.onCompleted: overlayArm.start()

  PwObjectTracker { objects: root.candidateSinks }
  PwObjectTracker { objects: root.candidateSources }
  PwObjectTracker { objects: root.audioStreams }

  PwNodePeakMonitor {
    id: inputPeakMonitor
    node: root.source
    enabled: (root.opened || root.embedMode) && !!root.source
  }

  Process {
    id: sinkAvailabilityProc
    command: ["omarchy-audio-sink-availability"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateSinkAvailability(text)
    }
  }

  Process {
    id: volumeSinkProc
    command: ["omarchy-audio-output-sink"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.volumeSinkName = String(text).trim()
    }
  }

  Timer {
    interval: 5000
    running: root.opened || root.embedMode
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.resolveVolumeSink()
  }

  Timer {
    id: audioModelRefreshTimer
    interval: 75
    repeat: false
    onTriggered: root.refreshDisplayAudioModels()
  }

  BarIconButton {
    id: button
    visible: root.chromeVisible
    anchors.fill: parent
    bar: root.bar
    text: root.outputIcon()
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleAllMuted()
      else root.toggle()
    }

    onWheelMoved: function(delta) {
      if (!root.hasOutput) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      var volume = root.setOutputVolume(root.outputVolume + wheel.steps * 0.05)
      root.showVolumeOsd(volume)
    }
  }

  Item {
    id: embedHost
    visible: !overlayLoader.active
    anchors.fill: parent

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.adjustVolume(dx * 0.05)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "m" || t === "M") {
          if (!root.cursorActive) return
          if (root.focusSection === "streams" && root.selectedIndex >= 0
              && root.selectedIndex < root.displayAudioStreams.length) {
            var s = root.displayAudioStreams[root.selectedIndex]
            if (s && s.audio) s.audio.muted = !s.audio.muted
          } else if (root.focusSection === "input") {
            root.toggleInputMute()
          } else {
            root.toggleOutputMute()
          }
        }
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          Item {
            id: heroItem
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.outputIcon()
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              opacity: root.outputMuted ? 0.5 : 1.0
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            ToggleSwitch {
              id: powerSwitch
              checked: root.anyAudible
              hasCursor: root.headerHasCursor
              foreground: root.bar.foreground
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onHovered: function(on) { if (on) root.setHeaderCursor() }
              onToggled: root.toggleAllMuted()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.toggleHint
                fontFamily: root.bar.fontFamily
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.rightMargin: powerSwitch.width + Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Audio"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroLabel
                textFormat: Text.PlainText
                text: root.outputVolumeName(
                  outputSlider.dragging ? outputSlider.liveValue : root.outputVolume,
                  root.outputMuted
                ).toUpperCase()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(outputHeader.implicitHeight, outputPercent.implicitHeight)

              PanelSectionHeader {
                id: outputHeader
                text: "OUTPUT"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: outputPercent
                textFormat: Text.PlainText
                text: Math.round((outputSlider.dragging ? outputSlider.liveValue : root.outputVolume) * 100) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.outputMuted ? 0.5 : 1.0
              }
            }

            CursorSurface {
              id: outputSliderRow
              width: parent.width
              height: outputSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "output" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(outputSliderRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: outputSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: 1
                step: 0.05
                value: root.outputVolume
                opacity: root.outputMuted ? 0.5 : 1.0
                enabled: !!root.sink

                onMoved: function(v) { root.setOutputVolume(v) }
                onRightClicked: root.toggleOutputMute()
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "output"
                  root.selectedIndex = -1
                }
              }
            }

            Repeater {
              model: root.displayAudioSinks

              SinkRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: root.displayAudioSources.length > 0 || !!root.source
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.displayAudioSources.length > 0 || !!root.source

            Item {
              width: parent.width
              implicitHeight: Math.max(microphoneHeader.implicitHeight, microphonePercent.implicitHeight)

              PanelSectionHeader {
                id: microphoneHeader
                text: "INPUT"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: microphonePercent
                textFormat: Text.PlainText
                text: Math.round((inputSlider.dragging ? inputSlider.liveValue : root.inputVolume) * 100) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.inputMuted ? 0.5 : 1.0
              }
            }

            CursorSurface {
              id: inputSliderRow
              visible: !!root.source
              width: parent.width
              height: inputControls.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(inputSliderRow)
              foreground: root.bar.foreground
              outline: true

              Column {
                id: inputControls
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(5)

                PanelSlider {
                  id: inputSlider
                  bar: root.bar
                  width: parent.width
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: root.inputVolume
                  opacity: root.inputMuted ? 0.5 : 1.0
                  enabled: !!root.source

                  onMoved: function(v) { root.setInputVolume(v) }
                  onRightClicked: root.toggleInputMute()
                }

                Rectangle {
                  width: parent.width
                  height: Math.max(Style.space(5), Style.spacing.xs)
                  color: Util.alpha(root.bar.foreground, 0.18)
                  opacity: root.inputMuted ? 0.35 : 1.0

                  Rectangle {
                    height: parent.height
                    width: parent.width * Math.max(0, Math.min(1, inputPeakMonitor.peak))
                    color: root.bar.foreground
                    Behavior on width { NumberAnimation { duration: 70 } }
                  }
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "input"
                  root.selectedIndex = -1
                }
              }
            }

            Repeater {
              model: root.displayAudioSources

              SourceRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: root.displayAudioStreams.length > 0
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.displayAudioStreams.length > 0

            PanelSectionHeader {
              text: "SOURCES"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.displayAudioStreams

              StreamRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
              }
            }
          }
        }
      }
    }
  }

  Loader {
    id: overlayLoader
    active: root.overlayReady
    sourceComponent: KeyboardPanel {
      id: panel
      anchorItem: root.hostAnchor || button
      owner: root
      bar: root.bar
      open: root.opened
      focusTarget: keyCatcher
      contentWidth: panel.fittedContentWidth(Style.space(380))
      contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))
    }
    onLoaded: root.adoptOverlayPage()
  }

  component SinkRow: CursorSurface {
    id: sinkRow
    required property var node
    required property int rowIndex

    readonly property bool isActive: root.sink && node && root.sink.id === node.id
    hasCursor: root.cursorActive && root.focusSection === "output" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sinkRow)
    current: isActive
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: sinkInner.implicitHeight + Style.spacing.xl

    Row {
      id: sinkInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: root.sinkGlyph(sinkRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: root.nodeLabel(sinkRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: sinkRow.isActive
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "output"
        root.selectedIndex = sinkRow.rowIndex
      }
      onClicked: root.setDefaultSink(sinkRow.node)
    }
  }

  component SourceRow: CursorSurface {
    id: sourceRow
    required property var node
    required property int rowIndex

    readonly property bool isActive: root.source && node && root.source.id === node.id
    hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sourceRow)
    current: isActive
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: sourceInner.implicitHeight + Style.spacing.xl

    Row {
      id: sourceInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: root.sourceGlyph(sourceRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: root.nodeLabel(sourceRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: sourceRow.isActive
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "input"
        root.selectedIndex = sourceRow.rowIndex
      }
      onClicked: root.setDefaultSource(sourceRow.node)
    }
  }

  component StreamRow: CursorSurface {
    id: streamRow
    required property var node
    required property int rowIndex

    readonly property real streamVolume: node && node.audio ? node.audio.volume : 0
    readonly property bool streamMuted: node && node.audio ? node.audio.muted : false
    readonly property bool isActive: root.streamRepresentsPlayer(node, root.activeMediaPlayer)

    hasCursor: root.cursorActive && root.focusSection === "streams" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(streamRow)
    current: isActive
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: streamColumn.implicitHeight + Style.spacing.xl

    Column {
      id: streamColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: streamMuteIcon
          textFormat: Text.PlainText
          text: streamRow.streamMuted ? "∅" : "●"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          width: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
          opacity: streamRow.streamMuted ? 0.5 : 1.0

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (streamRow.node && streamRow.node.audio)
                streamRow.node.audio.muted = !streamRow.node.audio.muted
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: root.streamLabel(streamRow.node)
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: streamRow.isActive
          elide: Text.ElideRight
          width: parent.width - streamMuteIcon.width - streamPct.width - Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: streamPct
          textFormat: Text.PlainText
          text: Math.round(streamRow.streamVolume * 100) + "%"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          width: Style.space(36)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
          opacity: streamRow.streamMuted ? 0.5 : 1.0
        }
      }

      PanelSlider {
        bar: root.bar
        width: parent.width
        minimum: 0
        maximum: 1.5
        step: 0.05
        value: streamRow.streamVolume
        opacity: streamRow.streamMuted ? 0.5 : 1.0

        onMoved: function(v) {
          if (streamRow.node && streamRow.node.audio) streamRow.node.audio.volume = v
        }
        onRightClicked: {
          if (streamRow.node && streamRow.node.audio)
            streamRow.node.audio.muted = !streamRow.node.audio.muted
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      propagateComposedEvents: true
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "streams"
        root.selectedIndex = streamRow.rowIndex
      }
    }
  }
}
