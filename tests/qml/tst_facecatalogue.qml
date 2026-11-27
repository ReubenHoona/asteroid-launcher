/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The face catalogue against stock (AUDIT-72 area A, round R5):
 *  - A-19: the 51 colours of all_colorway.xml (the 35 and the 16 two-tone ones of RWF glo.java:191-206),
 *    the colourway roles (gdo.java), Large Scale on Spring with its bulb in the second tone
 *    (preview_accessible.png), Concentric's text colours equal to the roles;
 *  - A-14: the complication chooser lists only the sources whose stock data types the slot takes
 *    (faceeditor.js SOURCE_TYPES, slotTypes, accepts; EditorProviderList.openFor with the slot).
 * qmltestrunner under qemu-aarch64 with the image rootfs (offscreen, software Qt Quick), run in place
 * (the faces of ../../src).
 */

import QtQuick
import QtTest
import "../../src/eoskit/facekit.js" as Kit
import "../../src/eoskit/concentric.js" as C
import "../../src/qml/complications/faceeditor.js" as FE
import "../../src/qml/complications"

Item {
    id: top
    width: 384
    height: 384

    // what the launcher gives a face (FaceLayer's context)
    property var wallClock: ({ time: new Date(2026, 10, 24, 10, 9, 30) })
    property var use12H: ({ value: true })
    property bool displayAmbient: false
    // what the editor's rows read (the launcher's locale manager)
    property var localeManager: ({ changesObserver: "" })

    Rectangle { anchors.fill: parent; color: "black" }
    Loader { id: ld; anchors.fill: parent }
    // the editor's chooser sheet (A-14), with a stand-in for the home screen's sources
    EditorProviderList { id: chooserSheet; sources: fakeSources }

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

        // ---- A-14: the chooser lists only the sources a slot can show ----
        // the source ids of ComplicationSources.qml (its `all` and `parameterised` lists), read from the file
        function sourceIds() {
            var x = new XMLHttpRequest()
            x.open("GET", Qt.resolvedUrl("../../src/qml/complications/ComplicationSources.qml"), false)
            x.send()
            var t = x.responseText
            function list(name) {
                var m = new RegExp("readonly property var " + name + ": \\[([^\\]]*)\\]").exec(t)
                return m[1].match(/"[a-z]+"/g).map(function (s) { return s.slice(1, -1) })
            }
            return { all: list("all"), parameterised: list("parameterised") }
        }
        function chosen(types) {
            var ids = sourceIds()
            return FE.chooserOrder(ids.all.concat(ids.parameterised), function (id) { return id }, types)
        }
        function test_a14_every_source_has_types() {
            var ids = sourceIds()
            verify(ids.all.length > 20)
            compare(ids.parameterised, ["worldclock", "countdown", "app"])
            var every = ids.all.concat(ids.parameterised)
            for (var i = 0; i < every.length; i++)
                if (every[i] !== "empty")
                    verify(FE.SOURCE_TYPES.hasOwnProperty(every[i]), every[i])
            // every shape the faces use has its types
            var shapes = ["bulb", "circle", "text", "long", "arc", "ring"]
            for (i = 0; i < shapes.length; i++)
                verify(FE.slotTypes(shapes[i]) !== null, shapes[i])
            compare(FE.slotTypes("nope"), null)
            compare(FE.slotTypes("text", ["SHORT_TEXT"]), ["SHORT_TEXT"])
        }
        function test_a14_slot_kinds() {
            var all = chosen(null)
            // a bulb takes every source of ours (each has a bulb type: short text, a value, an icon or an image)
            compare(chosen(FE.slotTypes("bulb")), all)
            compare(chosen(FE.slotTypes("circle")), all)
            // Utility's long slot: LONG_TEXT only
            compare(chosen(FE.slotTypes("long")).slice().sort(),
                    ["app", "assistant", "battery", "countdown", "empty", "media", "moon", "nextevent",
                     "phonebattery", "weather"])
            // Track's ring: RANGED_VALUE only
            compare(chosen(FE.slotTypes("ring")).slice().sort(),
                    ["aqi", "azm", "battery", "calories", "distance", "empty", "floors", "heartrate", "phonebattery",
                     "precipitation", "steps", "uv", "weather"])
            // an edge arc: no icon-only or image-only source
            var arc = chosen(FE.slotTypes("arc"))
            for (var k = 0, no = ["app", "assistant", "media"]; k < no.length; k++)
                compare(arc.indexOf(no[k]), -1, "arc " + no[k])
            verify(arc.indexOf("health") > 0 && arc.indexOf("notifications") > 0 && arc.indexOf("exercisedays") > 0)
            // a line: no image-only or long-only source; the icon ones stay
            var line = chosen(FE.slotTypes("text"))
            compare(line.indexOf("app"), -1)
            compare(line.indexOf("media"), -1)
            verify(line.indexOf("assistant") > 0 && line.indexOf("worldclock") > 0)
            // Large Scale's top line: SHORT_TEXT only
            var top = chosen(["SHORT_TEXT"])
            compare(top.indexOf("exercisedays"), -1)
            compare(top.indexOf("app"), -1)
            verify(top.indexOf("date") > 0)
            // Empty first, the rest alphabetical, whatever the filter
            compare(top[0], "empty")
            compare(FE.accepts("app:asteroid-music", FE.slotTypes("bulb")), true)
            compare(FE.accepts("app:asteroid-music", FE.slotTypes("text")), false)
            compare(FE.accepts("worldclock:+0530", FE.slotTypes("long")), false)
            compare(FE.accepts("empty", ["LONG_TEXT"]), true)
        }
        // the chooser sheet of the editor, with a stand-in for the home screen's sources
        QtObject {
            id: fakeSources
            property var all: tc.sourceIds().all
            property var parameterised: tc.sourceIds().parameterised
            function name(id) { return id }
            function info(id) { return { icon: "" } }
        }
        function test_a14_chooser_sheet() {
            var sheet = chooserSheet
            // the long slot of a face: only long-text sources; it opens on the slot's source
            sheet.openFor("nextevent", { shape: "long" })
            verify(sheet.order.indexOf("steps") < 0)
            compare(sheet.order[0], "empty")
            compare(sheet.current, sheet.order.indexOf("nextevent"))
            // a ring slot whose old source is not listed opens on the first row
            sheet.closeNow()
            sheet.openFor("date", { shape: "ring" })
            compare(sheet.order.indexOf("date"), -1)
            compare(sheet.current, 0)
            // a slot that names its own types
            sheet.closeNow()
            sheet.openFor("date", { shape: "text", supportedTypes: ["SHORT_TEXT"] })
            compare(sheet.order.indexOf("exercisedays"), -1)
            verify(sheet.order.indexOf("date") > 0)
            // no slot (an older caller): every source
            sheet.closeNow()
            sheet.openFor("steps")
            compare(sheet.order.length, fakeSources.all.length + fakeSources.parameterised.length)
            sheet.closeNow()
        }
        function test_a14_faces_slots() {
            // every slot of the eos faces resolves to a known type list; Large's top is SHORT_TEXT only
            var faces = ["018-modular", "019-list", "020-stacked", "021-classic", "022-large", "023-bold-numerals",
                         "024-step-ring", "025-words", "027-concentric"]
            for (var i = 0; i < faces.length; i++) {
                var f = load(faces[i])
                var slots = findAll(f, "eosComplication")
                for (var j = 0; j < slots.length; j++)
                    verify(FE.slotTypes(slots[j].shape, slots[j].supportedTypes) !== null, faces[i] + " " + slots[j].slotId)
            }
            f = load("022-large")
            compare(FE.slotTypes(slotOf(f, "top").shape, slotOf(f, "top").supportedTypes), ["SHORT_TEXT"])
            f = load("024-step-ring")
            compare(FE.slotTypes(slotOf(f, "ring").shape, slotOf(f, "ring").supportedTypes), ["RANGED_VALUE"])
            ld.source = ""
        }
    }
}
