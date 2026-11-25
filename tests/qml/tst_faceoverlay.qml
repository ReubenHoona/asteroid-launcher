// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause
//
// The face's bottom row (N61-17): src/qml/home/FaceOverlayRow.qml with LiveSpace.qml (the ongoing
// icon) and FaceStatusIcon.qml (the status icon), the rules of home/status.js, against the Wear OS 6
// emulator (S01, S02, X-face-ongoing-stopwatch(-6s), X-face-ongoing-plus-unread,
// X-ambient-ongoing-plus-unread, X-face-charging, X-face-airplane):
//  - the slots' centres for one, two and three slots (pixel 191.5, 360.5; 173.5 / 209.5 at y 359.5;
//    about 156 / 192 / 228), the band's length (57, 93, 129 px), thickness 42 px, black at 70 %;
//  - pixels: the 12 px white dot at x 186-197, y 355-366; the face under the band at 30 % of its value;
//    the bare charging bolt of WO-61-M1 at x 182-201, y 345-376 (20 x 32 px); nothing at the top;
//  - the 300 ms appear, slide and band changes awake, none in the always-on screen; a status glyph
//    replaced; the ongoing icon with no text, its 120 px tap target, tap and long press;
//  - the band clear of Concentric's hub-drawn dial; screenshots over Concentric into /tmp/l1h-shots.
// Coordinates here are the scene's (a pixel's centre is at +0.5).
// Run beside st/ (the tree as its qrc lays it out in st/qml, the faces in st/watchfaces and st/eoskit)
// under qemu-aarch64 on the image rootfs, the icon folder holding the glyphs of WO-61-M1
// (newlook-wt/l1h/run.sh, MODE=st).
import QtQuick
import QtTest
import org.asteroid.controls
import "st/qml/home/status.js" as Status
import "st/eoskit/concentric.js" as C

Item {
    id: top
    width: 384
    height: 384

    // what the launcher gives a face (FaceLayer's context)
    property var wallClock: ({ time: new Date(2026, 10, 24, 9, 31, 0) })
    property var use12H: ({ value: true })
    property bool displayAmbient: false

    Rectangle { id: bg; anchors.fill: parent; color: "black" }
    // a flat white face, for the band's dimming
    Rectangle { id: white; anchors.fill: parent; color: "white"; visible: false }
    Loader { id: faceLd; anchors.fill: parent }
    Item { id: host; anchors.fill: parent }

    property var row: null
    property int taps: 0
    property int menus: 0
    property string lastKey: ""

    readonly property var stopwatch: ({ key: "sw1", app: "stopwatch", title: "Stopwatch", category: "stopwatch",
                                        staticIcon: "ms-timer", when: 1, status: "%t" })
    readonly property var timer: ({ key: "tm1", app: "timer", title: "Timer", category: "alarm",
                                    staticIcon: "ms-alarm", when: 1 })

    TestCase {
        id: tc
        name: "FaceOverlayRow"
        when: windowShown

        function near(a, b, eps, msg) { verify(Math.abs(a - b) <= eps, (msg || "") + ": " + a + " vs " + b) }
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
        function find(item, name) { return findAll(item, name)[0] }
        function texts(item, out) {
            out = out || []
            if (!item)
                return out
            if (item.text !== undefined && item.font !== undefined)
                out.push(item)
            for (var i = 0; item.children && i < item.children.length; i++)
                texts(item.children[i], out)
            return out
        }
        // a slot's centre in the scene
        function centre(slot) {
            return slot.mapToItem(top, slot.width / 2, slot.height / 2)
        }
        function make(props) {
            var c = Qt.createComponent(Qt.resolvedUrl("st/qml/home/FaceOverlayRow.qml"))
            compare(c.status, Component.Ready, c.errorString())
            row = c.createObject(host, props || {})
            verify(row !== null)
            row.ongoingTapped.connect(function (key, app) { top.taps++; top.lastKey = key })
            row.ongoingMenuRequested.connect(function (key, app, title) { top.menus++; top.lastKey = key })
            return row
        }
        function grab() {
            wait(30)
            return grabImage(top)
        }
        function lum(img, x, y) { return Math.max(img.red(x, y), img.green(x, y), img.blue(x, y)) }
        function brightBox(img, x0, y0, x1, y1, min) {
            var b = { x0: 1e9, y0: 1e9, x1: -1, y1: -1 }
            for (var y = y0; y <= y1; y++)
                for (var x = x0; x <= x1; x++)
                    if (lum(img, x, y) >= min) {
                        b.x0 = Math.min(b.x0, x); b.x1 = Math.max(b.x1, x)
                        b.y0 = Math.min(b.y0, y); b.y1 = Math.max(b.y1, y)
                    }
            return b
        }
        function init() {
            top.taps = 0; top.menus = 0; top.lastKey = ""
            white.visible = false
            faceLd.source = ""
        }
        function cleanup() {
            if (row) {
                row.destroy()
                row = null
                wait(20)
            }
        }

        // ---- the rules ----------------------------------------------------------------------------
        function test_01_rules() {
            compare(Status.rowSlots(true, true, true), ["ongoing", "dot", "status"])
            compare(Status.rowSlots(false, true, false), ["dot"])
            compare(Status.rowSlots(true, false, true), ["ongoing", "status"])
            compare(Status.rowSlots(false, false, false), [])
            compare(Status.ROW_SLOT_DP, 18)
            compare(Status.ROW_EDGE_DP, 11.5)
            compare(Status.ROW_DOT_DP, 6)
            compare(Status.ROW_BAND_DP, 21)
            compare(Status.ROW_BAND_OPACITY, 0.7)
            compare(Status.ROW_MS, 300)
            compare(Status.ROW_CURVE, [0.4, 0, 0.2, 1, 1, 1])
            compare(Status.ROW_TAP_MIN_DP, 60)
            var r = 169, s = 36
            function at(i, n) { return Status.rowPoint(Status.rowAngle(i, n, s, r), 192, 192, r) }
            near(at(0, 1).x, 192, 1e-9, "one: x"); near(at(0, 1).y, 361, 1e-9, "one: y")
            near(at(0, 2).x, 174, 0.1, "two: left"); near(at(1, 2).x, 210, 0.1, "two: right")
            near(at(0, 2).y, 360, 0.1, "two: y"); near(at(1, 2).y, 360, 0.1, "two: y")
            near(at(0, 3).x, 156.5, 0.5, "three: left"); near(at(1, 3).x, 192, 1e-9, "three: middle")
            near(at(2, 3).x, 227.5, 0.5, "three: right")
            compare(Status.bandLength(1, s, 42), 57)
            compare(Status.bandLength(2, s, 42), 93)
            compare(Status.bandLength(3, s, 42), 129)
            compare(Status.bandLength(0, s, 42), 0)
            near(Status.bandSweepDeg(1, s, 42, r), 15 / 169 * 180 / Math.PI, 1e-9, "one: sweep")
            near(Status.bandSweepDeg(3, s, 42, r), 87 / 169 * 180 / Math.PI, 1e-9, "three: sweep")
            compare(Status.bandSweepDeg(0, s, 42, r), 0)
            verify(/eos-status-touchlock\.svg$/.test(Status.iconSource("wet-touch")), Status.iconSource("wet-touch"))
            verify(/eos-status-waterlock\.svg$/.test(Status.iconSource("wet-water")))
            verify(/eos-status-charging\.svg$/.test(Status.iconSource("charging")))
            compare(Status.iconSource("safety"), "")
            compare(Status.iconSource(""), "")
            compare(Status.words("wet-touch"), "Touch lock on")
        }

        // ---- where the slots are (always-on: no animation) ---------------------------------------
        function test_02_geometry() {
            make({ interactive: false })
            compare(row.count, 0)
            compare(row.band.visible, false)
            near(row.arcRadius, 169, 1e-9, "radius")
            compare(row.slotSize, 36)
            compare(row.bandWidth, 42)

            row.dotWanted = true
            compare(row.count, 1)
            var d = centre(row.dotSlot)
            near(d.x, 192, 1e-6, "dot x"); near(d.y, 361, 1e-6, "dot y")
            compare(row.dot.width, 12); compare(row.dot.height, 12)
            compare(String(row.dot.color), "#ffffff")
            var dr = row.dot.mapToItem(top, 0, 0)
            near(dr.x, 186, 1e-6, "dot box x"); near(dr.y, 355, 1e-6, "dot box y")
            compare(row.band.visible, true)
            near(row.band.opacity, 0.7, 1e-9, "band opacity")
            near(row.band.sweep, Status.bandSweepDeg(1, 36, 42, 169), 1e-9, "band: one slot")

            row.ongoingEntry = top.stopwatch
            compare(row.count, 2)
            var o = centre(row.ongoingSlot)
            d = centre(row.dotSlot)
            near(o.x, 174, 0.5, "ongoing x"); near(d.x, 210, 0.5, "dot x")
            near(o.y, 360, 0.6, "ongoing y"); near(d.y, 360, 0.6, "dot y")
            near(row.band.sweep, Status.bandSweepDeg(2, 36, 42, 169), 1e-9, "band: two slots")

            row.statusKey = "charging"
            compare(row.count, 3)
            var st = centre(row.statusIconSlot)
            o = centre(row.ongoingSlot); d = centre(row.dotSlot)
            near(o.x, 156.5, 0.6, "three: ongoing"); near(d.x, 192, 0.01, "three: dot")
            near(st.x, 227.5, 0.6, "three: status")
            near(d.y, 361, 0.01, "three: dot y"); near(st.y, 357.2, 0.3, "three: status y")
            near(row.band.sweep, Status.bandSweepDeg(3, 36, 42, 169), 1e-9, "band: three slots")
            // nothing at the top: every slot in the bottom eighth
            verify(row.ongoingSlot.mapToItem(top, 0, 0).y > 330)
            verify(row.statusIconSlot.mapToItem(top, 0, 0).y > 330)
            // the slots stay upright
            compare(row.ongoingSlot.rotation, 0)
            compare(row.statusIconSlot.rotation, 0)
            // the ongoing icon's tap target: at least 120 px square, centred on its slot
            var tap = find(row, "liveTap")
            verify(tap.width >= 120 && tap.height >= 120, tap.width + " x " + tap.height)
            var tc0 = tap.mapToItem(top, tap.width / 2, tap.height / 2)
            near(tc0.x, o.x, 0.01, "tap centre x"); near(tc0.y, o.y, 0.01, "tap centre y")

            // a type without a glyph takes no slot
            row.ongoingEntry = ({})
            row.dotWanted = false
            row.statusKey = "safety"
            compare(row.count, 0)
            compare(row.band.visible, false)
            compare(row.statusIconSlot.visible, false)
            row.statusKey = "wet-touch"
            compare(row.count, 1)
            verify(/eos-status-touchlock\.svg$/.test(String(row.statusIcon.mainIcon.source)))
        }

        // ---- pixels ---------------------------------------------------------------------------------
        function test_03_dot_and_band_pixels() {
            make({ interactive: false, dotWanted: true })
            wait(50)
            var img = grab()
            // the dot: white, 12 px at x 186-197, y 355-366
            var b = brightBox(img, 150, 330, 234, 383, 128)
            compare([b.x0, b.x1, b.y0, b.y1], [186, 197, 355, 366])
            compare(lum(img, 192, 361), 255)
            // over a white face
            white.visible = true
            img = grab()
            compare(lum(img, 192, 361), 255)
            // the white face under the band at 30 % (stock: 255 -> 69-77)
            near(lum(img, 192, 343), 76.5, 3, "under the band, over the dot")
            near(lum(img, 172, 361), 76.5, 3, "under the band, left of the dot")
            near(lum(img, 212, 361), 76.5, 3, "under the band, right of the dot")
            near(lum(img, 192, 381), 76.5, 3, "the band's bottom row")
            // outside it, the face as it is: the band is 57 x 42 px (x 163.5-220.5, y 340-382)
            compare(lum(img, 192, 338), 255)
            compare(lum(img, 160, 361), 255)
            compare(lum(img, 224, 361), 255)
            compare(lum(img, 192, 383), 255)
            // nothing at the top
            compare(lum(img, 192, 18), 255)
            img.save("/tmp/l1h-shots/row-dot-on-white.png")
        }

        function test_04_bolt_pixels() {
            make({ interactive: false, statusKey: "charging" })
            wait(50)
            var img = grab()
            // the bare bolt of WO-61-M1 (stock X-face-charging: x 182-201, y 345-376, 20 x 32 px)
            var b = brightBox(img, 150, 330, 234, 383, 128)
            near(b.x0, 182, 1, "bolt left"); near(b.x1, 201, 1, "bolt right")
            near(b.y0, 345, 1, "bolt top"); near(b.y1, 376, 1, "bolt bottom")
            // white, no disc: the slot's corner is black
            compare(lum(img, 176, 345), 0)
            verify(img.red(192, 361) > 240 && img.green(192, 361) > 240 && img.blue(192, 361) > 240, "white glyph")
            // nothing at the top
            var t = brightBox(img, 150, 0, 234, 60, 40)
            compare(t.x1, -1)
        }

        // ---- motion: 300 ms awake, none always-on --------------------------------------------------
        function test_05_motion() {
            verify(Motion.animationScale > 0)
            make({ interactive: true })
            row.dotWanted = true
            verify(row.dotSlot.appear < 1, "the dot comes in")
            verify(row.animating)
            near(centre(row.dotSlot).x, 192, 1e-6, "the new slot comes in at its place")
            tryCompare(row.dotSlot, "appear", 1, 2000)
            tryCompare(row, "animating", false, 2000)
            near(row.band.opacity, 0.7, 1e-9, "band shown")
            var t0 = Date.now()
            row.ongoingEntry = top.stopwatch
            // the dot slides right while the ongoing icon grows in at its place
            near(centre(row.ongoingSlot).x, 174, 0.5, "ongoing in place at once")
            tryVerify(function () { var x = centre(row.dotSlot).x; return x > 195 && x < 207 }, 1000, "the dot mid-slide")
            verify(row.band.sweep > Status.bandSweepDeg(1, 36, 42, 169) - 1e-9)
            tryCompare(row, "animating", false, 2000)
            near(centre(row.dotSlot).x, 210, 0.5, "the dot at its new place")
            near(row.band.sweep, Status.bandSweepDeg(2, 36, 42, 169), 1e-6, "band: two")
            var took = Date.now() - t0
            verify(took >= 250 * Motion.animationScale, "took " + took + " ms")
            // the ongoing entry goes: it shrinks where it is, the dot slides back
            row.ongoingEntry = ({})
            near(centre(row.ongoingSlot).x, 174, 0.5, "it goes where it is")
            tryCompare(row.ongoingSlot, "appear", 0, 2000)
            tryCompare(row, "animating", false, 2000)
            near(centre(row.dotSlot).x, 192, 0.5, "the dot back in the middle")
            // a change while the display goes always-on: the final look at once
            row.statusKey = "airplane"
            verify(row.animating)
            row.interactive = false
            compare(row.animating, false)
            compare(row.statusIconSlot.appear, 1)
            near(centre(row.dotSlot).x, 174, 0.5, "dot at once")
            near(centre(row.statusIconSlot).x, 210, 0.5, "status at once")
            // always-on: changes are at once
            row.dotWanted = false
            compare(row.dotSlot.appear, 0)
            compare(row.animating, false)
            near(centre(row.statusIconSlot).x, 192, 1e-6, "status alone")
            row.statusKey = ""
            compare(row.band.visible, false)
        }

        function test_06_status_replace() {
            make({ interactive: true, statusKey: "charging" })
            tryCompare(row, "animating", false, 2000)
            var icon = row.statusIcon
            compare(icon.shownKey, "charging")
            compare(row.statusIconSlot.appear, 1)
            row.statusKey = "airplane"
            compare(icon.replaceAnim.running, true)
            compare(icon.crossIcon.visible, true)
            verify(/airplane\.svg$/.test(String(icon.mainIcon.source)))
            verify(/charging\.svg$/.test(String(icon.crossIcon.source)))
            tryCompare(icon.replaceAnim, "running", false, 2000)
            compare(icon.crossIcon.visible, false)
            compare(icon.mainIcon.opacity, 1)
            compare(icon.description, "Airplane mode on")
            // the slot goes: the glyph stays while it shrinks
            row.statusKey = ""
            compare(icon.shownKey, "airplane")
            tryCompare(row.statusIconSlot, "appear", 0, 2000)
            compare(row.statusIconSlot.visible, false)
        }

        // ---- the ongoing icon ----------------------------------------------------------------------
        function test_07_ongoing() {
            make({ interactive: true, ongoingEntry: top.stopwatch })
            tryCompare(row, "animating", false, 2000)
            var live = row.liveSpace
            // icon only: no text, no pill, no timer
            compare(texts(live).length, 0)
            compare(find(live, "liveText"), undefined)
            compare(live.ambientKey, "sw1|ms-timer")
            compare(live.description, "Ongoing Stopwatch running in the background")
            compare(live.pill.width, 36)
            // tap on the icon, and 30 px above it (inside the 120 px target)
            mouseClick(top, 192, 361)
            compare(top.taps, 1); compare(top.lastKey, "sw1")
            mouseClick(top, 192, 331)
            compare(top.taps, 2)
            mousePress(top, 192, 361)
            wait(1000)
            mouseRelease(top, 192, 361)
            compare(top.menus, 1)
            // another entry: it gives way in 300 ms
            row.ongoingEntry = top.timer
            compare(live.replaceAnim.running, true)
            tryCompare(live.replaceAnim, "running", false, 2000)
            compare(live.ambientKey, "tm1|ms-alarm")
            // always-on: the static icon, no animation
            row.interactive = false
            compare(live.animated, false)
        }

        // ---- the hub: the band stays off Concentric's hub-drawn dial ---------------------------------
        function test_08_band_clear_of_the_hub_dial() {
            make({ interactive: false })
            var inner = row.arcRadius - row.bandWidth / 2
            near(inner, 148, 1e-9, "the band's inner edge")
            // the hub draws the inner dial's long ticks (to radius 138) and numerals (radius 106)
            verify(C.MINUTES_TICKS.major[1] < inner)
            verify(C.MINUTES_RADIUS + C.NUMERAL_PX < inner)
            // the band reaches the screen's edge less 1 dp, inside the outer ticks the AP draws
            near(row.arcRadius + row.bandWidth / 2, 190, 1e-9, "the band's outer edge")
        }

        // ---- over Concentric, for a look against the emulator ---------------------------------------
        function face(h, m, s, ambient) {
            top.displayAmbient = ambient
            top.wallClock = { time: new Date(2026, 10, 24, h, m, ambient ? s : s - 1) }
            faceLd.source = Qt.resolvedUrl("st/watchfaces/027-concentric.qml")
            tryCompare(faceLd, "status", Loader.Ready, 20000)
            var f = faceLd.item
            if (!ambient)
                tryVerify(function () { return Math.abs(f.sweep - (h * 3600 + m * 60 + s)) < 1e-3 }, 5000)
            else
                tryCompare(f, "blend", 1, 5000)
            wait(50)
        }
        function test_09_shots() {
            face(9, 31, 1, false)
            make({ interactive: false, ongoingEntry: top.stopwatch, dotWanted: true })
            wait(50)
            var img = grab()
            img.save("/tmp/l1h-shots/face-0931-ongoing-unread.png")
            // the stopwatch icon at x 174, the dot at x 210 (stock X-ambient-ongoing-plus-unread)
            var dotBox = brightBox(img, 200, 350, 222, 370, 200)
            near((dotBox.x0 + dotBox.x1) / 2, 209.5, 1, "dot centre x")
            near((dotBox.y0 + dotBox.y1) / 2, 359.5, 1, "dot centre y")
            row.statusKey = "charging"
            wait(50)
            grab().save("/tmp/l1h-shots/face-0931-ongoing-unread-charging.png")
            row.ongoingEntry = ({})
            row.dotWanted = false
            wait(50)
            grab().save("/tmp/l1h-shots/face-0931-charging.png")
            row.destroy(); row = null
            face(9, 32, 0, true)
            make({ interactive: false, ongoingEntry: top.stopwatch, dotWanted: true })
            wait(50)
            grab().save("/tmp/l1h-shots/face-0932-ambient-ongoing-unread.png")
        }
    }
}
