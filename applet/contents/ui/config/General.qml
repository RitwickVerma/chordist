// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Controls as QQC
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_serviceUrl: serviceUrl.text
    property alias cfg_defaultTab: defaultTab.currentValue
    property alias cfg_lyricSync: lyricSync.checked
    property alias cfg_autoScroll: autoScroll.checked
    property alias cfg_showChordDiagrams: showChordDiagrams.checked
    property alias cfg_showStage: showStage.checked
    property alias cfg_showFingerNumbers: showFingerNumbers.checked
    property alias cfg_leftHanded: leftHanded.checked
    property alias cfg_simplifyChords: simplifyChords.checked
    property alias cfg_scrollSpeed: scrollSpeed.value
    property alias cfg_compactScroll: compactScroll.checked
    property alias cfg_compactMode: compactMode.currentValue
    property alias cfg_middleClickAction: middleClickAction.currentValue
    property alias cfg_fontSizeOffset: fontSizeOffset.value
    property alias cfg_backgroundOpacity: backgroundOpacity.value
    property alias cfg_openAsWindow: openAsWindow.checked
    property alias cfg_animateIcon: animateIcon.checked

    Kirigami.FormLayout {
        QQC.TextField {
            id: serviceUrl
            Kirigami.FormData.label: i18n("Service address:")
            placeholderText: "http://127.0.0.1:8788"
        }

        QQC.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Behaviour")
        }

        QQC.ComboBox {
            id: defaultTab
            Kirigami.FormData.label: i18n("Open on:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("Lyrics"), value: "lyrics" },
                { text: i18n("Chords"), value: "chords" }
            ]
        }

        QQC.CheckBox {
            id: lyricSync
            Kirigami.FormData.label: i18n("Lyric sync:")
            text: i18n("Highlight the line being sung")
        }

        QQC.CheckBox {
            id: autoScroll
            Kirigami.FormData.label: i18n("Auto-scroll:")
            text: i18n("Follow the song while it plays")
        }

        QQC.CheckBox {
            id: showChordDiagrams
            Kirigami.FormData.label: i18n("Chord diagrams:")
            text: i18n("Show fingering diagrams above the chart")
        }

        QQC.CheckBox {
            id: showStage
            Kirigami.FormData.label: i18n("Chord stage:")
            text: i18n("Show the chord you are on, and the next one, large")
        }

        QQC.CheckBox {
            id: showFingerNumbers
            Kirigami.FormData.label: i18n("Finger numbers:")
            text: i18n("Number the fingers on the big diagram")
        }

        QQC.CheckBox {
            id: leftHanded
            Kirigami.FormData.label: i18n("Left-handed:")
            text: i18n("Mirror the chord diagrams")
        }

        QQC.CheckBox {
            id: simplifyChords
            Kirigami.FormData.label: i18n("Simplify chords:")
            text: i18n("Reduce complex chords to easy major/minor shapes")
        }

        QQC.SpinBox {
            id: scrollSpeed
            Kirigami.FormData.label: i18n("Auto-scroll speed:")
            from: 1
            to: 10
        }

        QQC.CheckBox {
            id: openAsWindow
            Kirigami.FormData.label: i18n("Floating window:")
            text: i18n("Open as a separate window (on top under X11; under Wayland use Keep Above in its title-bar menu)")
        }

        QQC.SpinBox {
            id: backgroundOpacity
            Kirigami.FormData.label: i18n("Background opacity:")
            from: 0
            to: 100
        }

        QQC.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Panel")
        }

        QQC.CheckBox {
            id: compactScroll
            Kirigami.FormData.label: i18n("Panel text:")
            text: i18n("Scroll long titles")
        }

        QQC.CheckBox {
            id: animateIcon
            Kirigami.FormData.label: i18n("Panel icon:")
            text: i18n("Rock the guitar while a song with lyrics or chords plays")
        }

        QQC.ComboBox {
            id: compactMode
            Kirigami.FormData.label: i18n("Panel widget:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("Icon only"), value: "icon" },
                { text: i18n("Icon and title"), value: "title" },
                { text: i18n("Art, title and artist"), value: "full" },
                { text: i18n("Icon and the chord to play now"), value: "chord" }
            ]
        }

        QQC.ComboBox {
            id: middleClickAction
            Kirigami.FormData.label: i18n("Middle-click:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("Play / Pause"), value: "playpause" },
                { text: i18n("Next track"), value: "next" },
                { text: i18n("Previous track"), value: "previous" },
                { text: i18n("Nothing"), value: "none" }
            ]
        }

        QQC.SpinBox {
            id: fontSizeOffset
            Kirigami.FormData.label: i18n("Text size offset:")
            from: -4
            to: 10
        }
    }
}
