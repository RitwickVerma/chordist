// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

.pragma library

// Chord theory for the Chordist widget, all client-side so it answers instantly
// when transpose or capo move: transposition, chord tones, key detection with
// roman numerals, and the capo calculator. Fingerings come from the service.

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

// How a chord root is written, the way guitarists and tab sites write it: Bb and
// Eb major but F# and B, Gm and Cm but G#m and D#m. Used for transposed chords
// and for the names of detected keys, so the two always agree.
var MAJOR_KEY_NAMES = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"];
var MINOR_KEY_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "Bb", "B"];

// The quality of the chord whose text after the root is `rest`: "maj", "min",
// "dim", "hdim" (half-diminished), "aug". Only a lowercase m means minor: a
// capital M is a major seventh (CM7), as in "maj".
function qualityOf(rest) {
    if (/^(m7b5|\u00f8)/.test(rest)) return "hdim";
    if (/^(dim|o|\u00b0)/i.test(rest)) return "dim";
    if (/^(aug|\+)/i.test(rest)) return "aug";
    if (/^(min|-)/i.test(rest) || /^m(?!aj)/.test(rest)) return "min";
    return "maj";
}
function isMinorish(rest) {
    var quality = qualityOf(rest);
    return quality === "min" || quality === "dim" || quality === "hdim";
}

// A slash bass note follows its chord's spelling: sharps with a sharp root,
// flats with a flat one, and for a natural root flats only around C and F.
function spellBass(pc, mainRoot) {
    var flats = /^[A-G]b/.test(mainRoot) || mainRoot === "C" || mainRoot === "F";
    return (flats ? FLAT : SHARP)[pc];
}

function transposeChord(name, semitones) {
    if (isNoChord(name) || !semitones) return name;
    var parts = name.split("/");
    var main = splitRoot(parts[0]);
    if (!main || PC[main.root] === undefined) return name;
    var shift = function (pc) { return ((pc + semitones) % 12 + 12) % 12; };
    var names = isMinorish(main.rest) ? MINOR_KEY_NAMES : MAJOR_KEY_NAMES;
    var root = names[shift(PC[main.root])];
    var out = root + main.rest;
    for (var i = 1; i < parts.length; i++) {
        var bass = splitRoot(parts[i]);
        if (bass && PC[bass.root] !== undefined) out += "/" + spellBass(shift(PC[bass.root]), root) + bass.rest;
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
    var out = main.root + (isMinorish(main.rest) ? "m" : "");
    for (var i = 1; i < parts.length; i++) out += "/" + parts[i];
    return out;
}

// Transpose, then optionally simplify, in the one place both the chart rows
// and the diagram strip look through.
function chordName(raw, semitones, simplify) {
    var name = transposeChord(raw, semitones);
    return simplify ? simplifyChord(name) : name;
}

// Where each chord of a row sits once the row is laid out in characters:
// [{col, len, name}]. A chord wants the column of its syllable, but is pushed
// right when the one before it is still there, so names never run together.
function chordColumns(chords, semitones, simplify) {
    var out = [];
    if (!chords) return out;
    var end = 0;
    for (var i = 0; i < chords.length; i++) {
        var name = chordName(chords[i].name, semitones, simplify);
        var col = chords[i].pos;
        // Never touching the previous name: at least one space between them.
        if (i > 0 && end >= col) col = end + 1;
        out.push({ col: col, len: name.length, name: name });
        end = col + name.length;
    }
    return out;
}

// The space-padded chord row that sits above one lyric line.
// Assumes a monospace font, so character offset == column offset.
function chordLine(chords, semitones, simplify) {
    var columns = chordColumns(chords, semitones, simplify);
    var out = "";
    for (var i = 0; i < columns.length; i++) {
        while (out.length < columns[i].col) out += " ";
        out += columns[i].name;
    }
    return out;
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


// ----------------------------------------------------------------- chord anatomy

// Split a chord into the pieces theory needs: root and bass as pitch classes,
// the third's quality, and the extensions. Returns null for "N.C." and words.
function parseChord(name) {
    if (isNoChord(name)) return null;
    var halves = String(name).split("/");
    var main = splitRoot(halves[0]);
    if (!main || PC[main.root] === undefined) return null;
    var rest = main.rest;
    var bass = null;
    if (halves.length > 1) {
        var bassPart = splitRoot(halves[1]);
        if (bassPart && PC[bassPart.root] !== undefined) bass = PC[bassPart.root];
    }
    var quality = qualityOf(rest);
    var sus = /sus2/.test(rest) ? 2 : (/sus/.test(rest) ? 4 : 0);
    return { name: name, root: PC[main.root], rootName: main.root, rest: rest, bass: bass, quality: quality, sus: sus };
}

// The tones of a chord as {interval, degree}: semitones above the root, and the
// scale degree (3 = a third of some kind, 7 = a seventh) that decides which
// letter names it.
function chordDegrees(parsed) {
    var rest = parsed.rest;
    var quality = parsed.quality;
    var flatFifth = quality === "dim" || quality === "hdim";
    var out = [{ interval: 0, degree: 1 }];
    if (/^5$/.test(rest)) return out.concat([{ interval: 7, degree: 5 }]);

    if (parsed.sus === 2) out.push({ interval: 2, degree: 2 });
    else if (parsed.sus === 4) out.push({ interval: 5, degree: 4 });
    else out.push({ interval: quality === "min" || flatFifth ? 3 : 4, degree: 3 });

    var fifth = flatFifth ? 6 : (quality === "aug" ? 8 : 7);
    if (/b5|-5/.test(rest) && !flatFifth) fifth = 6;
    if (/#5|\+5/.test(rest) && quality !== "aug") fifth = 8;
    out.push({ interval: fifth, degree: 5 });

    // Altered extensions are named first and taken out, so the 9 in "7b9" is not
    // also read as a natural ninth.
    var plain = rest.replace(/[b#]9|[b#]11|[b#]13/g, "");
    var sixNine = /6\/?9/.test(plain);
    var seventh = null;
    if (/maj7|maj9|maj11|maj13|M7|\u0394/.test(plain)) seventh = 11;
    else if (quality === "dim" && /7/.test(plain)) seventh = 9;
    else if (!sixNine && /7|9|11|13/.test(plain) && !/add/.test(plain)) seventh = 10;
    if (seventh === null && quality === "hdim") seventh = 10;

    if (/6/.test(plain) && seventh === null) out.push({ interval: 9, degree: 6 });
    if (seventh !== null) out.push({ interval: seventh, degree: 7 });
    if (/b9/.test(rest)) out.push({ interval: 1, degree: 9 });
    else if (/#9/.test(rest)) out.push({ interval: 3, degree: 9 });
    else if (/9|add2/.test(plain) && parsed.sus !== 2) out.push({ interval: 2, degree: 9 });
    if (/#11/.test(rest)) out.push({ interval: 6, degree: 11 });
    else if (/11/.test(plain)) out.push({ interval: 5, degree: 11 });
    if (/b13/.test(rest)) out.push({ interval: 8, degree: 13 });
    else if (/13/.test(plain)) out.push({ interval: 9, degree: 13 });
    return out;
}

var LETTERS = ["C", "D", "E", "F", "G", "A", "B"];
var LETTER_PC = [0, 2, 4, 5, 7, 9, 11];

// One chord tone, spelled by letter: the third of Gm is the next-but-one letter,
// B, lowered to Bb. (A table of sharps would call it A#.)
function spellTone(rootName, interval, degree) {
    var letter = (LETTERS.indexOf(rootName.charAt(0)) + degree - 1) % 7;
    var target = (PC[rootName] + interval) % 12;
    var drift = ((target - LETTER_PC[letter]) % 12 + 12) % 12;
    if (drift > 6) drift -= 12;
    var mark = drift > 0 ? "#" : "b";
    var accidental = "";
    for (var i = 0; i < Math.abs(drift); i++) accidental += mark;
    return LETTERS[letter] + accidental;
}

// The notes of a chord, spelled from its own root.
function chordTones(name) {
    var parsed = parseChord(name);
    if (!parsed) return [];
    var seen = {}, out = [];
    chordDegrees(parsed).forEach(function (tone) {
        var note = spellTone(parsed.rootName, tone.interval, tone.degree);
        if (!seen[note]) { seen[note] = true; out.push(note); }
    });
    return out;
}

// ---------------------------------------------------------------- key detection

var MAJOR_SCALE = [0, 2, 4, 5, 7, 9, 11];
var MINOR_SCALE = [0, 2, 3, 5, 7, 8, 10];
// Quality of the chord built on each scale degree.
var MAJOR_DEGREES = ["maj", "min", "min", "maj", "maj", "min", "dim"];
var MINOR_DEGREES = ["min", "dim", "maj", "min", "min", "maj", "maj"];
var ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII"];

function degreeOf(pc, tonic, mode) {
    var scale = mode === "minor" ? MINOR_SCALE : MAJOR_SCALE;
    return scale.indexOf(((pc - tonic) % 12 + 12) % 12);
}

// Best-fit key for a list of chords (each counted `weights[name]` times, or
// once). A chord that is diatonic to a key scores for it; the key's tonic chord
// earns a bonus, as does the first chord (and the last *new* one: the names are
// in order of first appearance), which helps separate a major key from its
// relative minor. Returns null when nothing parses.
function detectKey(names, weights) {
    var chords = [];
    (names || []).forEach(function (name, index) {
        var parsed = parseChord(name);
        if (parsed) chords.push({ parsed: parsed, weight: (weights && weights[name]) || 1, first: index === 0, last: index === names.length - 1 });
    });
    if (!chords.length) return null;
    var best = null;
    for (var tonic = 0; tonic < 12; tonic++) {
        ["major", "minor"].forEach(function (mode) {
            var degrees = mode === "major" ? MAJOR_DEGREES : MINOR_DEGREES;
            var score = 0;
            chords.forEach(function (chord) {
                var degree = degreeOf(chord.parsed.root, tonic, mode);
                var quality = chord.parsed.quality === "hdim" ? "dim" : chord.parsed.quality;
                if (degree >= 0 && (degrees[degree] === quality || chord.parsed.sus || chord.parsed.rest === "5")) score += chord.weight;
                else if (degree >= 0) score += chord.weight * 0.3;
                else score -= chord.weight * 0.5;
                if (chord.parsed.root === tonic && quality === (mode === "major" ? "maj" : "min")) score += chord.weight * 0.6;
                if ((chord.first || chord.last) && chord.parsed.root === tonic) score += 0.8;
            });
            if (!best || score > best.score) best = { tonic: tonic, mode: mode, score: score };
        });
    }
    var names = best.mode === "minor" ? MINOR_KEY_NAMES : MAJOR_KEY_NAMES;
    return { tonic: best.tonic, mode: best.mode, name: names[best.tonic] + (best.mode === "minor" ? "m" : ""), score: best.score };
}

// "vi", "IV", "V7": a chord's function in the key. Chords outside it get an
// accidental ("bVII"); null when the chord does not parse.
function romanNumeral(name, tonic, mode) {
    var parsed = parseChord(name);
    if (!parsed || tonic === null || tonic === undefined) return null;
    var degree = degreeOf(parsed.root, tonic, mode);
    var prefix = "";
    if (degree < 0) {
        var up = degreeOf((parsed.root + 1) % 12, tonic, mode);
        if (up < 0) return null;
        degree = up;
        prefix = "b";
    }
    var numeral = ROMAN[degree];
    var lower = parsed.quality === "min" || parsed.quality === "dim" || parsed.quality === "hdim";
    var text = prefix + (lower ? numeral.toLowerCase() : numeral);
    if (parsed.quality === "dim") text += "°";
    else if (parsed.quality === "hdim") text += "ø";
    else if (parsed.quality === "aug") text += "+";
    var seventh = /maj7|M7|Δ/.test(parsed.rest) ? "maj7" : (/7/.test(parsed.rest) && parsed.quality !== "dim" && parsed.quality !== "hdim" ? "7" : "");
    return text + seventh;
}

// ------------------------------------------------------------- capo calculator

// How awkward a chord is to fret, as a beginner feels it: 0 is a comfortable
// open shape, 2.5 is a full barre. Written for the shapes people actually play
// rather than computed, because "open" is a fact about a guitar, not about
// intervals.
var OPEN_COST = {
    "C": 0, "A": 0, "G": 0, "E": 0, "D": 0, "Am": 0, "Em": 0, "Dm": 0,
    "A7": 0, "B7": 0.5, "C7": 0.5, "D7": 0, "E7": 0, "G7": 0, "Am7": 0, "Dm7": 0, "Em7": 0,
    "Cmaj7": 0, "Dmaj7": 0.5, "Amaj7": 0.5, "Emaj7": 0.5, "Fmaj7": 0.5, "Gmaj7": 0.5,
    "Asus2": 0, "Asus4": 0, "Dsus2": 0, "Dsus4": 0, "Esus4": 0, "Cadd9": 0.5, "Gadd9": 0.5, "Dadd9": 0.5,
    "E6": 0.5, "A6": 0.5, "G6": 0.5, "C6": 0.5, "Am6": 0.5, "Em6": 0.5,
    "F": 1.5, "Fm": 2, "B": 2.5, "Bm": 2
};

function shapeCost(name) {
    var parsed = parseChord(name);
    if (!parsed) return 0;
    // The same root can be spelled three ways (Bb, A#, or as written).
    var spellings = [parsed.rootName, SHARP[parsed.root], FLAT[parsed.root]];
    var lookup = function (suffix) {
        for (var i = 0; i < spellings.length; i++) {
            var known = OPEN_COST[spellings[i] + suffix];
            if (known !== undefined) return known;
        }
        return null;
    };
    var base = lookup(parsed.rest);
    if (base === null) {
        // Not a shape listed above (A7sus4, Em9): the plain chord it grows from,
        // plus a little for the extra finger, and never more than a full barre.
        var triad = lookup(isMinorish(parsed.rest) ? "m" : "");
        base = Math.min(2.5, (triad === null ? 2.5 : triad) + 0.75);
    }
    // A different bass note than the root is one more thing for the thumb.
    if (parsed.bass !== null && parsed.bass !== parsed.root) base += 0.5;
    return base;
}

// What playing these chords costs with the capo on `capo`: every chord is
// shifted down by that many frets (the shape you hold) and priced. `sounding`
// are the chords as they sound, with optional occurrence `weights`.
function capoCost(sounding, weights, capo) {
    var total = 0;
    (sounding || []).forEach(function (name) {
        if (isNoChord(name)) return;
        total += shapeCost(transposeChord(name, -capo)) * ((weights && weights[name]) || 1);
    });
    return total;
}

// The capo position that makes a song easiest to play, and the shapes it
// leaves. Ties go to the lower capo: fewer frets of squeeze for the same ease.
// `capo0Cost` is what playing with no capo would cost, so the caller can say
// whether the suggestion is worth mentioning.
function suggestCapo(sounding, weights, maxCapo) {
    var limit = maxCapo === undefined ? 7 : maxCapo;
    var names = (sounding || []).filter(function (n) { return !isNoChord(n); });
    if (!names.length) return null;
    var best = { capo: 0, cost: capoCost(names, weights, 0) };
    var plain = best.cost;
    for (var capo = 1; capo <= limit; capo++) {
        var cost = capoCost(names, weights, capo);
        if (cost < best.cost - 0.001) best = { capo: capo, cost: cost };
    }
    var shapesAt = function (c) { return names.map(function (n) { return transposeChord(n, -c); }); };
    return { capo: best.capo, cost: best.cost, shapes: shapesAt(best.capo), capo0Cost: plain, capo0Shapes: shapesAt(0) };
}

// Occurrence count per chord name across a chart, for the weighted helpers.
function chordWeights(sections) {
    var weights = {};
    (sections || []).forEach(function (section) {
        (section.lines || []).forEach(function (line) {
            (line.chords || []).forEach(function (chord) { weights[chord.name] = (weights[chord.name] || 0) + 1; });
        });
    });
    return weights;
}

// The chart's chord names in the order they first appear, untransposed.
function orderedNames(sections) {
    var seen = {}, out = [];
    (sections || []).forEach(function (section) {
        (section.lines || []).forEach(function (line) {
            (line.chords || []).forEach(function (chord) {
                if (!seen[chord.name]) { seen[chord.name] = true; out.push(chord.name); }
            });
        });
    });
    return out;
}
