import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Inline "paste your own chart" editor, used by the empty states.
ColumnLayout {
    id: sheet

    property var applet
    property string hint: i18n("Paste a chord sheet or lyrics, or the address of an Ultimate Guitar tab. Plain text, ChordPro and Ultimate Guitar formats all work.")

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: sheet.hint
        wrapMode: Text.WordWrap
        opacity: 0.7
    }

    QQC.TextArea {
        id: input
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 5
        placeholderText: "Am        F\nWhen you were here before\nC         G\nand I wish I was special\n\n(or an Ultimate Guitar address)"
        wrapMode: QQC.TextArea.Wrap
        selectByMouse: true
        font: Kirigami.Theme.fixedWidthFont
        background: Rectangle {
            radius: Kirigami.Units.smallSpacing / 2
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Button {
            text: i18n("Paste from clipboard")
            icon.name: "edit-paste"
            onClicked: {
                input.forceActiveFocus()
                input.paste()
            }
        }
        PlasmaComponents3.Button {
            text: /^https?:\/\/\S+$/.test(input.text.trim()) ? i18n("Use this tab") : i18n("Save for this track")
            icon.name: "document-save"
            enabled: input.text.trim().length > 0
            onClicked: {
                if (sheet.applet) sheet.applet.submitPaste(input.text)
                input.text = ""
            }
        }
    }
}
