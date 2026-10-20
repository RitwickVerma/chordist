import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// The song's sections as chips: click to jump there, and loop the one you are
// struggling with until your fingers know it.
RowLayout {
    id: bar

    property var applet
    // Off while another tab is showing.
    property bool active: true

    readonly property var spans: applet ? applet.spans : []
    readonly property var current: applet ? applet.activeSpan : null
    readonly property var loop: applet ? applet.loopSpan : null

    visible: bar.active && spans.length >= 2
    spacing: Kirigami.Units.smallSpacing

    Flickable {
        id: flick
        Layout.fillWidth: true
        Layout.preferredHeight: row.implicitHeight
        contentWidth: row.implicitWidth
        contentHeight: row.implicitHeight
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        // Keep the section being played in view.
        Connections {
            target: bar.applet
            function onActiveSpanChanged() {
                var span = bar.current
                if (!span) return
                for (var i = 0; i < repeater.count; i++) {
                    const chip = repeater.itemAt(i) as Chip
                    if (chip && chip.payload.row === span.row) {
                        flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width,
                            chip.x - (flick.width - chip.width) / 2))
                        break
                    }
                }
            }
        }

        Row {
            id: row
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                id: repeater
                model: bar.spans
                delegate: Chip {
                    id: chip
                    required property var modelData
                    readonly property var span: modelData
                    payload: modelData
                    interactive: true
                    highlighted: !!(bar.current && bar.current.row === span.row)
                    icon: bar.loop && bar.loop.start === span.start ? "media-playlist-repeat" : ""
                    text: span.name.length > 18 ? span.name.substring(0, 17) + "…" : span.name
                    tip: i18n("Jump to %1", span.name)
                    onClicked: {
                        // While looping, picking another section moves the loop there.
                        if (bar.loop) bar.applet.loopSection(span)
                        bar.applet.jumpToSection(span)
                    }
                }
            }
        }
    }

    ToolbarButton {
        icon.name: "media-playlist-repeat"
        checkable: true
        checked: !!bar.loop
        enabled: !!(bar.loop || bar.current)
        tip: bar.loop ? i18n("Stop looping %1", bar.loop.name)
            : (bar.current ? i18n("Loop %1 until you have it", bar.current.name) : i18n("Loop the current section"))
        onClicked: bar.applet.toggleLoopHere()
    }
}
