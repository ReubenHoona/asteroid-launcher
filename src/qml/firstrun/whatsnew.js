/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/*
 * What's new after an update (setup-wizard-15, CR-42): eos-update writes
 * /org/asteroidos/eos-update/whatsnew-version (s), whatsnew-notes (s, pages
 * split at "|", each "Headline: text") and whatsnew-pending (b, true until the
 * launcher's splash was shown) once a new version confirmed itself. The rules of
 * Settings' whatsnew.js (its What's new row shows the same pages). Pure functions
 * (tests/qml/tst_whatsnew.qml).
 */

// stock SysUI (fractions.xml, dimens.xml): the splash title 10 % from the top, 12 % from
// the sides; the pages 12 % from the top, 5.2 % from the sides, the headline 12 dp over the
// text, the text 4.16 % in from the page, the Next and Back buttons 52 dp, 4 dp apart
var LAYOUT = {
    splashTop: 0.10, splashSide: 0.12, pageTop: 0.12, pageSide: 0.052, subtextSide: 0.0416,
    headlineGapDp: 12, buttonDp: 52, edgeSpacingDp: 4
}

function text(v) {
    return v === undefined || v === null ? "" : String(v).trim()
}

/* The pages: [{ headline, text }], blank pages dropped; the headline is what
 * comes before the first ":" (none: the whole page is text). */
function pages(notes) {
    var out = []
    var parts = text(notes).split("|")
    for (var i = 0; i < parts.length; i++) {
        var p = parts[i].trim()
        if (p === "")
            continue
        var cut = p.indexOf(":")
        if (cut > 0)
            out.push({ headline: p.substring(0, cut).trim(), text: p.substring(cut + 1).trim() })
        else
            out.push({ headline: "", text: p })
    }
    return out
}

function isTrue(v) {
    return v === true || v === "true"
}

/* The splash is due: an update said so (pending) and it has pages to show. */
function due(pending, notes) {
    return isTrue(pending) && pages(notes).length > 0
}
