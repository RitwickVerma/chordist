// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick
import org.kde.kirigami as Kirigami
import "../js/util.js" as Util

// The facts a guitarist wants before playing a note: key, capo (and the capo
// that would make it easy), tuning, difficulty, tempo, how well loved the tab is.
Flow {
    id: strip

    property var applet

    readonly property var meta: applet ? applet.chartMeta : ({})
    readonly property var key: applet ? applet.keyInfo : null
    readonly property var advice: applet ? applet.capoAdvice : null
    readonly property var tuning: meta.tuning || ({})
    readonly property var tuningNotes: tuning.notes || []
    readonly property bool standardTuning: tuningNotes.length === 0 || tuningNotes.join(" ") === "E A D G B E"
    readonly property string difficulty: meta.difficulty || ""

    visible: !!(applet && applet.chordsAvailable)
    spacing: Kirigami.Units.smallSpacing

    InfoChip {
        visible: !!strip.key
        text: strip.key ? i18n("Key %1", strip.key.name) : ""
        tip: strip.key ? (strip.key.source === "tab" ? i18n("The key the tab states") : i18n("Worked out from the chords")) : ""
    }
    InfoChip {
        visible: !!(strip.applet && strip.applet.capo > 0)
        text: strip.applet ? i18n("Capo %1", strip.applet.capo) : ""
        tip: i18n("Shapes below are played with the capo on this fret")
    }
    // The capo calculator's suggestion: one click applies it.
    InfoChip {
        visible: !!strip.advice
        interactive: true
        highlighted: true
        icon.name: "tools-wizard"
        text: strip.advice ? i18n("Easier: capo %1 → %2", strip.advice.capo,
                                  strip.advice.shapes.slice(0, 4).join(" ")) : ""
        tip: i18n("Click to use this capo. These are the shapes it leaves you with.")
        onClicked: strip.applet.capo = strip.advice.capo
    }
    InfoChip {
        visible: !strip.standardTuning
        text: i18n("Tuning %1", strip.tuningNotes.join(" "))
        tip: strip.tuning.name ? strip.tuning.name : ""
        highlighted: true
    }
    InfoChip {
        visible: strip.difficulty.length > 0
        text: strip.difficulty.charAt(0).toUpperCase() + strip.difficulty.slice(1)
        tip: i18n("Difficulty, as rated on Ultimate Guitar")
    }
    InfoChip {
        visible: !!meta.bpm
        text: i18n("♩ %1 bpm", meta.bpm)
        tip: i18n("Tempo from the strumming pattern")
    }
    InfoChip {
        visible: !!(meta.rating && meta.votes)
        opacity: 0.7
        text: meta.rating ? "★ " + Number(meta.rating).toFixed(1) + " · " + Util.compactCount(meta.votes) : ""
        tip: meta.views ? i18n("%1 views, %2 favourites", Util.compactCount(meta.views), Util.compactCount(meta.favorites)) : ""
    }
    InfoChip {
        visible: !!(strip.applet && strip.applet.chartKind === "tab")
        text: i18n("Tablature")
    }
}
