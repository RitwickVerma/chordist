import QtQuick
import org.kde.kirigami as Kirigami
import "../js/tab.js" as Tab
import "../js/util.js" as Util

// One staff of tablature, re-flowed at its bar lines so it fits the width of the
// popup instead of running off the edge.
Column {
    id: staffView

    property var staff
    property font font
    // Width of one character of `font`, measured by the owner.
    property real charWidth: 8
    property color bodyColor: Kirigami.Theme.textColor
    property color accentColor: Kirigami.Theme.highlightColor

    spacing: Kirigami.Units.smallSpacing

    // Room for the string label that precedes every row.
    readonly property int columns: Math.floor(width / Math.max(1, charWidth)) - 1
    readonly property var pieces: staff ? Tab.reflowStaff(staff, columns) : []

    Repeater {
        model: staffView.pieces
        delegate: Text {
            required property var modelData
            width: staffView.width
            font: staffView.font
            textFormat: Text.RichText
            wrapMode: Text.NoWrap
            clip: true
            text: Util.staffHtml(modelData.labels, modelData.rows,
                                 Util.colorHex(staffView.bodyColor), Util.colorHex(staffView.accentColor),
                                 Util.colorHex(Kirigami.ColorUtils.linearInterpolation(staffView.bodyColor, Kirigami.Theme.backgroundColor, 0.5)))
            Accessible.role: Accessible.StaticText
            Accessible.name: i18n("Tablature staff")
        }
    }
}
