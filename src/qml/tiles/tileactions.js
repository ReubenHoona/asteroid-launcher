/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/*
 * The actions of the Assistant tile (W3-launcher-tiles-content-a): the chips
 * the user chose, each a query the assistant runs (AssistantTileEditingActivity,
 * qva.java). Stored as a dconf string list, /org/asteroidos/assistant/tile-actions.
 * Pure functions.
 */

// unset: the three chips the tile always had; "no actions" is stored as ["@none"]
var DEFAULT_MARK = "@default"
var NONE_MARK = "@none"
// chips kept (the tile shows the first two; stock keeps more than it shows)
var MAX_ACTIONS = 5
// the tile shows two chips and the mic (tile_suggestion_chip_min_height 52 dp)
var SHOWN = 2

function same(a, b) {
    return String(a).trim().toLowerCase() === String(b).trim().toLowerCase()
}

/* The list to show: the stored value, else the defaults (unset or the
 * default mark), none for the none mark; blanks and repeats dropped. */
function parse(value, defaults) {
    if (value === undefined || value === null || typeof value.length !== "number" || typeof value === "string")
        return defaults.slice()
    if (value.length === 0)
        return defaults.slice()
    if (value.length === 1 && value[0] === DEFAULT_MARK)
        return defaults.slice()
    var out = []
    for (var i = 0; i < value.length; i++) {
        var t = String(value[i]).trim()
        if (t === "" || t === NONE_MARK || t === DEFAULT_MARK)
            continue
        var dup = false
        for (var j = 0; j < out.length; j++)
            if (same(out[j], t))
                dup = true
        if (!dup)
            out.push(t)
    }
    return out
}

// what goes into dconf
function toStore(list) {
    return list.length === 0 ? [NONE_MARK] : list.slice()
}

/* Add a chip (the newest first, so it shows; the oldest beyond MAX_ACTIONS
 * goes). Returns { ok, reason, list }: reason "empty" or "exists"
 * (tile_chip_already_exits). */
function add(list, text) {
    var t = String(text).trim()
    if (t === "")
        return { ok: false, reason: "empty", list: list }
    for (var i = 0; i < list.length; i++)
        if (same(list[i], t))
            return { ok: false, reason: "exists", list: list }
    return { ok: true, reason: "", list: [t].concat(list).slice(0, MAX_ACTIONS) }
}

function remove(list, text) {
    return list.filter(function (t) { return !same(t, text) })
}

// the chips the tile draws
function shown(list) {
    return list.slice(0, SHOWN)
}

/* The icon of a chip: the defaults' own, a generic one for the rest. The
 * ids and the English words are the defaults' (AssistantTile.suggestions). */
function iconFor(text, defaults) {
    for (var i = 0; i < defaults.length; i++)
        if (same(defaults[i].text, text))
            return defaults[i].icon
    return ""
}
