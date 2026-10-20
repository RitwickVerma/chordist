// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

.pragma library

function time(seconds) {
    if (!seconds || seconds < 0 || !isFinite(seconds)) return "0:00"
    var total = Math.floor(seconds)
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var secs = total % 60
    var mm = (hours > 0 && minutes < 10 ? "0" : "") + minutes
    var ss = (secs < 10 ? "0" : "") + secs
    return hours > 0 ? hours + ":" + mm + ":" + ss : mm + ":" + ss
}

function escapeHtml(text) {
    return String(text === undefined || text === null ? "" : text)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
}

function normalize(text) {
    // Devanagari is kept as well as Latin, so lyrics and charts match whether
    // or not they have been romanised.
    return String(text || "").toLowerCase()
        .replace(/[^a-z0-9\u00c0-\u024f\u0900-\u097f ]+/g, " ")
        .replace(/\s+/g, " ")
        .trim()
}

function colorHex(color) {
    function channel(value) {
        var text = Math.round(Math.max(0, Math.min(1, value)) * 255).toString(16)
        return text.length < 2 ? "0" + text : text
    }
    return "#" + channel(color.r) + channel(color.g) + channel(color.b)
}


// 919678 -> "920k", 19041965 -> "19M": view and favourite counts at a glance.
function compactCount(value) {
    if (value === null || value === undefined || !isFinite(value)) return ""
    function scaled(unit) {
        // One decimal below ten, none above; a count that rounds up to the next
        // unit (999999 -> "1000k") is promoted ("1M").
        var n = value / unit
        return n >= 10 ? Math.round(n) : Math.round(n * 10) / 10
    }
    if (value >= 999500) return scaled(1000000) + "M"
    if (value >= 1000) {
        var thousands = scaled(1000)
        return thousands >= 1000 ? "1M" : thousands + "k"
    }
    return String(Math.round(value))
}

// True when text is written in Devanagari (so the romanise switch means something).
function hasDevanagari(text) {
    return /[\u0900-\u097f]/.test(String(text || ""))
}

// One staff of tablature as rich text: string labels dimmed, fret numbers in
// the accent colour, everything else in the body colour. Rows are escaped, and
// spacing is preserved so the bars still line up in a monospace font.
function staffHtml(labels, rows, bodyColor, accentColor, dimColor) {
    var lines = []
    for (var i = 0; i < rows.length; i++) {
        var row = escapeHtml(rows[i]).replace(/(\d+)/g, '<span style="color:' + accentColor + '">$1</span>')
        lines.push('<span style="color:' + dimColor + '">' + escapeHtml(labels[i] || "") + '</span>'
                   + '<span style="color:' + bodyColor + '">' + row + '</span>')
    }
    return '<span style="white-space:pre">' + lines.join("<br>") + "</span>"
}
