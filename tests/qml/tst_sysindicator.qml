/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * N61-03, the launcher's part: the launcher hosts only system UI surfaces, so it draws the scroll
 * indicator in the system UI's style (RotaryInput.systemIndicator, qml-asteroid newlook-61): a white
 * thumb on a #4D4D4D track over 34 degrees about 3 o'clock, radius 183 (the Wear OS 6 emulator S05,
 * S07, S11). compositor.qml turns it on once at start. The tile picker (TileAddList) is an M3 screen
 * in stock (S14-d: #C6C6C6 thumb, +-16 degrees) and keeps the app style with m3Indicator. Applications
 * are other processes and keep the app style. Staged as the qrc lays the tree out (st/qml). Shots
 * (384 x 384) go to /tmp/l3h-shots.
 */
import QtQuick
import QtTest
import org.asteroid.controls

Item {
    id: top
    width: 384
    height: 384

    // the launcher's context properties the picker reads
    QtObject { id: localeManager; property string changesObserver: "" }

    Rectangle { anchors.fill: parent; color: "black" }
    // a list of the launcher (the app list, Recents, the stream: views of the system UI)
    ListView {
        id: sysList
        objectName: "sysList"
        anchors.fill: parent
        model: 30
        spacing: 8
        delegate: Rectangle {
            // clear of the arc (x 332 and more within +-40 degrees)
            width: sysList.width - 120
            height: 104
            radius: 52
            color: "#2F3036"
        }
    }
    Loader {
        id: addList
        anchors.fill: parent
        active: false
        source: "st/qml/tiles/TileAddList.qml"
    }

    TestCase {
        name: "SystemIndicator"
        when: windowShown

        // the shared indicator RotaryInput puts on the window
        function indicator() {
            var r = top
            while (r.parent)
                r = r.parent
            var kids = r.children
            for (var i = 0; i < kids.length; i++) {
                var k = kids[i]
                if (k.flickable !== undefined && k.shown !== undefined && typeof k.flash === "function")
                    return k
            }
            return null
        }
        function readFile(url) {
            var x = new XMLHttpRequest()
            x.open("GET", url, false)
            x.send()
            return x.responseText
        }
        function colourIs(c, hex, msg) {
            var e = Qt.color(hex)
            verify(Math.abs(c.r - e.r) < 0.01 && Math.abs(c.g - e.g) < 0.01 && Math.abs(c.b - e.b) < 0.01, (msg || "") + " " + c + " != " + hex)
        }
        function near(a, b, tol, msg) { verify(Math.abs(a - b) <= tol, (msg || "") + " " + a + " != " + b) }
        // the arc at radius 183 from -40 to +40 degrees (0 = 3 o'clock, + = down), one sample a degree:
        // the grey level of each
        function arc(img) {
            var out = []
            for (var d = -40; d <= 40; d++) {
                var a = d * Math.PI / 180
                var p = img.pixel(Math.round(192 + 183 * Math.cos(a)), Math.round(192 + 183 * Math.sin(a)))
                out.push({ deg: d, r: p.r, g: p.g, b: p.b })
            }
            return out
        }
        // the ink's extent and the thumb's and track's grey levels on the arc
        function inkOf(samples) {
            var lo = 99, hi = -99, white = 0, track = 0
            for (var i = 0; i < samples.length; i++) {
                var s = samples[i]
                if (s.r + s.g + s.b > 0.15) {
                    lo = Math.min(lo, s.deg); hi = Math.max(hi, s.deg)
                }
                if (s.r > 0.95 && s.g > 0.95 && s.b > 0.95)
                    white++
                if (Math.abs(s.r - 0x4D / 255) < 0.03 && Math.abs(s.g - 0x4D / 255) < 0.03 && Math.abs(s.b - 0x4D / 255) < 0.03)
                    track++
            }
            return { lo: lo, hi: hi, white: white, track: track }
        }
        function shown(ind) {
            tryVerify(function () { return ind.shown }, 1000)
            wait(500)       // the fade-in spring (about 330 ms)
        }

        function cleanupTestCase() {
            RotaryInput.systemIndicator = false
        }

        function test_01_the_launcher_turns_it_on_at_start() {
            // compositor.qml, the launcher's root: once, in its own Component.onCompleted
            var src = readFile(Qt.resolvedUrl("st/qml/compositor.qml"))
            var at = src.indexOf("RotaryInput.systemIndicator = true")
            verify(at > 0, "compositor.qml sets it")
            var onc = src.indexOf("Component.onCompleted")
            verify(onc > 0 && onc < at, "in the root's Component.onCompleted")
            verify(src.indexOf("}", onc) > at, "inside that block")
            compare(src.split("RotaryInput.systemIndicator").length, 2, "set once, nowhere cleared")
            // the tile picker's grid opts out
            var tal = readFile(Qt.resolvedUrl("st/qml/tiles/TileAddList.qml"))
            verify(/GridView \{[^{}]*property bool m3Indicator: true/.test(tal), "TileAddList's GridView keeps the app style")
        }

        function test_02_system_style_on_a_launcher_list() {
            verify(!RotaryInput.systemIndicator, "off by default: applications keep the app style")
            // the app style first (what an application gets): #C6C6C6 / #303030, 50 dp
            verify(RotaryInput.flashIndicator(sysList))
            var ind = indicator()
            verify(ind !== null)
            compare(ind.flickable, sysList)
            verify(!ind.systemStyle)
            colourIs(ind.thumbColor, "#C6C6C6", "app thumb")
            colourIs(ind.trackColor, "#303030", "app track")
            near(ind.sweepDegrees, 100 / 183 * 180 / Math.PI, 0.5, "50 dp along the track")
            // the launcher's: as compositor.qml sets it
            RotaryInput.systemIndicator = true
            verify(ind.systemStyle)
            colourIs(ind.thumbColor, "#FFFFFF", "system thumb")
            colourIs(ind.trackColor, "#4D4D4D", "system track")
            compare(ind.sweepDegrees, 34)
            verify(RotaryInput.flashIndicator(sysList))
            shown(ind)
            var img = grabImage(top)
            img.save("/tmp/l3h-shots/sysind-02-list-top.png")
            var ink = inkOf(arc(img))
            // the ink within +-17 degrees (the round caps sit inside the 34 degrees), the thumb white at
            // the top (the list at its start), the rest of the track #4D4D4D
            verify(ink.lo >= -18 && ink.hi <= 18, "ink from " + ink.lo + " to " + ink.hi)
            verify(ink.lo <= -15 && ink.hi >= 15, "the track spans 34 degrees: " + ink.lo + " to " + ink.hi)
            verify(ink.white >= 6, "a white thumb: " + ink.white)
            verify(ink.track >= 6, "a #4D4D4D track: " + ink.track)
            var a = arc(img)
            verify(a[40 - 14].r > 0.95, "the thumb at the top end (-14 degrees)")
            verify(Math.abs(a[40 + 12].r - 0x4D / 255) < 0.03, "the track at +12 degrees")
            // at the end of the list the thumb is at the bottom end (QS opens so: S11)
            sysList.positionViewAtEnd()
            wait(700)
            img = grabImage(top)
            img.save("/tmp/l3h-shots/sysind-02-list-end.png")
            a = arc(img)
            verify(a[40 + 14].r > 0.95, "the thumb at the bottom end (+14 degrees)")
            verify(Math.abs(a[40 - 12].r - 0x4D / 255) < 0.03, "the track at -12 degrees")
            sysList.positionViewAtBeginning()
        }

        function test_03_the_tile_picker_keeps_the_app_style() {
            RotaryInput.systemIndicator = true
            addList.active = true
            tryCompare(addList, "status", Loader.Ready)
            var l = addList.item
            var reg = {}, ids = []
            for (var i = 0; i < 14; i++) {
                reg["t" + i] = { name: "Tile " + i, icon: "ios-help" }
                ids.push("t" + i)
            }
            l.registry = reg
            l.tiles = ids
            l.open()
            wait(600)
            verify(l.grid.m3Indicator === true)
            verify(l.grid.contentHeight > l.grid.height, "a picker that scrolls")
            verify(RotaryInput.flashIndicator(l.grid))
            var ind = indicator()
            compare(ind.flickable, l.grid)
            verify(!ind.systemStyle, "the picker keeps the app style")
            colourIs(ind.thumbColor, "#C6C6C6", "picker thumb")
            colourIs(ind.trackColor, "#303030", "picker track")
            near(ind.sweepDegrees, 100 / 183 * 180 / Math.PI, 0.5)
            shown(ind)
            var img = grabImage(top)
            img.save("/tmp/l3h-shots/sysind-03-picker.png")
            // on top of the picker's previews: the thumb #C6C6C6 at the top end (the grid at its
            // start), the track #303030 below it
            var a = arc(img)
            verify(Math.abs(a[40 - 12].r - 0xC6 / 255) < 0.03, "a #C6C6C6 thumb: " + a[40 - 12].r)
            verify(Math.abs(a[40 + 12].r - 0x30 / 255) < 0.03, "a #303030 track: " + a[40 + 12].r)
            // a launcher list again: the system style
            l.closeNow()
            addList.active = false
            verify(RotaryInput.flashIndicator(sysList))
            verify(ind.systemStyle)
            colourIs(ind.thumbColor, "#FFFFFF")
        }
    }
}
