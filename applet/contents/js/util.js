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

// Levenshtein distance, capped: only 0, 1 or "more than 1" are ever needed.
function editDistance(a, b) {
    if (a === b) return 0
    if (Math.abs(a.length - b.length) > 1) return 2
    var previous = []
    for (var j = 0; j <= b.length; j++) previous[j] = j
    for (var i = 1; i <= a.length; i++) {
        var current = [i]
        for (var k = 1; k <= b.length; k++) {
            var cost = a.charAt(i - 1) === b.charAt(k - 1) ? 0 : 1
            current[k] = Math.min(previous[k] + 1, current[k - 1] + 1, previous[k - 1] + cost)
        }
        previous = current
    }
    return previous[b.length]
}

// True when two normalised words are the same word despite spelling drift:
// kahan/kahaan, vo/voh, chand/chaand, badalata/badalta, asaman/aasman.
function tokenMatches(a, b) {
    if (!a || !b) return false
    if (a === b) return true
    if (a.length >= 3 && b.indexOf(a) === 0) return true
    if (b.length >= 3 && a.indexOf(b) === 0) return true
    return editDistance(a, b) <= 1
}

function colorHex(color) {
    function channel(value) {
        var text = Math.round(Math.max(0, Math.min(1, value)) * 255).toString(16)
        return text.length < 2 ? "0" + text : text
    }
    return "#" + channel(color.r) + channel(color.g) + channel(color.b)
}

