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

    var cuts = barColumns(rows);
    var spans = [];
    if (cuts.length >= 2) {
        // Greedy: take bars until the next one would overflow.
        var start = cuts[0];
        var last = start;
        for (var c = 1; c < cuts.length; c++) {
            if (cuts[c] - start + 1 > fit && last > start) {
                spans.push([start, last]);
                start = last;
            }
            last = cuts[c];
        }
        spans.push([start, last]);
        // Music after the final bar line (a tab with no closing bar).
        if (last < width - 1) spans[spans.length - 1][1] = width - 1;
    } else {
        // No bar lines to respect: cut at the width, leaving a one-column overlap.
        for (var from = 0; from < width; from += fit) spans.push([from, Math.min(width - 1, from + fit - 1)]);
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

// The widest a staff gets once reflowed: used to size the view and to tell a
// reader how much of a long staff there is.
function staffWidth(staff) {
    var width = 0;
    for (var i = 0; i < staff.rows.length; i++) width = Math.max(width, staff.rows[i].length);
    return width;
}
