// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import assert from "node:assert/strict";
import { test } from "node:test";
import { load } from "./load.mjs";

const U = load("util.js");

test("time formats minutes and hours", () => {
    assert.equal(U.time(0), "0:00");
    assert.equal(U.time(65.9), "1:05");
    assert.equal(U.time(3725), "1:02:05");
    assert.equal(U.time(-3), "0:00");
    assert.equal(U.time(NaN), "0:00");
});

test("escapeHtml neutralises markup in lyrics", () => {
    assert.equal(U.escapeHtml("<b>&</b>"), "&lt;b&gt;&amp;&lt;/b&gt;");
    assert.equal(U.escapeHtml(null), "");
});

test("normalize keeps Latin and Devanagari, drops the rest", () => {
    assert.equal(U.normalize("  Hello,   World!! "), "hello world");
    assert.equal(U.normalize("तुम हो!"), "तुम हो");
});

test("compactCount abbreviates view counts", () => {
    assert.equal(U.compactCount(950), "950");
    assert.equal(U.compactCount(1234), "1.2k");
    assert.equal(U.compactCount(919678), "920k");
    assert.equal(U.compactCount(19041965), "19M");
    assert.equal(U.compactCount(null), "");
});

test("staffHtml escapes rows and colours fret numbers", () => {
    const html = U.staffHtml(["e", "B"], ["|-0-12-|", "|-<-|"], "#111", "#f00", "#999");
    assert.ok(html.includes('<span style="color:#f00">12</span>'));
    assert.ok(html.includes("&lt;") && !html.includes("<-"));
    assert.ok(html.includes("white-space:pre"));
});

test("hasDevanagari", () => {
    assert.equal(U.hasDevanagari("तुम"), true);
    assert.equal(U.hasDevanagari("tum"), false);
});
