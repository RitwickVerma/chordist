.pragma library

// Client-side chord transposition for the Lyricist widget.
// Chord shapes come from the service; this only rewrites note names.

var SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
var FLAT  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];

var PC = {
    "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4,
    "Fb": 4, "E#": 5, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
    "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11, "Cb": 11, "B#": 0
};

function isNoChord(name) {
    return !name || /^\s*(n\.?c\.?|x|\/)\s*$/i.test(name);
}

// Split "F#m7/B" style names into a root plus everything after it.
function splitRoot(name) {
    if (!name) return null;
    var match = /^\s*([A-Ga-g][#b]?)(.*)$/.exec(name);
    if (!match) return null;
    var root = match[1];
    root = root.charAt(0).toUpperCase() + root.slice(1);
    return { root: root, rest: match[2] };
}

function transposeNote(note, semitones, table) {
    if (PC[note] === undefined) return note;
    var index = ((PC[note] + semitones) % 12 + 12) % 12;
    return table[index];
}

function transposeChord(name, semitones) {
    if (isNoChord(name) || !semitones) return name;
    var parts = name.split("/");
    var main = splitRoot(parts[0]);
    if (!main) return name;
    var table = main.root.indexOf("b") >= 0 ? FLAT : SHARP;
    var out = transposeNote(main.root, semitones, table) + main.rest;
    for (var i = 1; i < parts.length; i++) {
        var bass = splitRoot(parts[i]);
        if (bass) out += "/" + transposeNote(bass.root, semitones, table) + bass.rest;
        else out += "/" + parts[i];
    }
    return out;
}

// Reduce a chord to an easy, open shape. Transpose first, then simplify, so a
// barred or extended chord becomes the plain major/minor triad a beginner can
// finger: Cmaj7 -> C, Am7 -> Am, Dsus4 -> D, F#m7 -> F#m. A slash bass is kept,
// because it is part of the voicing rather than an extension.
function simplifyChord(name) {
    if (isNoChord(name)) return name;
    var parts = name.split("/");
    var main = splitRoot(parts[0]);
    if (!main) return name;
    var minor = /^\s*(m(?!aj)|min|dim)/i.test(main.rest);
    var out = main.root + (minor ? "m" : "");
    for (var i = 1; i < parts.length; i++) out += "/" + parts[i];
    return out;
}

// Transpose, then optionally simplify, in the one place both the chart rows
// and the diagram strip look through.
function chordName(raw, semitones, simplify) {
    var name = transposeChord(raw, semitones);
    return simplify ? simplifyChord(name) : name;
}

// Build the space-padded chord row that sits above one lyric line.
// Assumes a monospace font, so character offset == column offset.
function chordLine(chords, semitones, simplify) {
    if (!chords || !chords.length) return "";
    var out = "";
    for (var i = 0; i < chords.length; i++) {
        var name = chordName(chords[i].name, semitones, simplify);
        var target = chords[i].pos;
        if (out.length > target) {
            if (out.charAt(out.length - 1) !== " ") out += " ";
        } else {
            while (out.length < target) out += " ";
        }
        out += name;
    }
    return out.replace(/\s+$/, "");
}

function uniqueNames(sections, semitones, simplify) {
    var seen = {}, out = [];
    if (!sections) return out;
    for (var i = 0; i < sections.length; i++) {
        var lines = sections[i].lines || [];
        for (var j = 0; j < lines.length; j++) {
            var chords = lines[j].chords || [];
            for (var k = 0; k < chords.length; k++) {
                var name = chordName(chords[k].name, semitones, simplify);
                if (!seen[name]) { seen[name] = true; out.push(name); }
            }
        }
    }
    return out;
}
