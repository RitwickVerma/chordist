// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import assert from "node:assert/strict";
import { test } from "node:test";
import { load } from "./load.mjs";

const Tab = load("tab.js");
const plain = (value) => JSON.parse(JSON.stringify(value));
const labels = ["e", "B", "G", "D", "A", "E"];
const bar = (fill) => `|${fill.repeat(7)}`;
const staff = (bars) => ({ labels, rows: labels.map((_, i) => bars.map((b) => bar(String(i === 2 ? b : "-"))).join("") + "|") });

test("a staff that fits is left alone", () => {
    const s = staff([1, 2]);
    assert.deepEqual(plain(Tab.reflowStaff(s, 40)), plain([s]));
});

test("a wide staff is cut at bar lines and every piece is closed", () => {
    const s = staff([1, 2, 3, 4]);          // 4 bars of 8 columns + closing bar = 33 wide
    const pieces = plain(Tab.reflowStaff(s, 17));
    assert.ok(pieces.length >= 2);
    for (const piece of pieces) {
        for (const row of piece.rows) {
            assert.ok(row.startsWith("|") && row.endsWith("|"));
            assert.ok(row.length <= 17, `${row.length} > 17`);
        }
        assert.equal(new Set(piece.rows.map((r) => r.length)).size, 1);
    }
    // no music is lost: the fret numbers on the G string all survive, in order
    const frets = pieces.map((p) => p.rows[2]).join("").replace(/[-|]/g, "");
    assert.equal(frets, "1111111" + "2222222" + "3333333" + "4444444");
});

test("a staff with no bar lines is cut by width", () => {
    const row = "-".repeat(50);
    const pieces = plain(Tab.reflowStaff({ labels: ["e", "B"], rows: [row, row] }, 20));
    assert.ok(pieces.length >= 3);
    assert.ok(pieces.every((p) => p.rows[0].length <= 22));
});

test("a single bar wider than the view is still returned, not dropped", () => {
    const pieces = plain(Tab.reflowStaff({ labels: ["e", "B"], rows: ["|" + "-".repeat(30) + "|", "|" + "-".repeat(30) + "|"] }, 10));
    assert.equal(pieces.length >= 1, true);
    assert.ok(pieces.every((p) => p.rows.length === 2));
});

test("music before the first bar line is kept", () => {
    const row = (frets) => "--" + frets + "|--5--|--6--|--7--|";
    const staff = { labels: ["e", "B"], rows: [row("1-"), row("--")] };
    const pieces = plain(Tab.reflowStaff(staff, 12));
    const kept = pieces.map((p) => p.rows[0]).join("").replace(/[-|]/g, "");
    assert.equal(kept, "1" + "5" + "6" + "7");
});

test("a repeat-sign staff (rows start with a colon) loses nothing", () => {
    const row = (digit) => ":--" + digit + "--|--" + digit + "--|--" + digit + "--|";
    const staff = { labels: ["e", "B"], rows: [row(1), row(2)] };
    const pieces = plain(Tab.reflowStaff(staff, 10));
    assert.equal(pieces.map((p) => p.rows[0]).join("").replace(/[-|:]/g, ""), "111");
});

test("every piece fits the room it was given, bars included", () => {
    for (const cols of [8, 10, 17, 33]) {
        const barless = "-".repeat(61);
        const barred = ("|" + "-".repeat(9)).repeat(7) + "|";
        for (const row of [barless, barred]) {
            const pieces = plain(Tab.reflowStaff({ labels: ["e", "B"], rows: [row, row] }, cols));
            for (const piece of pieces) {
                for (const r of piece.rows) assert.ok(r.length <= Math.max(cols, 11), `${cols}: ${r.length}`);
            }
        }
    }
});
