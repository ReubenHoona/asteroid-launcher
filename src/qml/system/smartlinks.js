/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* Smart links in a notification's text (system-dialogs-misc-04, -05): stock's
 * TextClassifier finds phone numbers and addresses in the body of an open card and underlines
 * them (pwi.java:648-720). A number opens a menu (Message, Call), an address opens the map
 * directly; web addresses and e-mail addresses are not links. The detection is a small
 * heuristic of our own (stock's classifier is not available): nothing is sent anywhere, and
 * no number or address is ever logged. */

// a phone number: an optional +, then 7 to 15 digits with spaces, dashes, dots and brackets
var MIN_DIGITS = 7
var MAX_DIGITS = 15

var STREET_WORDS = "Street|St|Road|Rd|Avenue|Ave|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Place|Pl|Way|Terrace|Highway|Hwy|Crescent|Cres|Parade|Square|Close"
// 12 Example Street, 221B Baker Street: a house number, one to three capitalised words, a street word
var ADDRESS = new RegExp("(^|[^\\w])(\\d{1,5}[A-Za-z]?\\s+(?:[A-Z][\\w'’-]*\\.?\\s+){1,3}(?:" + STREET_WORDS + ")\\b\\.?)", "g")
// after the start, white space or one of : ; , ( > " ' (not a path, an address or a parameter: / @ = . -)
var NUMBER = /(^|[\s:;,(>"'])(\+?\(?\d[\d\s().-]{4,}\d)(?![\w])/g

function digitsOf(s) { return s.replace(/\D/g, "") }

// not a phone number: a date (2026-11-14, 14.11.2026, 11/14/2026), a decimal, a plain run of digits
// with a decimal point or a time range
function looksLikeNumber(s) {
    var d = digitsOf(s)
    if (d.length < MIN_DIGITS || d.length > MAX_DIGITS)
        return false
    if (/^\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}$/.test(s))
        return false
    if (/^\d+\.\d+$/.test(s))
        return false
    // a long run of dots as separators reads as a version or an amount
    if ((s.match(/\./g) || []).length > 3)
        return false
    // unbalanced brackets
    if ((s.match(/\(/g) || []).length !== (s.match(/\)/g) || []).length)
        return false
    return true
}

/* The links of a text: [{ start, end, kind: "phone" | "address", value }] in text order, no overlap.
 * A phone's value is "+" and the digits (the number to dial); an address' value is its text. */
function find(text) {
    var out = []
    if (typeof text !== "string" || text.length === 0)
        return out
    var m
    NUMBER.lastIndex = 0
    while ((m = NUMBER.exec(text)) !== null) {
        var s = m[2]
        if (!looksLikeNumber(s))
            continue
        var start = m.index + m[1].length
        out.push({ start: start, end: start + s.length, kind: "phone",
                   value: (s.charAt(0) === "+" ? "+" : "") + digitsOf(s), shown: s.trim() })
    }
    ADDRESS.lastIndex = 0
    while ((m = ADDRESS.exec(text)) !== null) {
        var a = m[2]
        var as = m.index + m[1].length
        var ae = as + a.length
        var clash = false
        for (var i = 0; i < out.length; i++)
            if (as < out[i].end && ae > out[i].start)
                clash = true
        if (!clash)
            out.push({ start: as, end: ae, kind: "address", value: a.replace(/\.$/, ""), shown: a })
    }
    out.sort(function (x, y) { return x.start - y.start })
    return out
}

function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

/* The text as Qt StyledText: the links underlined (<a>, drawn in the text's own colour through
 * Text.linkColor), everything else escaped, line breaks kept. href is "sl:phone:<number>" or
 * "sl:address:<encoded address>". */
function styled(text) {
    var links = find(text)
    var out = ""
    var at = 0
    for (var i = 0; i < links.length; i++) {
        var l = links[i]
        out += esc(text.substring(at, l.start)).replace(/\n/g, "<br>")
        out += "<a href=\"sl:" + l.kind + ":" + encodeURIComponent(l.value) + "\">" + esc(text.substring(l.start, l.end)) + "</a>"
        at = l.end
    }
    out += esc(text.substring(at)).replace(/\n/g, "<br>")
    return out
}

/* A link's href back to { kind, value }, null for any other link */
function parse(href) {
    var m = /^sl:(phone|address):(.*)$/.exec(String(href))
    if (!m)
        return null
    try {
        return { kind: m[1], value: decodeURIComponent(m[2]) }
    } catch (e) {
        return null
    }
}

// the number as the menu's title (stock formats it for the country; the number is shown as the
// text gave it, as "+" and the digits)
function titleOf(value) {
    return String(value)
}
