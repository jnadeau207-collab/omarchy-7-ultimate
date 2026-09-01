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
      // A route is a catalog id, never a command fragment. The launcher runs as
      // an argv vector so a summon payload never reaches a shell, and a route
      // that is not shaped like a catalog id falls back to the Settings home
      // instead of being handed on. The window host still fails closed on an id
      // that is not in apps/ultimate-settings/routes-v1.json.
      if (route !== "" && /^[a-z][a-z0-9]*(\.[a-z0-9-]+)+$/.test(route)) {
        var launcher = root.omarchyPath
          ? root.omarchyPath + "/bin/omarchy-launch-settings"
          : "omarchy-launch-settings"
        Util.execArgv(["uwsm-app", "--", launcher, "--source", "desktop", route])
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
