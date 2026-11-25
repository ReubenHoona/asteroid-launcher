// SPDX-License-Identifier: BSD-3-Clause
//
// The charging screen and the charging quality screen drawn (src/qml/charging:
// ChargingScreen.qml, Bolt.qml, ChargerProblem.qml) with the image's controls on the
// repo mocks (MceBatteryLevel on Backend.batteryPercent, the ClockSource double of
// tests/qml/stage). 384 x 384 px = 192 dp, 1 dp = 2 px. The bolt is drawn where
// stock draws it (D60-10), the date chip reads ICU's "EEE d" and sits centred
// between the clock and the bottom slot as CP3A's measure policy places it
// (D60-11, imm.java); the look is the Wear OS 6 emulator's (N61-18, S03-c at 91 %:
// colours, digits, minutes corner, a 32 px chip, the unread dot in the bottom slot).
// Staged as tst_charging.qml is (module LauncherQml); the real org.asteroid.utils
// (DateFormat, ICU), not the mock. Shots go to /tmp/wo04-shots.
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
            s.unread = false
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
            compare(rgb(bolt.fillColor).join(), "198,184,249,0.96") // tertiaryDim at 96 % (S03-c)
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
            // two points inside the fill, tertiaryDim at 96 % over black: #BEB1EF (S03-c 190,177,239)
            var pts = [[190, 80], [192, 95]]
            for (var i = 0; i < pts.length; i++) {
                near(img.red(pts[i][0], pts[i][1]), 190, 2, "fill " + pts[i])
                near(img.green(pts[i][0], pts[i][1]), 177, 2, "fill " + pts[i])
                near(img.blue(pts[i][0], pts[i][1]), 239, 2, "fill " + pts[i])
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

        // ---- D60-11: the chip
        function test_chip_text() {
            up()
            var txt = find(s, "eosChargingChipText"), icon = find(s, "eosChargingChipIcon")
            // ICU "EEE d" in the C locale (ICU's en_US): the day before the weekday
            compare(Qt.locale().name, "C")
            compare(txt.text, "23 Mon")
            verify(!icon.visible)
            s.now = new Date(2026, 10, 14, 13, 7)
            compare(txt.text, "14 Sat")
            // an alarm within 24 h: icon 16 dp, 8 dp gap, the time
            s.nextAlarmMs = s.now.getTime() + 8 * 3600 * 1000
            compare(txt.text, "21:07")
            verify(icon.visible)
            compare(icon.width, 32)
            compare(icon.height, 32)
            s.use12h = true
            compare(txt.text, "9:07 PM")
            // beyond 24 h: the date again
            s.nextAlarmMs = s.now.getTime() + 25 * 3600 * 1000
            compare(txt.text, "14 Sat")
            verify(!icon.visible)
        }
        function test_chip_place() {
            up()
            var chip = find(s, "eosChargingChip"), txt = find(s, "eosChargingChipText"), h = find(s, "eosChargingHours")
            compare(rgb(chip.color).join(), "36,38,43,1")           // surfaceContainerLow (S03-c)
            compare(rgb(txt.color).join(), "198,184,249,1")         // tertiaryDim (S03-c)
            compare(txt.font.pixelSize, 26)                         // labelSmall 13 sp
            // padding 6 / 0 dp: the labelSmall line, 16 sp = 32 px tall (S03-c: 32 px)
            near(chip.width, txt.width + 24, 0.5)
            compare(chip.height, 32)
            near(chip.radius, 16, 0.01)
            // centred between the clock's bottom (262) and the empty bottom slot's top (384 - 28)
            var clockBottom = h.parent.y + h.height
            near(clockBottom, 262, 0.01)
            near(chip.y, (clockBottom + 356 - chip.height) / 2, 0.01)
            near(chip.y, 293, 0.01)
            near(chip.x + chip.width / 2, 192, 0.5)
            // drawn there: the pill's fill just inside its top and bottom edges, black above and below
            var img = shot("charging-chip")
            var cx = 150
            near(img.red(cx, 296), 36, 3); near(img.green(cx, 296), 38, 3); near(img.blue(cx, 296), 43, 3)
            near(img.red(cx, 322), 36, 3); near(img.green(cx, 322), 38, 3); near(img.blue(cx, 322), 43, 3)
            compare(img.red(cx, 290) + img.green(cx, 290) + img.blue(cx, 290), 0)
            compare(img.red(cx, 328) + img.green(cx, 328) + img.blue(cx, 328), 0)
        }

        // ---- N61-18 (D60-12 reversed): the unread dot in the bottom slot
        function test_unread_dot() {
            up()
            var dot = find(s, "eosChargingDot"), chip = find(s, "eosChargingChip")
            verify(dot !== null)
            // no unread: no dot, the slot empty (0 px), nothing drawn under the chip
            verify(!dot.visible)
            var img = shot("charging-bottom")
            for (var y = 340; y <= 362; y++)
                for (var x = 176; x <= 208; x++)
                    compare(img.red(x, y) + img.green(x, y) + img.blue(x, y), 0, "pixel " + x + "," + y)
            // unread: 5 dp primary, its bottom 14 dp above the edge; the slot is 5 dp, the chip moves up
            s.unread = true
            verify(dot.visible)
            compare(dot.width, 10); compare(dot.height, 10)
            compare(rgb(dot.color).join(), "219,226,249,1")         // primary
            near(dot.x, 187, 0.01); near(dot.y, 346, 0.01)
            near(chip.y, 288, 0.01)
            img = shot("charging-bottom-unread")
            // S03-c: x 187-196, y 346-355, #DBE2F9
            near(img.red(191, 350), 219, 3); near(img.green(191, 350), 226, 3); near(img.blue(191, 350), 249, 3)
            compare(img.red(191, 358) + img.green(191, 358) + img.blue(191, 358), 0)
            compare(img.red(191, 343) + img.green(191, 343) + img.blue(191, 343), 0)
            compare(img.red(184, 350) + img.green(184, 350) + img.blue(184, 350), 0)
        }

        // ---- N61-18: the probes of the emulator's settled frame S03-c (91 %, one unread)
        function test_emulator_probes() {
            Backend.batteryPercent = 91
            s.unread = true
            s.shown = true
            s.awake = false
            s.now = new Date(2026, 10, 23, 6, 34)
            tryCompare(s, "shownLevel", 0.91, 2000)
            wait(50)
            var img = shot("charging-91-unread")
            function px(x, y) { return [img.red(x, y), img.green(x, y), img.blue(x, y)] }
            function close(p, c, tol, msg) {
                verify(Math.abs(p[0] - c[0]) <= tol && Math.abs(p[1] - c[1]) <= tol && Math.abs(p[2] - c[2]) <= tol,
                       msg + ": " + p + " vs " + c)
            }
            function box(x0, y0, x1, y1, test) {
                var b = { x0: 1e9, y0: 1e9, x1: -1, y1: -1 }
                for (var y = y0; y <= y1; y++)
                    for (var x = x0; x <= x1; x++)
                        if (test(px(x, y))) {
                            b.x0 = Math.min(b.x0, x); b.x1 = Math.max(b.x1, x)
                            b.y0 = Math.min(b.y0, y); b.y1 = Math.max(b.y1, y)
                        }
                return b
            }
            // the ring: primaryDim #CDD4EB at full alpha
            close(px(12, 192), [205, 212, 235], 3, "ring")
            // the digits: onSurface #E8E7EE, cap 78 +- 2 px; '06' as the emulator's (x 53-171, y 150-226)
            var d = box(36, 126, 186, 258, function (p) { return p[0] > 200 && p[1] > 200 && p[2] > 200 })
            near(d.y1 - d.y0 + 1, 78, 2, "digit cap")
            near(d.y0, 150, 2, "digits top")
            near((d.x0 + d.x1) / 2, 112, 3, "digits middle x")
            verify(d.x1 - d.x0 + 1 >= 110, "'06' width " + (d.x1 - d.x0 + 1))
            var stroke = 0
            for (var x = d.x0; x < d.x0 + 30; x++)
                if (px(x, 188)[0] > 200) stroke++
            near(stroke, 17, 2, "'0' stroke")
            var lit = box(36, 126, 186, 258, function (p) { return Math.abs(p[0] - 232) <= 3 && Math.abs(p[1] - 231) <= 3 && Math.abs(p[2] - 238) <= 3 })
            verify(lit.x1 > 0, "digit pixels #E8E7EE")
            // the percentage: tertiaryDim #C6B8F9, its glyph top at y 38 (under the ring, which ends at y 20)
            var pc = box(160, 26, 224, 62, function (p) { return p[2] > 150 })
            near(pc.y0, 38, 1, "percent top")
            var pcol = box(160, 26, 224, 62, function (p) { return Math.abs(p[0] - 198) <= 3 && Math.abs(p[1] - 184) <= 3 && Math.abs(p[2] - 249) <= 3 })
            verify(pcol.x1 > 0, "percent pixels #C6B8F9")
            // the bolt: inside x 179-203, y 67-104, #BEB1EF
            var bb = box(150, 60, 234, 115, function (p) { return p[2] > 120 })
            verify(bb.x0 >= 178 && bb.x1 <= 205 && bb.y0 >= 65 && bb.y1 <= 106, "bolt " + JSON.stringify(bb))
            close(px(190, 80), [190, 177, 239], 6, "bolt fill")
            // the chip: y 288-319, #24262B, its text #C6B8F9
            var ch = box(100, 270, 284, 340, function (p) { return Math.abs(p[0] - 36) <= 3 && Math.abs(p[1] - 38) <= 3 && Math.abs(p[2] - 43) <= 3 })
            near(ch.y0, 288, 1, "chip top"); near(ch.y1, 319, 1, "chip bottom")
            var ct = box(100, 270, 284, 340, function (p) { return Math.abs(p[0] - 198) <= 4 && Math.abs(p[1] - 184) <= 4 && Math.abs(p[2] - 249) <= 4 })
            verify(ct.x1 > 0, "chip text #C6B8F9")
            // the unread dot: x 187-196, y 346-355, #DBE2F9
            var dt = box(180, 338, 204, 362, function (p) { return p[2] > 150 })
            compare([dt.x0, dt.x1, dt.y0, dt.y1], [187, 196, 346, 355])
            close(px(191, 350), [219, 226, 249], 3, "dot")
            // the minutes pill's 52 px corner: black at (199, 140), the pill at (200, 160)
            close(px(199, 140), [0, 0, 0], 2, "minutes corner")
            close(px(200, 160), [36, 38, 43], 3, "minutes pill")
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
