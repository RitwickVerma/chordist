// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// One guitar chord box, drawn from the fret data the service sends: low E on the
// left, dots for fretted strings, a bar for a barre, o/x above open and muted
// strings. `zoom` scales the whole box (the Stage draws it large); at a large
// enough size the finger numbers appear inside the dots. `mirrored` flips it for
// a left-handed player.
Item {
    id: diagram

    property var shape: null
    property color lineColor: Kirigami.Theme.textColor
    property color dotColor: Kirigami.Theme.highlightColor
    property color dotTextColor: Kirigami.Theme.highlightedTextColor
    property real zoom: 1
    property bool showFingers: false
    property bool mirrored: false
    property bool showName: true

    readonly property int strings: 6
    readonly property int fretSpan: 5
    readonly property real stringGap: Kirigami.Units.smallSpacing * 1.7 * zoom
    readonly property real fretGap: Kirigami.Units.smallSpacing * 2.1 * zoom
    readonly property real markerHeight: Kirigami.Units.smallSpacing * 1.2 * zoom
    readonly property real pad: Kirigami.Units.smallSpacing * zoom
    readonly property real dotRadius: stringGap * 0.32

    readonly property var frets: shape && shape.frets ? shape.frets : []
    readonly property var fingers: shape && shape.fingers ? shape.fingers : []
    readonly property int base: shape && shape.base ? shape.base : 1
    readonly property bool showNut: base <= 1
    // Numbers only fit in dots of a reasonable size.
    readonly property bool numbered: showFingers && dotRadius >= 5.5

    readonly property real gridWidth: (strings - 1) * stringGap
    readonly property real gridHeight: fretSpan * fretGap
    readonly property real labelHeight: showName ? nameLabel.implicitHeight : 0

    implicitWidth: gridWidth + pad * 2 + Kirigami.Units.smallSpacing * 2 * zoom
    implicitHeight: labelHeight + markerHeight + gridHeight + pad * 2

    onShapeChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onDotColorChanged: canvas.requestPaint()
    onZoomChanged: canvas.requestPaint()
    onMirroredChanged: canvas.requestPaint()
    onNumberedChanged: canvas.requestPaint()

    Accessible.role: Accessible.Graphic
    Accessible.name: shape ? shape.name + ", frets " + frets.map(function (f) { return f < 0 ? "x" : f }).join(" ") : ""

    PlasmaComponents3.Label {
        id: nameLabel
        visible: diagram.showName
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        text: diagram.shape ? diagram.shape.name : ""
        font.weight: Font.DemiBold
        font.pointSize: Kirigami.Theme.smallFont.pointSize * Math.min(1.5, diagram.zoom)
        color: diagram.lineColor
    }

    Canvas {
        id: canvas
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: diagram.labelHeight
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
            var line = Math.max(1, Math.round(Screen.devicePixelRatio))
            // Strings run low to high in the data; a left-handed diagram reads the other way.
            var toX = function (i) { return left + (diagram.mirrored ? diagram.strings - 1 - i : i) * diagram.stringGap }
            var toY = function (fret) { return top + (fret - diagram.base + 0.5) * diagram.fretGap }

            ctx.lineWidth = line
            ctx.strokeStyle = diagram.lineColor

            // frets, the nut thicker when the box starts at the first fret
            for (var f = 0; f <= diagram.fretSpan; f++) {
                var y = top + f * diagram.fretGap
                ctx.beginPath()
                ctx.lineWidth = (f === 0 && diagram.showNut) ? line * 3 : line
                ctx.moveTo(left, y)
                ctx.lineTo(left + gw, y)
                ctx.stroke()
            }
            ctx.lineWidth = line
            for (var s = 0; s < diagram.strings; s++) {
                ctx.beginPath()
                ctx.moveTo(left + s * diagram.stringGap, top)
                ctx.lineTo(left + s * diagram.stringGap, top + gh)
                ctx.stroke()
            }

            // open / muted markers
            for (var i = 0; i < diagram.strings; i++) {
                var fret = data[i]
                var mx = toX(i)
                var my = top - diagram.markerHeight * 0.5
                ctx.strokeStyle = diagram.lineColor
                if (fret === 0) {
                    ctx.beginPath()
                    ctx.arc(mx, my, diagram.markerHeight * 0.28, 0, Math.PI * 2)
                    ctx.stroke()
                } else if (fret < 0) {
                    var r = diagram.markerHeight * 0.24
                    ctx.beginPath()
                    ctx.moveTo(mx - r, my - r); ctx.lineTo(mx + r, my + r)
                    ctx.moveTo(mx + r, my - r); ctx.lineTo(mx - r, my + r)
                    ctx.stroke()
                }
            }

            // barre: the fret where the outermost played strings share the lowest fret
            var barre = diagram.shape ? diagram.shape.barre : null
            var barreFrom = -1, barreTo = -1
            if (barre) {
                for (var k = 0; k < diagram.strings; k++) {
                    if (data[k] !== barre) continue
                    if (barreFrom < 0) barreFrom = k
                    barreTo = k
                }
                if (barreTo > barreFrom) {
                    var x1 = Math.min(toX(barreFrom), toX(barreTo))
                    var x2 = Math.max(toX(barreFrom), toX(barreTo))
                    var radius = diagram.dotRadius * 1.05
                    var cy = toY(barre)
                    ctx.fillStyle = diagram.dotColor
                    ctx.beginPath()
                    ctx.moveTo(x1, cy - radius)
                    ctx.lineTo(x2, cy - radius)
                    ctx.arc(x2, cy, radius, -Math.PI / 2, Math.PI / 2)
                    ctx.lineTo(x1, cy + radius)
                    ctx.arc(x1, cy, radius, Math.PI / 2, -Math.PI / 2)
                    ctx.fill()
                    if (diagram.numbered) {
                        ctx.fillStyle = diagram.dotTextColor
                        ctx.font = "bold " + Math.round(radius * 1.3) + "px sans-serif"
                        ctx.textAlign = "center"
                        ctx.textBaseline = "middle"
                        ctx.fillText("1", (x1 + x2) / 2, cy)
                    }
                }
            }

            // dots (the strings inside a barre are part of the bar)
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            for (var d = 0; d < diagram.strings; d++) {
                var value = data[d]
                if (value <= 0) continue
                var relative = value - diagram.base
                if (relative < 0 || relative >= diagram.fretSpan) continue
                if (barre && value === barre && barreTo > barreFrom && d >= barreFrom && d <= barreTo) continue
                ctx.fillStyle = diagram.dotColor
                ctx.beginPath()
                ctx.arc(toX(d), toY(value), diagram.dotRadius, 0, Math.PI * 2)
                ctx.fill()
                var finger = diagram.fingers[d]
                if (diagram.numbered && finger > 0) {
                    ctx.fillStyle = diagram.dotTextColor
                    ctx.font = "bold " + Math.round(diagram.dotRadius * 1.35) + "px sans-serif"
                    ctx.fillText(String(finger), toX(d), toY(value))
                }
            }

            // base fret number when the shape sits up the neck
            if (!diagram.showNut && diagram.base > 1) {
                ctx.fillStyle = diagram.lineColor
                ctx.font = Math.round(diagram.markerHeight * 0.9) + "px sans-serif"
                ctx.textAlign = diagram.mirrored ? "left" : "right"
                ctx.fillText(String(diagram.base),
                             diagram.mirrored ? left + gw + diagram.pad * 0.5 : left - diagram.pad * 0.5,
                             top + diagram.fretGap * 0.5)
            }
        }
    }
}
