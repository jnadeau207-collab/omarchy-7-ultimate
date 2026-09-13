import QtQuick
import qs.Commons

Item {
  id: root

  property var host: null
  property int frame: 6
  property int captionHeight: 30

  Canvas {
    id: glassPaint
    anchors.fill: parent
    antialiasing: true
    renderTarget: Canvas.FramebufferObject

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      var w = width
      var h = height
      if (w < 2 || h < 2)
        return
      ctx.reset()
      ctx.clearRect(0, 0, w, h)
      ctx.beginPath()
      var r = 6
      ctx.moveTo(r, 0)
      ctx.lineTo(w - r, 0)
      ctx.quadraticCurveTo(w, 0, w, r)
      ctx.lineTo(w, h - r)
      ctx.quadraticCurveTo(w, h, w - r, h)
      ctx.lineTo(r, h)
      ctx.quadraticCurveTo(0, h, 0, h - r)
      ctx.lineTo(0, r)
      ctx.quadraticCurveTo(0, 0, r, 0)
      ctx.closePath()
      ctx.clip()

      ctx.fillStyle = "rgba(69, 128, 196, 0.66)"
      ctx.fillRect(0, 0, w, h)

      var across = ctx.createLinearGradient(0, 0, w, 0)
      across.addColorStop(0.0, "rgba(255,255,255,0.14)")
      across.addColorStop(0.5, "rgba(0,0,0,0.06)")
      across.addColorStop(1.0, "rgba(255,255,255,0.10)")
      ctx.fillStyle = across
      ctx.fillRect(0, 0, w, h)

      ctx.save()
      ctx.beginPath()
      ctx.moveTo(0, 0)
      ctx.lineTo(100, 0)
      ctx.lineTo(0, 100)
      ctx.closePath()
      ctx.clip()
      var specL = ctx.createLinearGradient(0, 0, 70, 70)
      specL.addColorStop(0.0, "rgba(255,255,255,0.22)")
      specL.addColorStop(1.0, "rgba(255,255,255,0.00)")
      ctx.fillStyle = specL
      ctx.fillRect(0, 0, 100, 100)
      ctx.restore()

      ctx.save()
      ctx.beginPath()
      ctx.moveTo(w, 0)
      ctx.lineTo(w - 100, 0)
      ctx.lineTo(w, 100)
      ctx.closePath()
      ctx.clip()
      var specR = ctx.createLinearGradient(w, 0, w - 70, 70)
      specR.addColorStop(0.0, "rgba(255,255,255,0.22)")
      specR.addColorStop(1.0, "rgba(255,255,255,0.00)")
      ctx.fillStyle = specR
      ctx.fillRect(w - 100, 0, 100, 100)
      ctx.restore()

      ctx.lineWidth = 1
      ctx.strokeStyle = "rgba(0,0,0,0.70)"
      ctx.beginPath()
      ctx.moveTo(r, 0.5)
      ctx.lineTo(w - r, 0.5)
      ctx.quadraticCurveTo(w - 0.5, 0.5, w - 0.5, r)
      ctx.lineTo(w - 0.5, h - r)
      ctx.quadraticCurveTo(w - 0.5, h - 0.5, w - r, h - 0.5)
      ctx.lineTo(r, h - 0.5)
      ctx.quadraticCurveTo(0.5, h - 0.5, 0.5, h - r)
      ctx.lineTo(0.5, r)
      ctx.quadraticCurveTo(0.5, 0.5, r, 0.5)
      ctx.stroke()

      ctx.strokeStyle = "rgba(255,255,255,0.35)"
      ctx.beginPath()
      ctx.moveTo(r, 1.5)
      ctx.lineTo(w - r, 1.5)
      ctx.quadraticCurveTo(w - 1.5, 1.5, w - 1.5, r)
      ctx.lineTo(w - 1.5, h - r)
      ctx.quadraticCurveTo(w - 1.5, h - 1.5, w - r, h - 1.5)
      ctx.lineTo(r, h - 1.5)
      ctx.quadraticCurveTo(1.5, h - 1.5, 1.5, h - r)
      ctx.lineTo(1.5, r)
      ctx.quadraticCurveTo(1.5, 1.5, r, 1.5)
      ctx.stroke()
    }
  }
}
