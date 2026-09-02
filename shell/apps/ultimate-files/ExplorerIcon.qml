import QtQuick

import "ExplorerTheme.js" as Aero

Canvas {
  id: root

  property string kind: "file"
  property string extension: ""
  property bool dimmed: false

  implicitWidth: 16
  implicitHeight: 16
  antialiasing: true
  renderStrategy: Canvas.Cooperative

  onKindChanged: requestPaint()
  onExtensionChanged: requestPaint()
  onDimmedChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  function vertical(ctx, x, y, w, h, top, bottom) {
    var gradient = ctx.createLinearGradient(x, y, x, y + h)
    gradient.addColorStop(0, top)
    gradient.addColorStop(1, bottom)
    return gradient
  }

  function roundedPath(ctx, x, y, w, h, r) {
    ctx.beginPath()
    ctx.moveTo(x + r, y)
    ctx.lineTo(x + w - r, y)
    ctx.quadraticCurveTo(x + w, y, x + w, y + r)
    ctx.lineTo(x + w, y + h - r)
    ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
    ctx.lineTo(x + r, y + h)
    ctx.quadraticCurveTo(x, y + h, x, y + h - r)
    ctx.lineTo(x, y + r)
    ctx.quadraticCurveTo(x, y, x + r, y)
    ctx.closePath()
  }

  function paintFolder(ctx, w, h) {
    var x = w * 0.04
    var y = h * 0.16
    var fw = w * 0.92
    var fh = h * 0.68
    var tab = fw * 0.42
    var radius = Math.max(1, fw * 0.06)

    ctx.beginPath()
    ctx.moveTo(x, y + fh)
    ctx.lineTo(x, y + radius)
    ctx.quadraticCurveTo(x, y, x + radius, y)
    ctx.lineTo(x + tab - radius, y)
    ctx.quadraticCurveTo(x + tab, y, x + tab + fw * 0.05, y + fh * 0.16)
    ctx.lineTo(x + fw - radius, y + fh * 0.16)
    ctx.quadraticCurveTo(x + fw, y + fh * 0.16, x + fw, y + fh * 0.16 + radius)
    ctx.lineTo(x + fw, y + fh)
    ctx.closePath()
    ctx.fillStyle = vertical(ctx, x, y, fw, fh, Aero.folderBackTop, Aero.folderBackBottom)
    ctx.fill()
    ctx.strokeStyle = Aero.folderOutline
    ctx.lineWidth = Math.max(1, w / 32)
    ctx.stroke()

    var fy = y + fh * 0.30
    roundedPath(ctx, x + fw * 0.03, fy, fw * 0.94, y + fh - fy, radius)
    ctx.fillStyle = vertical(ctx, x, fy, fw, y + fh - fy, Aero.folderFrontTop, Aero.folderFrontBottom)
    ctx.fill()
    ctx.strokeStyle = Aero.folderOutline
    ctx.stroke()

    ctx.beginPath()
    ctx.moveTo(x + fw * 0.10, fy + Math.max(1, h / 24))
    ctx.lineTo(x + fw * 0.90, fy + Math.max(1, h / 24))
    ctx.strokeStyle = Aero.folderHighlight
    ctx.lineWidth = Math.max(1, w / 40)
    ctx.stroke()
  }

  function paintSheet(ctx, w, h) {
    var x = w * 0.18
    var y = h * 0.06
    var sw = w * 0.64
    var sh = h * 0.88
    var fold = sw * 0.36

    ctx.beginPath()
    ctx.moveTo(x, y)
    ctx.lineTo(x + sw - fold, y)
    ctx.lineTo(x + sw, y + fold)
    ctx.lineTo(x + sw, y + sh)
    ctx.lineTo(x, y + sh)
    ctx.closePath()
    ctx.fillStyle = vertical(ctx, x, y, sw, sh, Aero.sheetTop, Aero.sheetBottom)
    ctx.fill()
    ctx.strokeStyle = Aero.sheetOutline
    ctx.lineWidth = Math.max(1, w / 32)
    ctx.stroke()

    ctx.beginPath()
    ctx.moveTo(x + sw - fold, y)
    ctx.lineTo(x + sw, y + fold)
    ctx.lineTo(x + sw - fold, y + fold)
    ctx.closePath()
    ctx.fillStyle = Aero.sheetFold
    ctx.fill()
    ctx.strokeStyle = Aero.sheetOutline
    ctx.stroke()

    if (w >= 32) {
      ctx.strokeStyle = "#c3cad1"
      ctx.lineWidth = Math.max(1, w / 48)
      for (var line = 0; line < 4; line++) {
        var ly = y + sh * (0.52 + line * 0.11)
        ctx.beginPath()
        ctx.moveTo(x + sw * 0.16, ly)
        ctx.lineTo(x + sw * 0.84, ly)
        ctx.stroke()
      }
    }
  }

  function paintShortcut(ctx, w, h) {
    paintSheet(ctx, w, h)
    var size = Math.max(6, w * 0.40)
    var x = w * 0.10
    var y = h - size - h * 0.06
    ctx.beginPath()
    ctx.rect(x, y, size, size)
    ctx.fillStyle = "#ffffff"
    ctx.fill()
    ctx.strokeStyle = "#8f9aa5"
    ctx.lineWidth = 1
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(x + size * 0.26, y + size * 0.74)
    ctx.lineTo(x + size * 0.72, y + size * 0.28)
    ctx.moveTo(x + size * 0.44, y + size * 0.26)
    ctx.lineTo(x + size * 0.74, y + size * 0.26)
    ctx.lineTo(x + size * 0.74, y + size * 0.56)
    ctx.strokeStyle = "#1f5f9e"
    ctx.lineWidth = Math.max(1, size / 8)
    ctx.stroke()
  }

  function paintDrive(ctx, w, h) {
    var x = w * 0.08
    var y = h * 0.20
    var dw = w * 0.84
    var dh = h * 0.58
    roundedPath(ctx, x, y, dw, dh, Math.max(1, w * 0.06))
    ctx.fillStyle = vertical(ctx, x, y, dw, dh, Aero.driveTop, Aero.driveBottom)
    ctx.fill()
    ctx.strokeStyle = Aero.driveOutline
    ctx.lineWidth = Math.max(1, w / 32)
    ctx.stroke()

    ctx.beginPath()
    ctx.moveTo(x + dw * 0.08, y + dh * 0.42)
    ctx.lineTo(x + dw * 0.92, y + dh * 0.42)
    ctx.strokeStyle = "#ffffff"
    ctx.lineWidth = Math.max(1, w / 40)
    ctx.stroke()

    ctx.beginPath()
    ctx.arc(x + dw * 0.84, y + dh * 0.74, Math.max(1, w * 0.035), 0, Math.PI * 2)
    ctx.fillStyle = "#5bb75b"
    ctx.fill()
  }

  function paintGlobe(ctx, w, h) {
    var cx = w / 2
    var cy = h / 2
    var r = Math.min(w, h) * 0.40
    ctx.beginPath()
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.fillStyle = vertical(ctx, cx - r, cy - r, r * 2, r * 2, "#dff0fb", "#7fb8e4")
    ctx.fill()
    ctx.strokeStyle = "#4a7fae"
    ctx.lineWidth = Math.max(1, w / 32)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(cx - r, cy)
    ctx.lineTo(cx + r, cy)
    ctx.stroke()
    ctx.beginPath()
    ctx.ellipse(cx - r * 0.52, cy - r, r * 1.04, r * 2)
    ctx.stroke()
  }

  function paintMonitor(ctx, w, h) {
    var x = w * 0.10
    var y = h * 0.18
    var mw = w * 0.80
    var mh = h * 0.50
    roundedPath(ctx, x, y, mw, mh, Math.max(1, w * 0.05))
    ctx.fillStyle = vertical(ctx, x, y, mw, mh, "#e9eef4", "#b9c5d2")
    ctx.fill()
    ctx.strokeStyle = "#7d8996"
    ctx.lineWidth = Math.max(1, w / 32)
    ctx.stroke()
    ctx.beginPath()
    ctx.rect(x + mw * 0.09, y + mh * 0.14, mw * 0.82, mh * 0.62)
    ctx.fillStyle = vertical(ctx, x, y, mw, mh, "#9fd2f5", "#3f89c9")
    ctx.fill()
    ctx.beginPath()
    ctx.rect(x + mw * 0.34, y + mh, mw * 0.32, h * 0.12)
    ctx.fillStyle = "#a8b4c0"
    ctx.fill()
    ctx.beginPath()
    ctx.rect(x + mw * 0.18, y + mh + h * 0.12, mw * 0.64, h * 0.06)
    ctx.fillStyle = "#8f9ca9"
    ctx.fill()
  }

  function paintStar(ctx, w, h) {
    var cx = w / 2
    var cy = h * 0.52
    var outer = Math.min(w, h) * 0.44
    var inner = outer * 0.46
    ctx.beginPath()
    for (var i = 0; i < 10; i++) {
      var radius = i % 2 === 0 ? outer : inner
      var angle = -Math.PI / 2 + i * Math.PI / 5
      var px = cx + Math.cos(angle) * radius
      var py = cy + Math.sin(angle) * radius
      if (i === 0) ctx.moveTo(px, py)
      else ctx.lineTo(px, py)
    }
    ctx.closePath()
    ctx.fillStyle = vertical(ctx, cx - outer, cy - outer, outer * 2, outer * 2, "#ffe9a4", "#f2b830")
    ctx.fill()
    ctx.strokeStyle = "#c9911f"
    ctx.lineWidth = Math.max(1, w / 32)
    ctx.stroke()
  }

  function paintLibrary(ctx, w, h) {
    var x = w * 0.10
    var base = h * 0.80
    var colors = [["#cfe4f7", "#8bb8de"], ["#d9edd2", "#89bd7c"], ["#fbe0c8", "#e0a25f"]]
    for (var i = 0; i < 3; i++) {
      var bw = w * 0.19
      var bh = h * (0.40 + i * 0.11)
      var bx = x + i * (bw + w * 0.05)
      ctx.beginPath()
      ctx.rect(bx, base - bh, bw, bh)
      ctx.fillStyle = vertical(ctx, bx, base - bh, bw, bh, colors[i][0], colors[i][1])
      ctx.fill()
      ctx.strokeStyle = "#6f7d8a"
      ctx.lineWidth = Math.max(1, w / 40)
      ctx.stroke()
    }
  }

  function paintTrash(ctx, w, h) {
    var x = w * 0.24
    var y = h * 0.24
    var tw = w * 0.52
    var th = h * 0.62
    ctx.beginPath()
    ctx.moveTo(x, y)
    ctx.lineTo(x + tw, y)
    ctx.lineTo(x + tw * 0.86, y + th)
    ctx.lineTo(x + tw * 0.14, y + th)
    ctx.closePath()
    ctx.fillStyle = vertical(ctx, x, y, tw, th, "#e8eef4", "#a9b8c6")
    ctx.fill()
    ctx.strokeStyle = "#6f7d8a"
    ctx.lineWidth = Math.max(1, w / 32)
    ctx.stroke()
    ctx.beginPath()
    ctx.ellipse(x - tw * 0.06, y - h * 0.10, tw * 1.12, h * 0.18)
    ctx.fillStyle = "#cbd6e0"
    ctx.fill()
    ctx.strokeStyle = "#6f7d8a"
    ctx.stroke()
    if (w >= 32) {
      ctx.strokeStyle = "#7f8d9a"
      ctx.lineWidth = Math.max(1, w / 44)
      for (var line = 0; line < 3; line++) {
        var lx = x + tw * (0.28 + line * 0.22)
        ctx.beginPath()
        ctx.moveTo(lx, y + th * 0.18)
        ctx.lineTo(lx - tw * 0.02, y + th * 0.82)
        ctx.stroke()
      }
    }
  }

  function paintSearch(ctx, w, h) {
    var r = Math.min(w, h) * 0.28
    var cx = w * 0.44
    var cy = h * 0.42
    ctx.beginPath()
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.fillStyle = "#eaf4fc"
    ctx.fill()
    ctx.strokeStyle = "#4a7fae"
    ctx.lineWidth = Math.max(1.5, w / 12)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(cx + r * 0.72, cy + r * 0.72)
    ctx.lineTo(w * 0.86, h * 0.86)
    ctx.strokeStyle = "#3d6f9c"
    ctx.lineCap = "round"
    ctx.stroke()
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)
    if (width <= 0 || height <= 0) return
    ctx.globalAlpha = root.dimmed ? 0.45 : 1.0
    if (kind === "directory" || kind === "folder") paintFolder(ctx, width, height)
    else if (kind === "symlink") paintShortcut(ctx, width, height)
    else if (kind === "drive" || kind === "mount") paintDrive(ctx, width, height)
    else if (kind === "network") paintGlobe(ctx, width, height)
    else if (kind === "computer") paintMonitor(ctx, width, height)
    else if (kind === "favorites") paintStar(ctx, width, height)
    else if (kind === "libraries") paintLibrary(ctx, width, height)
    else if (kind === "trash") paintTrash(ctx, width, height)
    else if (kind === "search") paintSearch(ctx, width, height)
    else paintSheet(ctx, width, height)
  }
}
