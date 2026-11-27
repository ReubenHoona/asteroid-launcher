/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The face catalogue against stock (AUDIT-72 area A, round R5):
 *  - A-19: the 51 colours of all_colorway.xml (the 35 and the 16 two-tone ones of RWF glo.java:191-206),
 *    the colourway roles (gdo.java), Large Scale on Spring with its bulb in the second tone
 *    (preview_accessible.png), Concentric's text colours equal to the roles.
 * qmltestrunner under qemu-aarch64 with the image rootfs (offscreen, software Qt Quick), run in place
 * (the faces of ../../src).
 */

import QtQuick
import QtTest
import "../../src/eoskit/facekit.js" as Kit
import "../../src/eoskit/concentric.js" as C

Item {
    id: top
    width: 384
    height: 384

    // what the launcher gives a face (FaceLayer's context)
    property var wallClock: ({ time: new Date(2026, 10, 24, 10, 9, 30) })
    property var use12H: ({ value: true })
    property bool displayAmbient: false

    Rectangle { anchors.fill: parent; color: "black" }
    Loader { id: ld; anchors.fill: parent }

    TestCase {
        id: tc
        name: "FaceCatalogue"
        when: windowShown

        function findAll(item, name, out) {
            out = out || []
            if (!item)
                return out
            if (item.objectName === name)
                out.push(item)
            var d = item.children
            if (d)
                for (var i = 0; i < d.length; i++)
                    findAll(d[i], name, out)
            return out
        }
        function slotOf(f, id) {
            return findAll(f, "eosComplication").filter(function (s) { return s.slotId === id })[0]
        }
        function load(file, style) {
            ld.source = ""
            ld.source = Qt.resolvedUrl("../../src/watchfaces/" + file + ".qml")
            tryCompare(ld, "status", Loader.Ready, 20000)
            if (style)
                ld.item.eosStyle = style
            return ld.item
        }

        // ---- A-19: the long colour list ----
        function test_a19_all_colorway() {
            compare(Kit.ALL_COLORS.length, 51)
            compare(Kit.ALL_COLORS.slice(0, 35), Kit.accentIds())
            // all_colorway.xml: pop01 ... pop16 after the 35; the stock defaults by index
            compare(Kit.ALL_COLORS.slice(35), ["milkshake", "verbena", "salmon", "amber", "cantaloupe", "mustard",
                                               "key-lime", "spring", "avocado", "polar", "arctic", "winter",
                                               "macaron", "sunset", "seafoam", "charcoal"])
            compare(Kit.ALL_COLORS[42], "spring")          // Large Scale, index 42
            compare(Kit.ALL_COLORS[50], "charcoal")        // Abstract, index 50
            compare(Kit.ALL_COLORS[5], "pomelo")           // Big Time, index 5
            compare(Kit.ALL_COLORS[28], "ocean")           // Analog, index 28
            var o = Kit.colorOption("spring", Kit.ALL_COLORS)
            compare(o.values.length, 51)
            compare(o.labels[42], "Spring")
            compare(o.labels[41], "Key Lime")
            compare(o.labels[34], "Bubble Gum")
            compare(Kit.optionValue([o], {}, "color"), "spring")
            compare(Kit.optionValue([o], { color: "charcoal" }, "color"), "charcoal")
            compare(Kit.optionValue([o], { color: "nope" }, "color"), "spring")
            // the 35-colour list is unchanged; a two-tone id is not in it
            var four = Kit.colorOption("cloud")
            compare(four.values.length, 35)
            compare(Kit.optionValue([four], { color: "spring" }, "color"), "cloud")
        }
        function test_a19_roles() {
            // glo.java pop08 Spring: d(id, #C7FF81, #80FDD5): b the first, c (and d, the dark fallback) the second,
            // e (light) falls back to b
            compare(Kit.accentColor("spring"), "#c7ff81")
            compare(Kit.colorRole("spring", "b"), "#c7ff81")
            compare(Kit.colorRole("spring", "c"), "#80fdd5")
            compare(Kit.colorRole("spring", "d"), "#80fdd5")
            compare(Kit.colorRole("spring", "e"), "#c7ff81")
            compare(Kit.colorRole("charcoal", "c"), "#a0a3ab")
            compare(Kit.accentColor("charcoal"), "#616161")
            compare(Kit.colorRole("sunset", "c"), "#ffcaed")
            // the 35 keep their ramps (glo.java A06 Pomelo: b #FFA49F, c #F8908B, d #D6524E, e #FFCBC9)
            compare(Kit.colorRole("pomelo", "b"), "#ffa49f")
            compare(Kit.colorRole("pomelo", "c"), "#f8908b")
            compare(Kit.colorRole("pomelo", "d"), "#d6524e")
            compare(Kit.colorRole("pomelo", "e"), "#ffcbc9")
            compare(Kit.colorRole("nope", "c", "cloud"), "#ffffff")
            compare(Kit.accentColor("nope", "cloud"), "#e4e4e4")
            // every one of the 51 has all four roles as #rrggbb
            for (var i = 0; i < Kit.ALL_COLORS.length; i++)
                for (var r = 0; r < 4; r++)
                    verify(/^#[0-9a-f]{6}$/.test(Kit.colorRole(Kit.ALL_COLORS[i], "bcde"[r])),
                           Kit.ALL_COLORS[i] + " " + "bcde"[r])
            // Concentric's dial colours are the roles' text colours (A13 Jade, A37 Lemongrass included)
            var ids = Kit.accentIds()
            for (i = 0; i < ids.length; i++)
                compare(C.textColor(ids[i]), Kit.colorRole(ids[i], "c"), ids[i])
            compare(C.textColor("jade"), "#b0f1d9")
            compare(C.textColor("lemongrass"), "#e8febb")
        }
        function test_a19_large_scale() {
            var f = load("022-large")
            compare(f.opt("color"), "spring")
            compare(f.eosOptions[0].values.length, 51)
            compare(String(f.accent), "#c7ff81")
            compare(String(f.accent2), "#80fdd5")
            // the time in the first tone, the bulb in the second (preview_accessible.png)
            compare(String(findAll(f, "eosTime")[0].color), "#c7ff81")
            compare(String(findAll(f, "eosTime")[0].hourItem.interactiveItem.color), "#c7ff81")
            compare(String(slotOf(f, "bulb").tint), "#80fdd5")
            // a colour of the 35: the bulb in its text shade
            f.eosStyle = { color: "pomelo" }
            compare(String(f.accent), "#ffa49f")
            compare(String(slotOf(f, "bulb").tint), "#f8908b")
            // an older favourite's Spearmint stays
            f.eosStyle = { color: "spearmint" }
            compare(f.opt("color"), "spearmint")
            ld.source = ""
        }
    }
}
