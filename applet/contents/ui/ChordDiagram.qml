import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Draws one guitar chord box from the fret data returned by the service.
// Finger numbers are deliberately not drawn - dots and the barre only.
Item {
    id: diagram

    property var shape: null
    property color lineColor: Kirigami.Theme.textColor
    property color dotColor: Kirigami.Theme.highlightColor

    readonly property int strings: 6
    readonly property int fretSpan: 5
    readonly property real stringGap: Kirigami.Units.smallSpacing * 1.7
    readonly property real fretGap: Kirigami.Units.smallSpacing * 2.1
    readonly property real markerHeight: Kirigami.Units.smallSpacing * 1.2
    readonly property real pad: Kirigami.Units.smallSpacing

    readonly property var frets: shape && shape.frets ? shape.frets : []
    readonly property int base: shape && shape.base ? shape.base : 1
    readonly property bool showNut: base <= 1

    readonly property real gridWidth: (strings - 1) * stringGap
    readonly property real gridHeight: fretSpan * fretGap

    implicitWidth: gridWidth + pad * 2 + Kirigami.Units.smallSpacing * 2
    implicitHeight: nameLabel.implicitHeight + markerHeight + gridHeight + pad * 2

    onShapeChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onDotColorChanged: canvas.requestPaint()

    PlasmaComponents3.Label {
        id: nameLabel
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        text: diagram.shape ? diagram.shape.name : ""
        font.weight: Font.DemiBold
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        color: diagram.lineColor
    }

    Canvas {
        id: canvas
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: nameLabel.bottom
        width: diagram.gridWidth + diagram.pad * 2
        height: diagram.markerHeight + diagram.gridHeight + diagram.pad

        onPaint: {
            var ctx = getContext("2d")
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clearRect(0, 0, width, height)

            var data = diagram.frets
            if (!data || data.length < diagram.strings) return

            var left = diagram.pad
            var top = diagram.markerHeight
            var gw = diagram.gridWidth
            var gh = diagram.gridHeight
            var line = Math.max(1, Math.round(Kirigami.Units.devicePixelRatio))
            var toX = function (i) { return left + i * diagram.stringGap }
            var toY = function (fret) { return top + (fret - 0.5) * diagram.fretGap }

            ctx.lineWidth = line
            ctx.strokeStyle = diagram.lineColor

            // frets
            for (var f = 0; f <= diagram.fretSpan; f++) {
                var y = top + f * diagram.fretGap
                ctx.beginPath()
                ctx.lineWidth = (f === 0 && diagram.showNut) ? line * 3 : line
                ctx.moveTo(left, y)
                ctx.lineTo(left + gw, y)
                ctx.stroke()
            }
            // strings
            ctx.lineWidth = line
            for (var s = 0; s < diagram.strings; s++) {
                ctx.beginPath()
                ctx.moveTo(toX(s), top)
                ctx.lineTo(toX(s), top + gh)
                ctx.stroke()
            }

            // open / muted markers
            ctx.font = Math.round(diagram.markerHeight * 0.9) + "px sans-serif"
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            for (var i = 0; i < diagram.strings; i++) {
                var fret = data[i]
                if (fret === 0) {
                    ctx.strokeStyle = diagram.lineColor
                    ctx.beginPath()
                    ctx.arc(toX(i), top - diagram.markerHeight * 0.5, diagram.markerHeight * 0.28, 0, Math.PI * 2)
                    ctx.stroke()
                } else if (fret < 0) {
                    ctx.strokeStyle = diagram.lineColor
                    var mx = toX(i)
                    var my = top - diagram.markerHeight * 0.5
                    var r = diagram.markerHeight * 0.24
                    ctx.beginPath()
                    ctx.moveTo(mx - r, my - r); ctx.lineTo(mx + r, my + r)
                    ctx.moveTo(mx + r, my - r); ctx.lineTo(mx - r, my + r)
                    ctx.stroke()
                }
            }

            // barre
            var barre = diagram.shape ? diagram.shape.barre : null
            if (barre) {
                var indices = []
                for (var k = 0; k < diagram.strings; k++)
                    if (data[k] === barre) indices.push(k)
                if (indices.length >= 2) {
                    var from = Math.min.apply(null, indices)
                    var to = Math.max.apply(null, indices)
                    ctx.fillStyle = diagram.dotColor
                    var radius = diagram.stringGap * 0.34
                    var cy = toY(barre)
                    ctx.beginPath()
                    ctx.moveTo(toX(from), cy - radius)
                    ctx.lineTo(toX(to), cy - radius)
                    ctx.arc(toX(to), cy, radius, -Math.PI / 2, Math.PI / 2)
                    ctx.lineTo(toX(from), cy + radius)
                    ctx.arc(toX(from), cy, radius, Math.PI / 2, -Math.PI / 2)
                    ctx.fill()
                }
            }

            // dots
            ctx.fillStyle = diagram.dotColor
            for (var d = 0; d < diagram.strings; d++) {
                var fretValue = data[d]
                if (fretValue <= 0) continue
                var relative = fretValue - diagram.base
                if (relative < 0 || relative >= diagram.fretSpan) continue
                if (barre && fretValue === barre) continue
                ctx.beginPath()
                ctx.arc(toX(d), toY(fretValue), diagram.stringGap * 0.32, 0, Math.PI * 2)
                ctx.fill()
            }

            // base fret number when the shape sits up the neck
            if (!diagram.showNut && diagram.base > 1) {
                ctx.fillStyle = diagram.lineColor
                ctx.textAlign = "right"
                ctx.textBaseline = "middle"
                ctx.fillText(String(diagram.base), left - Kirigami.Units.smallSpacing * 0.5, top + diagram.fretGap * 0.5)
            }
        }
    }
}
