import assert from "node:assert/strict";
import { test } from "node:test";
import { load } from "./load.mjs";

const S = load("schedule.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

const rows = [
    { kind: "section", name: "Verse" },
    { kind: "line", lyric: "hello there my friend", chords: [{ pos: 0, name: "C" }, { pos: 12, name: "G" }] },
    { kind: "line", lyric: "it has been so long", chords: [{ pos: 0, name: "Am" }] },
    { kind: "section", name: "Chorus" },
    { kind: "line", lyric: "", instrumental: true, chords: [{ pos: 0, name: "F" }, { pos: 1, name: "C" }] },
    { kind: "line", lyric: "sing along now", chords: [{ pos: 0, name: "F" }] },
];

test("aligned times are laid onto line rows only", () => {
    const times = plain(S.rowTimes(rows, [10, 20, 30, 40], 100));
    assert.deepEqual(times, [null, 10, 20, null, 30, 40]);
});

test("a time can never go backwards", () => {
    assert.deepEqual(plain(S.rowTimes(rows, [10, 5, 30, 25], 100)), [null, 10, 10, null, 30, 30]);
});

test("short aligned lists leave the rest unplaced; nulls stay null", () => {
    assert.deepEqual(plain(S.rowTimes(rows, [10, null], 100)), [null, 10, null, null, null, null]);
});

test("with nothing aligned the chart is spread evenly over the track", () => {
    const times = plain(S.rowTimes(rows, null, 80));
    assert.deepEqual(times, [null, 0, 20, null, 40, 60]);
    assert.deepEqual(plain(S.rowTimes(rows, null, 0)), rows.map(() => null));
});

test("rowAt follows playback and respects the sync lag", () => {
    const times = S.rowTimes(rows, [10, 20, 30, 40], 100);
    assert.equal(S.rowAt(times, 5, 0.25), -1);
    assert.equal(S.rowAt(times, 10.2, 0.25), -1);   // a line never lights before its time
    assert.equal(S.rowAt(times, 10.3, 0.25), 1);
    assert.equal(S.rowAt(times, 25, 0.25), 2);
    assert.equal(S.rowAt(times, 999, 0.25), 5);
});

test("lyricAt skips blank gap lines and untimed lines", () => {
    const lines = [{ t: 1, text: "a" }, { t: 5, text: "" }, { t: 8, text: "b" }, { t: null, text: "x" }];
    assert.equal(S.lyricAt(lines, 6, 0), 0);        // the gap keeps the highlight on "a"
    assert.equal(S.lyricAt(lines, 9, 0), 2);
    assert.equal(S.lyricAt(lines, 0.5, 0), -1);
    assert.equal(S.lyricAt([], 3, 0), -1);
});

test("chord events sit proportionally along their line", () => {
    const events = plain(S.chordEvents(rows, S.rowTimes(rows, [10, 20, 30, 40], 100), 100));
    const names = events.map((e) => e.name);
    assert.deepEqual(names, ["C", "G", "Am", "F", "C", "F"]);
    assert.equal(events[0].t, 10);
    assert.ok(events[1].t > 10 && events[1].t < 20);              // G mid-line
    assert.ok(Math.abs(events[3].t - 30) < 1e-9 && events[4].t > 30 && events[4].t < 40); // instrumental spreads evenly
    for (let i = 1; i < events.length; i++) assert.ok(events[i].t >= events[i - 1].t);
});

test("chordAt gives the sounding chord, the next change and the countdown", () => {
    const events = S.chordEvents(rows, S.rowTimes(rows, [10, 20, 30, 40], 100), 100);
    const before = S.chordAt(events, 2, 0);
    assert.equal(before.current, null);
    assert.equal(before.next.name, "C");
    const mid = S.chordAt(events, 11, 0);
    assert.equal(mid.current.name, "C");
    assert.equal(mid.next.name, "G");
    assert.ok(mid.nextIn > 0);
    assert.equal(S.chordAt([], 5, 0), null);
});

test("next means the next change, not a repeat of the same chord", () => {
    const repeats = [
        { kind: "line", lyric: "ab", chords: [{ pos: 0, name: "C" }] },
        { kind: "line", lyric: "cd", chords: [{ pos: 0, name: "C" }] },
        { kind: "line", lyric: "ef", chords: [{ pos: 0, name: "G" }] },
    ];
    const events = S.chordEvents(repeats, [0, 10, 20], 30);
    const at = S.chordAt(events, 1, 0);
    assert.equal(at.next.name, "G");
    assert.equal(at.nextIn, 19);
});

test("tab rows carry no chords and produce no events", () => {
    const tab = [{ kind: "line", lyric: "e|--0--", chords: [], mono: true }];
    assert.deepEqual(plain(S.chordEvents(tab, [0], 10)), []);
});

test("section spans cover the song without gaps", () => {
    const spans = plain(S.sectionSpans(rows, S.rowTimes(rows, [10, 20, 30, 40], 100), 100));
    assert.deepEqual(spans.map((s) => [s.name, s.start, s.end]), [["Verse", 10, 30], ["Chorus", 30, 100]]);
    assert.equal(S.spanAt(spans, 12).name, "Verse");
    assert.equal(S.spanAt(spans, 30).name, "Chorus");
    assert.equal(S.spanAt(spans, 5), null);
});

test("sections with no timed line are left out", () => {
    const empty = [{ kind: "section", name: "Ghost" }, { kind: "section", name: "Real" }, { kind: "line", lyric: "x", chords: [] }];
    assert.deepEqual(plain(S.sectionSpans(empty, [null, null, 5], 50)).map((s) => s.name), ["Real"]);
});
