function isArgvList(value) {
  return !!value && typeof value !== "string" && typeof value !== "function" && typeof value.length === "number"
}

function copyArgv(value) {
  if (!isArgvList(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function isDesktopFieldCode(part) {
  return /^%[A-Za-z@]$/.test(String(part || ""))
}

function argvFrom(command) {
  if (isArgvList(command)) {
    var out = []
    for (var i = 0; i < command.length; i++) {
      var part = String(command[i] === undefined || command[i] === null ? "" : command[i])
      if (!part || isDesktopFieldCode(part)) continue
      out.push(part)
    }
    return out
  }
  var raw = String(command || "").trim().replace(/\s+%[A-Za-z@]/g, "")
  if (!raw) return []
  return raw.split(/\s+/).filter(Boolean)
}

function resolveLaunchArgv(command, omarchyPath) {
  var parts = argvFrom(command)
  if (parts.length === 0) return []
  var bin = parts[0]
  if (bin.charAt(0) !== "/" && bin.indexOf("omarchy-") === 0 && omarchyPath)
    parts[0] = String(omarchyPath) + "/bin/" + bin
  return parts
}

if (typeof module !== "undefined") {
  module.exports = {
    isArgvList: isArgvList,
    copyArgv: copyArgv,
    argvFrom: argvFrom,
    resolveLaunchArgv: resolveLaunchArgv
  }
}
