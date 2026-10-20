import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// A small rounded label: "Key Am", "Capo 2", "Intermediate". Clickable when
// something listens to `clicked`.
Rectangle {
    id: chip

    property string text: ""
    property string icon: ""
    property bool highlighted: false
    property bool dim: false
    property bool interactive: false
    property string tip: ""
    // Whatever the owner wants back when this chip is found again (a section).
    property var payload: null
    signal clicked()

    implicitWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing
    radius: height / 2
    color: highlighted ? Kirigami.Theme.highlightColor
        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b,
                  mouse.containsMouse && interactive ? 0.16 : 0.09)
    opacity: dim ? 0.6 : 1
    Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: tip.length > 0 ? tip : text

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing / 2

        Kirigami.Icon {
            visible: chip.icon.length > 0
            source: chip.icon
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            color: chip.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
        }
        PlasmaComponents3.Label {
            text: chip.text
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: chip.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: chip.interactive
        hoverEnabled: true
        cursorShape: chip.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: chip.clicked()
    }
    PlasmaComponents3.ToolTip { visible: chip.tip.length > 0 && mouse.containsMouse; text: chip.tip }
}
