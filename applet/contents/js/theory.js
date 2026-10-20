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
        if (i > 0 && end > col) col = end + 1;
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
    var quality = "maj";
    if (/^(m(?!aj)|min|-)/i.test(rest) && !/^M/.test(rest)) quality = "min";
    if (/^(dim|o|°)/i.test(rest)) quality = "dim";
    if (/^(aug|\+)/i.test(rest)) quality = "aug";
    if (/^m7b5|^ø/i.test(rest)) quality = "hdim";
    var sus = /sus2/.test(rest) ? 2 : (/sus/.test(rest) ? 4 : 0);
    return { name: name, root: PC[main.root], rootName: main.root, rest: rest, bass: bass, quality: quality, sus: sus };
}

// Semitones above the root for each chord tone, in the order they stack.
function chordIntervals(parsed) {
    if (!parsed) return [];
    var rest = parsed.rest;
    var third = parsed.quality === "min" || parsed.quality === "dim" || parsed.quality === "hdim" ? 3 : 4;
    var fifth = parsed.quality === "dim" || parsed.quality === "hdim" ? 6 : (parsed.quality === "aug" ? 8 : 7);
    var tones = [0];
    if (/^5$/.test(rest)) return [0, 7];
    if (parsed.sus === 2) tones.push(2);
    else if (parsed.sus === 4) tones.push(5);
    else tones.push(third);
    tones.push(fifth);
    var seventh = null;
    if (/maj7|maj9|maj11|maj13|M7|Δ/.test(rest)) seventh = 11;
    else if (parsed.quality === "dim" && /7/.test(rest)) seventh = 9;
    else if (/7|9|11|13/.test(rest) && !/add/.test(rest)) seventh = 10;
    if (seventh === null && parsed.quality === "hdim") seventh = 10;
    if (/6/.test(rest) && !/6\/9|69/.test(rest) && seventh === null) tones.push(9);
    if (seventh !== null) tones.push(seventh);
    if (/9|add9|add2|6\/9|69/.test(rest) && parsed.sus !== 2) tones.push(2);
    if (/11|add11/.test(rest)) tones.push(5);
    if (/13/.test(rest)) tones.push(9);
    if (/b5|-5/.test(rest) && parsed.quality !== "dim" && parsed.quality !== "hdim") tones[2] = 6;
    if (/#5|\+5/.test(rest) && parsed.quality !== "aug") tones[2] = 8;
    return tones;
}

// The notes of a chord, spelled the way its own root is written.
function chordTones(name) {
    var parsed = parseChord(name);
    if (!parsed) return [];
    var table = parsed.rootName.indexOf("b") >= 0 ? FLAT : SHARP;
    var seen = {}, out = [];
    chordIntervals(parsed).forEach(function (interval) {
        var note = table[(parsed.root + interval) % 12];
        if (!seen[note]) { seen[note] = true; out.push(note); }
    });
    return out;
}

// ---------------------------------------------------------------- key detection

// Keys are spelled the way guitarists and tab sites write them: Bb and Eb major
// but F# and B, Gm and Cm but G#m and D#m.
var MAJOR_KEY_NAMES = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"];
var MINOR_KEY_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "Bb", "B"];
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
// earns a bonus, as does opening or closing on it, which is what separates a
// major key from its relative minor. Returns null when nothing parses.
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
    var base = 2.5;
    for (var i = 0; i < spellings.length; i++) {
        var known = OPEN_COST[spellings[i] + parsed.rest];
        if (known !== undefined) { base = known; break; }
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
