// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

.pragma library

// Fitting a tablature staff onto a narrow popup. A staff written for a wide
// page is cut at its bar lines into as many shorter staves as needed; each one
// keeps the string labels and is closed with a bar line, so it still reads as
// music.

// Columns where every string has a bar line: the places a staff may be cut.
function barColumns(rows) {
    var width = 0, i;
    for (i = 0; i < rows.length; i++) width = Math.max(width, rows[i].length);
    var cuts = [];
    for (var col = 0; col < width; col++) {
        var all = true;
        for (i = 0; i < rows.length && all; i++) all = rows[i].charAt(col) === "|";
        if (all) cuts.push(col);
    }
    return cuts;
}

// `staff` is {labels, rows} with rows that begin at the first bar line.
// `columns` is how many characters of music fit beside the labels.
function reflowStaff(staff, columns) {
    var rows = staff.rows;
    var width = 0, i;
    for (i = 0; i < rows.length; i++) width = Math.max(width, rows[i].length);
    var fit = Math.max(8, Math.floor(columns));
    if (width <= fit) return [staff];

    // Where a piece may end: each bar line every string shares, and the end of
    // the staff itself (a tab need not close with a bar). The first piece always
    // begins at column 0, so nothing before the first bar line is lost.
    var bars = barColumns(rows).filter(function (col) { return col > 0; });
    var bounds = [0].concat(bars);
    if (bounds[bounds.length - 1] < width - 1) bounds.push(width - 1);
    var spans = [];
    if (bars.length > 0) {
        // Greedy: take bars until the next one would overflow.
        var start = 0;
        var last = 0;
        for (var c = 1; c < bounds.length; c++) {
            if (bounds[c] - start + 1 > fit && last > start) {
                spans.push([start, last]);
                start = last;
            }
            last = bounds[c];
        }
        spans.push([start, last]);
    } else {
        // No bar lines to respect: cut by width. Each piece gets a bar line at
        // both ends below, so it carries two characters fewer.
        var step = fit - 2;
        for (var from = 0; from < width; from += step) spans.push([from, Math.min(width - 1, from + step - 1)]);
    }

    return spans.map(function (span) {
        return {
            labels: staff.labels,
            rows: rows.map(function (row) {
                var piece = row.substring(span[0], span[1] + 1);
                if (piece.charAt(0) !== "|") piece = "|" + piece;
                if (piece.charAt(piece.length - 1) !== "|") piece += "|";
                return piece;
            })
        };
    });
}
