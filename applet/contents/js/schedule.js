.pragma library

// Timing for the song views: which chart row or lyric line the song has
// reached, which chord is sounding now and which comes next, and where each
// section starts and ends. Everything is a pure function of its arguments so it
// can be tested without a compositor and called from any view.

// Last index whose value is <= x in an ascending array, or -1.
function lastAtOrBefore(values, x) {
    var low = 0, high = values.length - 1, found = -1;
    while (low <= high) {
        var mid = (low + high) >> 1;
        if (values[mid] <= x) { found = mid; low = mid + 1; }
        else high = mid - 1;
    }
    return found;
}

// Row times with their gaps and any backward step removed: a time can never be
// earlier than the one before it, so a mis-aligned row cannot make the
// highlight jump back up the page. Rows without a time (sections) stay null.
function monotonic(times) {
    var out = [], floor = 0;
    for (var i = 0; i < times.length; i++) {
        var t = times[i];
        if (t === null || t === undefined) { out.push(null); continue; }
        floor = Math.max(floor, t);
        out.push(floor);
    }
    return out;
}

// A time for every chart line, evenly spread over the track: the fallback for
// when there are no timed lyrics to align against, so the chart still walks.
function fillEvenly(rows, length) {
    var times = rows.map(function () { return null; });
    if (!(length > 0)) return times;
    var total = 0, seen = 0, i;
    for (i = 0; i < rows.length; i++) if (rows[i].kind === "line") total++;
    for (i = 0; i < rows.length; i++) {
        if (rows[i].kind !== "line") continue;
        times[i] = total > 1 ? length * seen / total : 0;
        seen++;
    }
    return times;
}

// The row times to use: what the service aligned (one per line row, in order)
// laid onto the row list, else an even spread.
function rowTimes(rows, aligned, length) {
    if (aligned && aligned.length) {
        var times = rows.map(function () { return null; });
        var next = 0;
        for (var i = 0; i < rows.length && next < aligned.length; i++) {
            if (rows[i].kind !== "line") continue;
            var value = aligned[next++];
            if (value !== null && value !== undefined) times[i] = value;
        }
        return monotonic(times);
    }
    return fillEvenly(rows, length);
}

// Index of the row being sung at `position`, or -1 before the first one.
function rowAt(times, position, lag) {
    var stamps = [], indexes = [];
    for (var i = 0; i < times.length; i++) {
        if (times[i] === null || times[i] === undefined) continue;
        stamps.push(times[i]);
        indexes.push(i);
    }
    var hit = lastAtOrBefore(stamps, position - (lag || 0));
    return hit < 0 ? -1 : indexes[hit];
}

// Index of the lyric line being sung. Blank timed lines are instrumental gaps:
// the highlight stays on the line that was actually sung.
function lyricAt(lines, position, lag) {
    var stamps = [], indexes = [];
    for (var i = 0; i < lines.length; i++) {
        var t = lines[i].t;
        if (t === null || t === undefined) continue;
        stamps.push(t);
        indexes.push(i);
    }
    var hit = lastAtOrBefore(stamps, position - (lag || 0));
    while (hit >= 0 && !(lines[indexes[hit]].text || "").length) hit--;
    return hit < 0 ? -1 : indexes[hit];
}

// Every chord in the chart as a timed event. A chord sits at the same fraction
// along its row's duration as its first letter sits along the lyric, so a chord
// change in the middle of a line lands in the middle of the line. An
// instrumental row spreads its chords evenly. Tab (monospace) rows carry no
// chords and are skipped. `end` closes the last row.
function chordEvents(rows, times, end) {
    var events = [];
    var lineRows = [];
    var i;
    for (i = 0; i < rows.length; i++) {
        if (rows[i].kind === "line" && times[i] !== null && times[i] !== undefined) lineRows.push(i);
    }
    for (var n = 0; n < lineRows.length; n++) {
        var index = lineRows[n];
        var row = rows[index];
        var chords = row.chords || [];
        if (!chords.length) continue;
        var start = times[index];
        var stop = n + 1 < lineRows.length ? times[lineRows[n + 1]] : Math.max(end || 0, start);
        var span = Math.max(0, stop - start);
        var length = Math.max(1, (row.lyric || "").length);
        for (var c = 0; c < chords.length; c++) {
            var fraction = row.instrumental ? c / chords.length : Math.min(0.92, chords[c].pos / length * 0.92);
            events.push({ t: start + span * fraction, row: index, chord: c, name: chords[c].name });
        }
    }
    events.sort(function (a, b) { return a.t - b.t; });
    return events;
}

// What is sounding at `position`: the event, the next one with a *different*
// chord, and how many seconds until it. Repeats of the same chord are skipped so
// "next" always means "the next change".
function chordAt(events, position, lag) {
    if (!events.length) return null;
    var stamps = events.map(function (e) { return e.t; });
    var index = lastAtOrBefore(stamps, position - (lag || 0));
    var current = index < 0 ? null : events[index];
    var from = index < 0 ? 0 : index + 1;
    var upcoming = null;
    for (var i = from; i < events.length; i++) {
        if (!current || events[i].name !== current.name) { upcoming = events[i]; break; }
    }
    return {
        index: index,
        current: current,
        next: upcoming,
        nextIn: upcoming ? Math.max(0, upcoming.t - position) : null
    };
}

// Where each named section starts and ends, for jumping and looping. A section
// begins at its first timed line and ends where the next one begins (or at
// `end`). Sections with no timed line are left out.
function sectionSpans(rows, times, end) {
    var spans = [];
    for (var i = 0; i < rows.length; i++) {
        if (rows[i].kind !== "section") continue;
        var start = null;
        for (var j = i + 1; j < rows.length && rows[j].kind !== "section"; j++) {
            if (times[j] !== null && times[j] !== undefined) { start = times[j]; break; }
        }
        if (start === null) continue;
        spans.push({ row: i, name: rows[i].name, start: start, end: null });
    }
    for (var k = 0; k < spans.length; k++) {
        spans[k].end = k + 1 < spans.length ? spans[k + 1].start : Math.max(end || 0, spans[k].start);
    }
    return spans;
}

// The span containing `position`, or null.
function spanAt(spans, position) {
    for (var i = spans.length - 1; i >= 0; i--) {
        if (position >= spans[i].start) return position < spans[i].end ? spans[i] : null;
    }
    return null;
}
