import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons

// Hosts the existing image picker twice: theme packs and wallpapers.
// This is Settings chrome over omarchy.image-picker, not a second Settings app.
Item {
  id: root

  property bool embedMode: true
  property bool chromeVisible: false
  property bool manageIpc: false
  property var bar: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string themeDirs: ""
  property string wallpaperDirs: ""

  function injectPicker(item, kind, dirs) {
    if (!item) return
    item.embedMode = true
    item.embedApplyKind = kind
    item.imageDirs = dirs
    item.showLabels = true
    item.filterable = true
    if (typeof item.startEmbedded === "function") item.startEmbedded()
  }

  function wallpaperDirList() {
    var home = Quickshell.env("HOME")
    var themeName = String(themeNameView.text() || "").replace(/\n/g, "").trim()
    var dirs = [home + "/.local/state/omarchy/current/theme/backgrounds"]
    if (themeName !== "")
      dirs.push(home + "/.config/omarchy/backgrounds/" + themeName)
    return dirs.join("\n")
  }

  FileView {
    id: themeNameView
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: root.wallpaperDirs = root.wallpaperDirList()
  }

  Process {
    id: themeDirProc
    command: ["bash", "-c",
      "find " + Util.shellQuote(root.omarchyPath + "/themes") + " " +
      Util.shellQuote(Quickshell.env("HOME") + "/.config/omarchy/themes") +
      " -mindepth 1 -maxdepth 1 \\( -type d -o -type l \\) -print 2>/dev/null | while IFS= read -r dir; do" +
      " for name in preview.png preview.jpg preview.jpeg preview.webp preview.gif preview.bmp; do" +
      "  if [[ -f $dir/$name ]]; then printf '%s\\n' \"$dir\"; break; fi; done; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.themeDirs = String(text || "").trim()
        if (themeLoader.item) root.injectPicker(themeLoader.item, "theme", root.themeDirs)
      }
    }
  }

  onWallpaperDirsChanged: if (wallpaperLoader.item && root.wallpaperDirs !== "")
    root.injectPicker(wallpaperLoader.item, "wallpaper", root.wallpaperDirs)

  Component.onCompleted: {
    root.wallpaperDirs = root.wallpaperDirList()
    themeDirProc.running = true
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      text: "Theme packs"
      color: Tokens.text.secondary
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      Layout.fillWidth: true
    }

    Loader {
      id: themeLoader
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 180
      Component.onCompleted: setSource(Quickshell.shellPath("plugins/image-picker/ImagePicker.qml"), {
        embedMode: true,
        embedApplyKind: "theme",
        imageDirs: ""
      })
      onLoaded: if (root.themeDirs !== "") root.injectPicker(item, "theme", root.themeDirs)
    }

    Text {
      textFormat: Text.PlainText
      text: "Wallpaper"
      color: Tokens.text.secondary
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      Layout.fillWidth: true
    }

    Loader {
      id: wallpaperLoader
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 180
      Component.onCompleted: setSource(Quickshell.shellPath("plugins/image-picker/ImagePicker.qml"), {
        embedMode: true,
        embedApplyKind: "wallpaper",
        imageDirs: ""
      })
      onLoaded: if (root.wallpaperDirs !== "") root.injectPicker(item, "wallpaper", root.wallpaperDirs)
    }
  }
}
