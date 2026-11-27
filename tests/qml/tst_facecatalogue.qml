/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The face catalogue against stock (AUDIT-72 area A, round R5):
 *  - A-19: the 51 colours of all_colorway.xml (the 35 and the 16 two-tone ones of RWF glo.java:191-206),
 *    the colourway roles (gdo.java), Large Scale on Spring with its bulb in the second tone
 *    (preview_accessible.png), Concentric's text colours equal to the roles;
 *  - A-14: the complication chooser lists only the sources whose stock data types the slot takes
 *    (faceeditor.js SOURCE_TYPES, slotTypes, accepts; EditorProviderList.openFor with the slot);
 *  - A-11: the picker names the eos faces with the stock faces' names (RWF strings.xml);
 *  - A-07: the Big Time face (two tones, 122 px digits on the stock preview's ink centres, the same look
 *    always-on, the hub's time items), screenshots into /tmp/r5f-shots;
 *  - A-08: the Analog Arcs face (the layouts' slots, the indices of both styles, the numerals, the hands,
 *    the carousel's name), screenshots.
 * qmltestrunner under qemu-aarch64 with the image rootfs (offscreen, software Qt Quick), run in place
 * (the faces of ../../src).
 */

import QtQuick
import QtTest
import "../../src/eoskit/facekit.js" as Kit
import "../../src/eoskit/concentric.js" as C
import "../../src/qml/complications/faceeditor.js" as FE
import "../../src/qml/complications"
import "../../src/qml/misc/facepicker.js" as FP

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
    readonly property string shots: "/tmp/r5f-shots/"
    // the digits' ink (A-07)
    FontMetrics { id: bigProbe }
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

        // ---- A-11: the stock names in the picker ----
        function test_a11_names() {
            var sys = "file:///usr/share/asteroid-launcher/watchfaces/"
            var want = { "018-modular": "Utility", "019-list": "Index", "020-stacked": "Everyday", "021-classic": "Classic",
                         "022-large": "Large Scale", "023-bold-numerals": "Analog Bold", "024-step-ring": "Track",
                         "025-words": "Prime", "026-photo": "Photos", "027-concentric": "Concentric" }
            for (var st in want)
                compare(FP.displayName(sys + st + ".qml"), want[st], st)
            // the upstream faces keep their names, a face the table does not know its file name's words
            compare(FP.displayName(sys + "000-default-digital.qml"), "Digital")
            compare(FP.displayName("file:///tmp/faces/090-my-own-face.qml"), "My Own Face")
            // the favourites stay keyed on the file: the fresh carousel still finds the faces by their file names
            var installed = ["018-modular", "021-classic", "027-concentric"].map(function (s) { return sys + s + ".qml" })
            compare(FP.defaults(installed, sys + "027-concentric.qml").map(function (e) { return e.id }),
                    ["027-concentric", "018-modular", "021-classic"])
        }

        // ---- A-07: Big Time ----
        function shoot(name) {
            var got = { ok: false }
            top.grabToImage(function (r) { got.r = r; got.ok = true })
            tryVerify(function () { return got.ok }, 10000)
            verify(got.r.saveToFile(top.shots + name), name)
        }
        function at(h, m, ambient, use12) {
            top.displayAmbient = ambient === true
            top.use12H = { value: use12 !== false }
            top.wallClock = { time: new Date(2026, 10, 24, h, m, 0) }
        }
        function test_a07_big_time() {
            at(10, 9, false)
            var f = load("028-big-time")
            // Color only: the 51, Pomelo; no slot
            compare(f.eosOptions.length, 1)
            compare(f.eosOptions[0].id, "color")
            compare(f.eosOptions[0].values.length, 51)
            compare(f.opt("color"), "pomelo")
            compare(findAll(f, "eosComplication").length, 0)
            var st = findAll(f, "eosTime")[0]
            var hh = st.hourItem, mm = st.minuteItem
            compare(hh.text, "10")
            compare(mm.text, "09")
            // the two tones: the hours in role c, the minutes in role e (preview_bigtime.png: #F8908B, #FFCBC9)
            compare(String(hh.interactiveItem.color), "#f8908b")
            compare(String(mm.interactiveItem.color), "#ffcbc9")
            // Roboto Light at 167 px: 122 px digits (the preview's), the middles on its ink centres
            compare(hh.interactiveItem.font.pixelSize, 167)
            compare(hh.interactiveItem.font.weight, Font.Light)
            compare(mm.interactiveItem.font.weight, Font.Light)
            bigProbe.font = hh.interactiveItem.font
            var ink = bigProbe.tightBoundingRect("10")
            verify(Math.abs(ink.height - 122) <= 2, "digits " + ink.height + " px")
            var mid = function (it) { return it.mapToItem(top, 0, Kit.DIGIT_CENTER * it.font.pixelSize).y }
            verify(Math.abs(mid(hh.interactiveItem) - 121.2) <= 1, "hour middle " + mid(hh.interactiveItem))
            verify(Math.abs(mid(mm.interactiveItem) - 265.2) <= 1, "minute middle " + mid(mm.interactiveItem))
            // centred across the screen
            var cx = function (it) { return it.mapToItem(top, it.width / 2, 0).x }
            verify(Math.abs(cx(hh) - 192) <= 0.5 && Math.abs(cx(mm) - 192) <= 0.5)
            shoot("bigtime-1009-awake.png")
            // two-tone colourways: Sunset (pop14) hours pink, minutes blue
            f.eosStyle = { color: "sunset" }
            compare(String(hh.interactiveItem.color), "#ffcaed")
            compare(String(mm.interactiveItem.color), "#b6daf1")
            shoot("bigtime-1009-sunset.png")
            f.eosStyle = {}
            // always-on: the same look (stock's ambient blocks set nothing), the hub's items carry it
            at(18, 33, true)
            f = load("028-big-time")
            tryCompare(f, "blend", 1, 5000)
            var h2 = findAll(f, "eosHubHour")[0], m2 = findAll(f, "eosHubMinute")[0]
            compare(h2.text, "6")
            compare(m2.text, "33")
            compare(String(h2.color), "#f8908b")
            compare(String(m2.color), "#ffcbc9")
            compare(h2.font.weight, Font.Light)
            compare(h2.renderType, Text.NativeRendering)
            compare(h2.font.family, "Roboto")
            shoot("bigtime-0633-ambient.png")
            // 24 h: two digits
            at(18, 33, false, false)
            f = load("028-big-time")
            compare(findAll(f, "eosTime")[0].hourItem.text, "18")
            ld.source = ""
            at(10, 9, false)
        }

        // ---- A-08: Analog Arcs ----
        function activeSlots(f) {
            return findAll(f, "eosComplication").filter(function (s) { return s.eosActive !== false && s.visible })
                .map(function (s) { return s.slotId }).sort()
        }
        function test_a08_analog_arcs() {
            at(10, 9, false)
            var f = load("029-analog-arcs")
            compare(f.eosHubDrawn, false)
            compare(f.eosOptions.map(function (o) { return o.id }), ["color", "layout", "styles", "seconds"])
            compare(f.opt("color"), "stream")
            compare(f.opt("layout"), "max4")
            compare(f.opt("styles"), "ring")
            compare(f.opt("seconds"), true)
            compare(f.eosOptions[1].labels, ["Max Four", "Max Two", "Minimal Four", "Minimal Two", "Numerals Four", "Numerals Two"])
            compare(f.eosOptions[2].labels, ["Ring Indices", "Simple Indices"])
            // Max Four: four bulbs at the layout's bounds x 2, four quarter arcs
            compare(activeSlots(f), ["bottom", "left", "northeast", "northwest", "right", "southeast", "southwest", "top"])
            var l = slotOf(f, "left"), t = slotOf(f, "top"), r = slotOf(f, "right"), bo = slotOf(f, "bottom")
            compare([l.x, l.y, l.width], [72, 150, 86])
            compare([t.x, t.y], [150, 72])
            compare([r.x, r.y], [228, 150])
            compare([bo.x, bo.y], [150, 224])
            compare([slotOf(f, "northwest").arcStart, slotOf(f, "northwest").arcSweep], [180, 90])
            compare([slotOf(f, "northeast").arcStart, slotOf(f, "southeast").arcStart, slotOf(f, "southwest").arcStart],
                    [-90, 0, 90])
            // stock's default sources
            compare([l.defaultSource, t.defaultSource, r.defaultSource, bo.defaultSource], ["heartrate", "health", "date", "steps"])
            compare([slotOf(f, "northwest").defaultSource, slotOf(f, "northeast").defaultSource,
                     slotOf(f, "southwest").defaultSource, slotOf(f, "southeast").defaultSource], ["sun", "uv", "calories", "weather"])
            // Ring Indices: two circles, 12 hour indices, 48 minute ticks, in Stream at 85 %
            var circles = findAll(f, "eosArcsCircle")
            compare(circles.length, 2)
            compare(circles[0].width, 2 * 140.8)
            compare(String(circles[0].border.color), Kit.accentColor("stream"))
            compare(findAll(f, "eosArcsHourIndex").filter(function (i) { return i.visible }).length, 12)
            compare(findAll(f, "eosArcsMinuteTick").filter(function (i) { return i.visible }).length, 48)
            compare(findAll(f, "eosNumeral").length, 0)
            // the hands, the seconds in the colour
            verify(findAll(f, "eosHourHand").length === 1 && findAll(f, "eosSecondHand").length === 1)
            shoot("arcs-max4-1009-awake.png")
            // the other layouts
            var want = {
                max2: ["bottom", "left", "lower", "right", "top", "upper"],
                minimal4: ["line", "northeast", "northwest", "southeast", "southwest"],
                minimal2: ["line", "lower", "upper"],
                numerals4: ["northeast", "northwest", "southeast", "southwest"],
                numerals2: ["lower", "upper"]
            }
            for (var lay in want) {
                f.eosStyle = { layout: lay }
                compare(activeSlots(f), want[lay], lay)
            }
            f.eosStyle = { layout: "minimal4" }
            compare([slotOf(f, "line").x, slotOf(f, "line").y, slotOf(f, "line").width, slotOf(f, "line").height], [98, 88, 188, 28])
            compare(slotOf(f, "line").defaultSource, "date")
            f.eosStyle = { layout: "max2" }
            compare([slotOf(f, "upper").arcStart, slotOf(f, "upper").arcSweep, slotOf(f, "lower").arcStart], [180, 180, 0])
            compare([slotOf(f, "upper").defaultSource, slotOf(f, "lower").defaultSource], ["weather", "uv"])
            // Numerals: 12, 3, 6, 9 where numerals.png has them, Simple Indices: the hour indices alone
            f.eosStyle = { layout: "numerals4", styles: "simple" }
            var nums = findAll(f, "eosNumeral")
            compare(nums.map(function (n) { return n.text }), ["12", "3", "6", "9"])
            var mid = nums[1].mapToItem(top, nums[1].width / 2, Kit.DIGIT_CENTER * nums[1].font.pixelSize)
            verify(Math.abs(mid.x - 285.5) <= 0.75 && Math.abs(mid.y - 195) <= 0.75, mid.x + "," + mid.y)
            compare(findAll(f, "eosArcsCircle").length, 0)
            compare(findAll(f, "eosArcsHourIndex").filter(function (i) { return i.visible }).length, 12)
            compare(findAll(f, "eosArcsMinuteTick").filter(function (i) { return i.visible }).length, 0)
            shoot("arcs-numerals4-simple-1009.png")
            // always-on: the indices dim
            at(10, 9, true)
            f = load("029-analog-arcs")
            tryCompare(f, "blend", 1, 5000)
            compare(String(f.indexColor), String(f.accentAmbient))
            shoot("arcs-max4-1009-ambient.png")
            ld.source = ""
            at(10, 9, false)
            // the picker's name
            compare(FP.displayName("file:///usr/share/asteroid-launcher/watchfaces/029-analog-arcs.qml"), "Analog Arcs")
        }
    }
}
