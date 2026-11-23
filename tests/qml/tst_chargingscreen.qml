// SPDX-License-Identifier: BSD-3-Clause
//
// The charging screen and the charging quality screen drawn (src/qml/charging:
// ChargingScreen.qml, Bolt.qml, ChargerProblem.qml) with the image's controls on the
// repo mocks (MceBatteryLevel on Backend.batteryPercent, the ClockSource double of
// tests/qml/stage). 384 x 384 px = 192 dp, 1 dp = 2 px. The bolt is drawn where
// stock draws it (D60-10). Staged as tst_charging.qml is (module LauncherQml); the
// real org.asteroid.utils, not the mock. Shots go to /tmp/wo04-shots.
// Run by motion-wt/wo04/run.sh (qmltestrunner under qemu-aarch64 on the image rootfs).
import QtQuick
import QtTest
import org.asteroid.controls
import LauncherTest
import "LauncherQml/charging/charging.js" as Charging

Item {
    id: top
    width: 384; height: 384

    // the launcher's context property (lipstick localemanager.cpp)
    QtObject { id: localeManager; property int localeRevision: 0 }

    Rectangle { anchors.fill: parent; color: "black" }
    Loader { id: ld; anchors.fill: parent; source: Qt.resolvedUrl("LauncherQml/charging/ChargingScreen.qml") }
    Loader { id: pl; anchors.fill: parent; source: Qt.resolvedUrl("LauncherQml/charging/ChargerProblem.qml") }

    function find(item, name) {
        if (item.objectName === name) return item
        var d = item.data
        if (d) for (var i = 0; i < d.length; i++) {
            if (!d[i]) continue
            var r = find(d[i], name); if (r) return r }
        return null
    }

    TestCase {
        id: tc
        name: "ChargingScreen"
        when: windowShown

        property var s: ld.item

        function near(a, b, eps, msg) { verify(Math.abs(a - b) <= eps, (msg || "") + " " + a + " vs " + b) }
        function rgb(c) { return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255), Math.round(c.a * 100) / 100] }

        function initTestCase() { verify(s !== null, "ChargingScreen.qml loads") }
        function init() {
            Backend.reset()
            Backend.batteryPercent = 82
            s.fade = false
            s.shown = false
            s.plugIntro = false
            s.awake = true
            s.use12h = false
            s.nextAlarmMs = 0
            s.now = new Date(2026, 10, 23, 6, 34)
            s.finishIntro()
            wait(10)
        }
        // the finished screen, still: the display reads as dark so the pulse and the minute timer stop
        function up() {
            s.shown = true
            s.awake = false
            s.now = new Date(2026, 10, 23, 6, 34)
            tryCompare(s, "shownLevel", 0.82, 2000)
            wait(50)
        }
        function shot(name) {
            var img = grabImage(top)
            img.save("/tmp/wo04-shots/" + name + ".png")
            return img
        }

        // ---- D60-10: the bolt
        function test_bolt_place() {
            up()
            var bolt = find(s, "eosBolt"), h = find(s, "eosChargingHours")
            // 24 dp, 6 dp above the clock (imm.java: clock top - 6 dp - the bolt), centred
            compare(bolt.size, 48)
            near(h.parent.y, 122, 0.01)
            near(bolt.y + bolt.height, h.parent.y - 12, 0.5)
            near(bolt.x + bolt.width / 2, 192, 0.5)
            near(bolt.x, 168, 0.5)
            near(bolt.y, 62, 0.5)
            compare(s.pulse, 1)
            compare(bolt.opacity, 1)
            compare(rgb(bolt.fillColor).join(), "255,255,255,1")    // onBackground
        }
        function test_bolt_pixels() {
            up()
            var img = shot("charging-rest")
            function lum(x, y) { return img.red(x, y) + img.green(x, y) + img.blue(x, y) }
            // every lit pixel of the band between the percentage and the clock: the bolt, inside
            // stock's box x 179-204, y 67-104 (glyph 13..35 x 4..44 of the 48 px box at 168, 62)
            var n = 0, x0 = 999, x1 = -1, y0 = 999, y1 = -1
            for (var y = 60; y <= 115; y++)
                for (var x = 150; x <= 234; x++)
                    if (lum(x, y) > 120) {
                        n++
                        x0 = Math.min(x0, x); x1 = Math.max(x1, x)
                        y0 = Math.min(y0, y); y1 = Math.max(y1, y)
                    }
            verify(n > 250, "lit bolt pixels " + n)
            verify(x0 >= 179 && x1 <= 205, "bolt x " + x0 + ".." + x1)
            verify(y0 >= 65 && y1 <= 106, "bolt y " + y0 + ".." + y1)
            near((y0 + y1) / 2, 86, 1, "bolt centre y")
            near((x0 + x1) / 2, 192, 1.5, "bolt centre x")
            // two points inside the fill, onBackground (white)
            var pts = [[190, 80], [192, 95]]
            for (var i = 0; i < pts.length; i++) {
                compare(img.red(pts[i][0], pts[i][1]), 255, "fill " + pts[i])
                compare(img.green(pts[i][0], pts[i][1]), 255, "fill " + pts[i])
                compare(img.blue(pts[i][0], pts[i][1]), 255, "fill " + pts[i])
            }
            // outside the glyph, the band is black
            compare(lum(172, 70), 0)
            compare(lum(212, 100), 0)
        }
        function test_bolt_intro_draws() {
            // the intro's bolt: traced outline and fill at 400 ms, large and in the middle
            s.awake = false
            s.plugIntro = true
            s.shown = true
            s.introT = 400
            wait(50)
            var img = shot("charging-intro-400")
            var n = 0
            for (var y = 120; y <= 264; y += 2)
                for (var x = 120; x <= 264; x += 2)
                    if (img.red(x, y) + img.green(x, y) + img.blue(x, y) > 120) n++
            verify(n > 150, "lit intro pixels " + n)
            s.finishIntro()
        }
    }

    // ---- the charging quality screen: its bolt is cut out of the disc (D60-10, same path rule)
    TestCase {
        id: tp
        name: "ChargerProblem"
        when: windowShown

        property var p: pl.item
        function init() { p.kind = "" }
        function cleanup() { p.kind = "" }

        function test_misaligned_bolt_cut_out() {
            verify(p !== null, "ChargerProblem.qml loads")
            p.kind = "misaligned"
            wait(80)
            var img = grabImage(top)
            img.save("/tmp/wo04-shots/charger-problem.png")
            var icon = find(p, "eosChargerProblemIcon")
            compare(icon.width, 48)
            // box units -> px: u * 2 * 0.8 + 4.8 (the bolt at 80 % in the middle of the 24 dp disc)
            function at(ux, uy) { return icon.mapToItem(top, ux * 1.6 + 4.8, uy * 1.6 + 4.8) }
            function lum(q) { return img.red(q.x, q.y) + img.green(q.x, q.y) + img.blue(q.x, q.y) }
            // inside the bolt (upper and lower part): background, cut out of the disc
            compare(lum(at(11.5, 8)), 0, "upper bolt")
            compare(lum(at(12, 16)), 0, "lower bolt")
            // the disc beside the bolt: error colour
            var d = at(3, 12)
            verify(img.red(d.x, d.y) > 150, "disc " + img.red(d.x, d.y))
            d = at(20, 16)
            verify(img.red(d.x, d.y) > 150, "disc " + img.red(d.x, d.y))
        }
    }
}
