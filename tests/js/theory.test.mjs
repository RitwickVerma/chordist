import assert from "node:assert/strict";
import { test } from "node:test";
import { load } from "./load.mjs";

const T = load("theory.js");

test("transposing keeps flats flat and sharps sharp", () => {
    assert.equal(T.transposeChord("F#m7/B", 2), "G#m7/C#");
    assert.equal(T.transposeChord("Bb", 2), "C");
    assert.equal(T.transposeChord("Ebmaj7", 1), "Emaj7");
    assert.equal(T.transposeChord("C", -1), "B");
    assert.equal(T.transposeChord("N.C.", 5), "N.C.");
    assert.equal(T.transposeChord("Am", 12), "Am");
});

test("easy chords drop extensions but keep the slash bass", () => {
    assert.equal(T.simplifyChord("Cmaj7"), "C");
    assert.equal(T.simplifyChord("Am7"), "Am");
    assert.equal(T.simplifyChord("Dsus4"), "D");
    assert.equal(T.simplifyChord("F#m7b5"), "F#m");
    assert.equal(T.simplifyChord("G/B"), "G/B");
    assert.equal(T.simplifyChord("Dmaj"), "D");
});

test("chord row is padded to the lyric columns", () => {
    const row = T.chordLine([{ pos: 0, name: "Am" }, { pos: 10, name: "F" }], 0, false);
    assert.equal(row, "Am        F");
    assert.equal(T.chordLine([{ pos: 0, name: "Am" }, { pos: 1, name: "F" }], 0, false), "Am F");
    assert.equal(T.chordLine([], 0, false), "");
});

test("chord tones are spelled from the chord's own root", () => {
    assert.deepEqual(T.chordTones("C"), ["C", "E", "G"]);
    assert.deepEqual(T.chordTones("Am7"), ["A", "C", "E", "G"]);
    assert.deepEqual(T.chordTones("Bbmaj7"), ["Bb", "D", "F", "A"]);
    assert.deepEqual(T.chordTones("Dsus4"), ["D", "G", "A"]);
    assert.deepEqual(T.chordTones("Dsus2"), ["D", "E", "A"]);
    assert.deepEqual(T.chordTones("Bdim"), ["B", "D", "F"]);
    assert.deepEqual(T.chordTones("Caug"), ["C", "E", "G#"]);
    assert.deepEqual(T.chordTones("G7"), ["G", "B", "D", "F"]);
    assert.deepEqual(T.chordTones("Cadd9"), ["C", "E", "G", "D"]);
    assert.deepEqual(T.chordTones("E5"), ["E", "B"]);
    assert.deepEqual(T.chordTones("Bm7b5"), ["B", "D", "F", "A"]);
    assert.deepEqual(T.chordTones("N.C."), []);
    assert.deepEqual(T.chordTones("hello"), []);
});

test("key detection tells a major key from its relative minor", () => {
    assert.equal(T.detectKey(["C", "G", "Am", "F"]).name, "C");
    assert.equal(T.detectKey(["Am", "F", "C", "G"]).name, "Am");
    assert.equal(T.detectKey(["Em", "G", "D", "A7sus4"]).tonic, 4);
    assert.equal(T.detectKey(["D", "A", "Bm", "G"]).name, "D");
    assert.equal(T.detectKey([]), null);
    assert.equal(T.detectKey(["N.C."]), null);
});

test("roman numerals describe the chord's job in the key", () => {
    assert.equal(T.romanNumeral("Am", 0, "major"), "vi");
    assert.equal(T.romanNumeral("F", 0, "major"), "IV");
    assert.equal(T.romanNumeral("G7", 0, "major"), "V7");
    assert.equal(T.romanNumeral("Bb", 0, "major"), "bVII");
    assert.equal(T.romanNumeral("Bdim", 0, "major"), "vii°");
    assert.equal(T.romanNumeral("Cmaj7", 0, "major"), "Imaj7");
    assert.equal(T.romanNumeral("N.C.", 0, "major"), null);
});

test("shape cost ranks open shapes below barres", () => {
    assert.equal(T.shapeCost("G"), 0);
    assert.ok(T.shapeCost("F") > T.shapeCost("Am"));
    assert.ok(T.shapeCost("Bm") > T.shapeCost("F"));
    assert.ok(T.shapeCost("G/B") > T.shapeCost("G"));
    assert.equal(T.shapeCost("N.C."), 0);
    // different spellings of the same shape cost the same
    assert.equal(T.shapeCost("Bb"), T.shapeCost("A#"));
});

test("capo suggestion finds the easy shapes", () => {
    // Bb F Gm Eb is all barres at capo 0; a capo on 3 turns it into G D Em C.
    const hit = T.suggestCapo(["Bb", "F", "Gm", "Eb"]);
    assert.equal(hit.capo, 3);
    assert.deepEqual(hit.shapes, ["G", "D", "Em", "C"]);
    assert.ok(hit.cost < hit.capo0Cost);
});

test("capo suggestion leaves an already easy song alone", () => {
    const hit = T.suggestCapo(["G", "C", "D", "Em"]);
    assert.equal(hit.capo, 0);
    assert.equal(T.suggestCapo([]), null);
});

test("occurrence weights steer the capo choice", () => {
    const names = ["Bm", "G"];
    const heavyBm = T.suggestCapo(names, { Bm: 50, G: 1 });
    assert.equal(T.transposeChord("Bm", -heavyBm.capo), heavyBm.shapes[0]);
    assert.ok(T.shapeCost(heavyBm.shapes[0]) <= T.shapeCost("Bm"));
});

test("chart helpers count and order chords", () => {
    const sections = [{ lines: [{ chords: [{ name: "C" }, { name: "G" }] }, { chords: [{ name: "C" }] }] }];
    assert.deepEqual(T.orderedNames(sections), ["C", "G"]);
    assert.deepEqual(JSON.parse(JSON.stringify(T.chordWeights(sections))), { C: 2, G: 1 });
});

test("uniqueNames applies transpose and easy mode", () => {
    const sections = [{ lines: [{ chords: [{ name: "Am7" }, { name: "Cmaj7" }, { name: "Am7" }] }] }];
    assert.deepEqual(T.uniqueNames(sections, 2, false), ["Bm7", "Dmaj7"]);
    assert.deepEqual(T.uniqueNames(sections, 0, true), ["Am", "C"]);
});

test("chord columns push a chord right when the previous one is still there", () => {
    const cols = T.chordColumns([{ pos: 0, name: "Am7" }, { pos: 1, name: "F" }, { pos: 10, name: "C" }], 0, false);
    assert.deepEqual(cols.map((c) => [c.col, c.len, c.name]), [[0, 3, "Am7"], [4, 1, "F"], [10, 1, "C"]]);
    // the row text and the columns agree, so a highlight lands under the right letters
    const row = T.chordLine([{ pos: 0, name: "Am7" }, { pos: 1, name: "F" }, { pos: 10, name: "C" }], 0, false);
    for (const c of cols) assert.equal(row.substr(c.col, c.len), c.name);
});

test("capoCost agrees with suggestCapo", () => {
    const names = ["Bb", "F", "Gm", "Eb"];
    const best = T.suggestCapo(names);
    assert.equal(T.capoCost(names, null, best.capo), best.cost);
    assert.equal(T.capoCost(names, null, 0), best.capo0Cost);
});

test("detected keys are spelled like a guitarist writes them", () => {
    assert.equal(T.detectKey(["Bb", "F", "Gm", "Eb"]).name, "Bb");
    assert.equal(T.detectKey(["Eb", "Bb", "Cm", "Ab"]).name, "Eb");
    assert.equal(T.detectKey(["A", "E", "F#m", "D", "A"]).name, "A");
    assert.equal(T.detectKey(["Gm", "Eb", "Bb", "F"]).name, "Bb");
    assert.equal(T.detectKey(["F#m", "D", "E", "F#m"]).name, "F#m");
});
