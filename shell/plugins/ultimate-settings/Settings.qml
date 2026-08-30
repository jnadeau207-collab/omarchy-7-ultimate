import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false

  function open(payloadJson) {
    var route = ""
    try {
      var payload = payloadJson ? JSON.parse(payloadJson) : {}
      route = String(payload.routeId || payload.route || "")
    } catch (e) {
      route = ""
    }
    if (root.shell && root.shell.appLibrary) {
      if (route !== "") {
        var command = root.shell.appLibrary.launchCommand("omarchy-launch-settings --source desktop " + route)
        if (command) Util.execDetached("uwsm-app -- " + command)
      } else {
        root.shell.appLibrary.launch("org.omarchy.Settings", "Settings")
      }
    }
    root.close()
  }

  function close() {
    if (root.shell && root.shell.transientCoordinator)
      root.shell.transientCoordinator.release(root)
    root.opened = false
  }
}
