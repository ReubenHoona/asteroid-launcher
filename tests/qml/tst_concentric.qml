/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The Concentric face (src/watchfaces/027-concentric.qml, src/eoskit/concentric.js, D60-48):
 *  - the dial angles at sample times (10:09:30, 06:42:05, the wrap at the hour), the slots the
 *    sensor hub uses (slot j shows (minute + j) % 60 when a multiple of 5), the pill window (the
 *    value now sits in the pill, the pill's width awake and always-on), the hour text (two digits
 *    in 12 h);
 *  - the face awake (the dials where the maths puts them, the seconds dial in the pill, the pill
 *    running off the screen) and always-on (no seconds dial, the inner dial on the whole minute at
 *    the hub's slot origins, the long ticks where eosHubTick says on the ring that turns, the short
 *    ticks on a ring that stands still, the hub's time items and covers, the circle), Dial II (no
 *    tick rings) and 24 h;
 *  - the fresh carousel's order (facepicker.js defaults(): S15 Concentric, Utility, Classic, ...,
 *    Big Time last);
 *  - screenshots at 10:09:30 and 06:42:05, awake and always-on, into /tmp/concentric-shots.
 * qmltestrunner under qemu-aarch64 with the image rootfs (offscreen, software Qt Quick); the face
 * needs org.asteroid.controls (Motion) from the image.
 */

import QtQuick
import QtTest
import "../../src/eoskit/facekit.js" as Kit
import "../../src/eoskit/concentric.js" as C
import "../../src/qml/misc/facepicker.js" as FP

Item {
    id: top
    width: 384
    height: 384

    // what the launcher gives a face (FaceLayer's context)
    property var wallClock: ({ time: new Date(2026, 10, 24, 10, 9, 29) })
    property var use12H: ({ value: true })
    property bool displayAmbient: false

    Rectangle { anchors.fill: parent; color: "black" }
    Loader { id: ld; anchors.fill: parent }
    // the digits' advances (A-21)
    FontMetrics { id: digitProbe; font.family: "Roboto"; font.pixelSize: 90 }

    readonly property string shots: "/tmp/concentric-shots/"

    TestCase {
        id: tc
        name: "Concentric"
        when: windowShown

        function near(a, b, eps) { return Math.abs(a - b) <= (eps === undefined ? 1e-6 : eps) }
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
        function visibleIn(item) {
            for (var i = item; i; i = i.parent)
                if (!i.visible || i.opacity <= 0)
                    return false
            return true
        }
        function visibleAll(item, name) { return findAll(item, name).filter(visibleIn) }
        // the scene point of a numeral's digits' middle
        function middleOf(t) {
            var p = t.mapToItem(top, t.implicitWidth / 2, Kit.DIGIT_CENTER * t.font.pixelSize)
            return p
        }

        // the face at a time; awake: the clock a second early and the sweep run to the time
        function show(h, m, s, ambient, use12, style) {
            ld.source = ""
            top.displayAmbient = ambient
            top.use12H = { value: use12 !== false }
            top.wallClock = { time: new Date(2026, 10, 24, h, m, ambient ? s : s - 1) }
            ld.source = Qt.resolvedUrl("../../src/watchfaces/027-concentric.qml")
            tryCompare(ld, "status", Loader.Ready, 20000)
            var f = ld.item
            if (style)
                f.eosStyle = { layout: style }
            if (!ambient)
                tryVerify(function () { return near(f.sweep, h * 3600 + m * 60 + s, 1e-3) }, 5000)
            else
                tryCompare(f, "blend", 1, 5000)
            wait(50)
            return f
        }
        function shoot(name) {
            var got = { ok: false }
            top.grabToImage(function (r) { got.r = r; got.ok = true })
            tryVerify(function () { return got.ok }, 10000)
            verify(got.r.saveToFile(top.shots + name), name)
        }

        // ---- the maths ----
        function test_angles() {
            // 10:09:30: the seconds dial has 30 in the pill, 35 a numeral up; the minutes dial 9.5
            var sw = 10 * 3600 + 9 * 60 + 30
            compare(C.secondsT(sw), 30)
            verify(near(C.minutesT(sw), 9.5))
            compare(C.numeralAngle(30, 30), 0)
            compare(C.numeralAngle(35, 30), 30)
            compare(C.numeralAngle(25, 30), -30)
            verify(near(C.numeralAngle(10, 9.5), 3))
            verify(near(C.numeralAngle(5, 9.5), -27))
            verify(near(C.ringTurn(9.5), 57))
            // 06:42:05: 05 in the pill; 40 and 45 round the minute 42 (and 5 s)
            sw = 6 * 3600 + 42 * 60 + 5
            compare(C.secondsT(sw), 5)
            verify(near(C.minutesT(sw), 42 + 5 / 60))
            compare(C.numeralAngle(5, 5), 0)
            compare(C.numeralAngle(0, 5), -30)
            verify(near(C.numeralAngle(40, 42 + 5 / 60), -12.5))
            verify(near(C.numeralAngle(45, 42 + 5 / 60), 17.5))
            // over the hour: 00 is 12 degrees above at :58, 55 42 degrees below at :02
            compare(C.numeralAngle(0, 58), 12)
            compare(C.numeralAngle(55, 2), -42)
            compare(C.numeralAngle(30, 0), 180)
            // across midnight the sweep goes on (86400 s is a whole number of minutes and hours)
            verify(near(C.secondsT(86399.5), 59.5))
            verify(near(C.minutesT(86399.5), 59 + 59.5 / 60))
            verify(near(C.minutesT(0), 0))
            // the stock place of 40 at 06:34 (S02: 35.7 degrees, bbox centre) is the whole minute
            verify(near(C.numeralAngle(40, 34), 36))
        }
        function test_points() {
            var p = C.pointAt(C.SECONDS_RADIUS, 0)
            verify(near(p.x, 352) && near(p.y, 192))
            p = C.pointAt(C.MINUTES_RADIUS, 90)
            verify(near(p.x, 192, 1e-9) && near(p.y, 86))
            // a numeral box centred on its point; snapped always-on
            var tl = C.numeralTopLeft(C.MINUTES_RADIUS, 30, 26, 1, 23, Kit.DIGIT_CENTER, true)
            compare(tl.x, Math.round(192 + 106 * Math.cos(Math.PI / 6) - 13))
            compare(tl.y, Math.round(192 - 106 * 0.5 - Kit.DIGIT_CENTER * 23))
            var l = C.tickLine(0, 124, 138)
            verify(near(l.x1, 316) && near(l.x2, 330) && near(l.y1, 192) && near(l.y2, 192))
        }
        function test_slots() {
            for (var m = 0; m < 60; m++) {
                var shown = 0
                for (var j = 0; j < 60; j++) {
                    var v = C.slotValue(j, m)
                    if (v >= 0) {
                        shown++
                        compare(v % 5, 0)
                        compare(C.slotOf(v, m), j)
                        // the numeral at slot j is at j * 6 degrees: the same as its angle at the minute
                        compare(C.norm(j * 6), C.numeralAngle(v, m))
                    }
                }
                compare(shown, 12)
            }
            compare(C.slotValue(3, 42), 45)
            compare(C.slotValue(58, 42), 40)
            compare(C.slotValue(1, 42), -1)
            compare(C.slotOf(0, 42), 18)
        }
        function test_pill_window() {
            compare(C.windowValue(30), 30)
            compare(C.windowValue(9.5), 10)
            compare(C.windowValue(5), 5)
            compare(C.windowValue(57.6), 0)
            compare(C.windowValue(42 + 5 / 60), 40)
            // which outer numerals are in the pill: only the one now
            var times = [30, 5, 59.5]
            var expect = [[30], [5], [0]]
            for (var i = 0; i < times.length; i++) {
                var inside = []
                for (var v = 0; v < 60; v += 5) {
                    var p = C.pointAt(C.SECONDS_RADIUS, C.numeralAngle(v, times[i]))
                    if (C.inPill(p.x, p.y))
                        inside.push(v)
                }
                compare(inside, expect[i], "seconds " + times[i])
            }
            // the inner numeral now is in the pill, under the black box
            var q = C.pointAt(C.MINUTES_RADIUS, C.numeralAngle(10, 9.5))
            verify(C.inPill(q.x, q.y))
            verify(q.x > C.SCRIM_RECT.x && q.x < C.SCRIM_RECT.x + C.SCRIM_RECT.w)
            verify(Math.abs(q.y - 192) < C.SCRIM_RECT.h / 2)
            // the pill: 170 wide awake (off the right edge), the 70 px circle always-on
            compare(C.pillWidth(0), 170)
            compare(C.pillWidth(1), 70)
            compare(C.pillWidth(0.5), 120)
            verify(C.PILL.cx - 35 + C.pillWidth(0) > 384)
            verify(!C.inPill(C.PILL.cx - 35, 150))
            verify(C.inPill(C.PILL.cx, C.PILL.cy - 34))
        }
        function test_hour_text() {
            compare(C.hourText(18, true), "06")
            compare(C.hourText(0, true), "12")
            compare(C.hourText(12, true), "12")
            compare(C.hourText(10, true), "10")
            compare(C.hourText(18, false), "18")
            compare(C.hourText(6, false), "06")
            compare(C.hourText(0, false), "00")
            compare(C.textColor("cloud"), "#ffffff")
            compare(C.textColor("nope"), "#ffffff")
            compare(C.textColor("ocean"), "#94bafa")
        }

        // ---- the face ----
        function test_awake() {
            var f = show(10, 9, 30, false, true)
            compare(f.blend, 0)
            verify(near(f.secondsT, 30, 1e-3))
            verify(near(f.minutesT, 9.5, 1e-3))
            var secs = findAll(f, "eosConcentricSecond")
            compare(secs.length, 12)
            for (var i = 0; i < secs.length; i++) {
                verify(visibleIn(secs[i]))
                var v = parseInt(secs[i].text, 10)
                var want = C.pointAt(C.SECONDS_RADIUS, C.numeralAngle(v, 30))
                var got = middleOf(secs[i])
                verify(near(got.x, want.x, 0.75) && near(got.y, want.y, 0.75), secs[i].text + " " + got.x + "," + got.y)
            }
            var mins = findAll(f, "eosHubDialNumeral")
            compare(mins.length, 12)
            for (i = 0; i < mins.length; i++) {
                v = parseInt(mins[i].text, 10)
                want = C.pointAt(C.MINUTES_RADIUS, C.numeralAngle(v, 9.5))
                got = middleOf(mins[i])
                verify(near(got.x, want.x, 0.75) && near(got.y, want.y, 0.75), mins[i].text)
            }
            // "30" is in the pill, left of the edge, on the middle line
            var thirty = secs.filter(function (t) { return t.text === "30" })[0]
            verify(near(middleOf(thirty).y, 192, 0.75))
            // the tick rings turn with the dials
            verify(near(find(f, "eosConcentricSecondsTicks").rotation, 180, 0.01))
            verify(near(find(f, "eosConcentricMinutesTicks").rotation, 57, 0.01))
            verify(!find(f, "eosConcentricAmbientTicks").visible)
            verify(find(f, "eosConcentricMinutesTicks").visible)
            verify(!find(f, "eosConcentricMinutesShortTicks").visible)
            verify(!find(f, "eosConcentricMinutesLongTicks").visible)
            // the pill: the stadium off the right edge; no disk, the box over the inner numerals
            var covers = findAll(f, "eosHubCover")
            compare(covers.length, 2)
            var pill = covers.filter(function (c) { return c.border.width > 0 })[0]
            compare(pill.x, 251)
            compare(pill.y, 157)
            compare(pill.width, 170)
            compare(pill.height, 70)
            compare(pill.border.width, 2)
            compare(String(pill.border.color), "#ffffff")
            verify(!covers.filter(function (c) { return c.border.width === 0 })[0].visible)
            verify(find(f, "eosConcentricScrim").visible)
            // the time: "10" and "09" in the awake weights
            var hourText = find(f, "eosConcentricHour")
            compare(hourText.text, "10")
            compare(find(f, "eosConcentricMinute").text, "09")
            verify(!find(f, "eosHubHour").visible)
            shoot("concentric-1009-awake.png")
        }
        function test_awake_0642() {
            var f = show(6, 42, 5, false, true)
            compare(find(f, "eosConcentricHour").text, "06")
            compare(find(f, "eosConcentricMinute").text, "42")
            var five = findAll(f, "eosConcentricSecond").filter(function (t) { return t.text === "05" })[0]
            verify(near(middleOf(five).y, 192, 0.75) && near(middleOf(five).x, 352, 0.75))
            shoot("concentric-0642-awake.png")
        }
        function test_ambient() {
            var f = show(6, 42, 5, true, true)
            compare(f.minutesT, 42)
            verify(!find(f, "eosConcentricSecondsDial").visible)
            verify(!find(f, "eosConcentricSecondsTicks").visible)
            verify(find(f, "eosConcentricAmbientTicks").visible)
            compare(find(f, "eosConcentricAmbientTicks").rotation, 0)
            // the inner ring: the short ticks stand still, the long ones turn with the minute
            verify(!find(f, "eosConcentricMinutesTicks").visible)
            verify(find(f, "eosConcentricMinutesShortTicks").visible)
            compare(find(f, "eosConcentricMinutesShortTicks").rotation, 0)
            verify(find(f, "eosConcentricMinutesLongTicks").visible)
            compare(find(f, "eosConcentricMinutesLongTicks").rotation, 42 * 6)
            verify(!find(f, "eosConcentricScrim").visible)
            // the dial: on the whole minute, every numeral at the hub's slot origin
            var dial = find(f, "eosHubDial")
            compare(dial.eosHubMinute, 42)
            var mins = findAll(f, "eosHubDialNumeral")
            compare(mins.length, 12)
            for (var i = 0; i < mins.length; i++) {
                var v = parseInt(mins[i].text, 10)
                var o = dial.eosHubSlotOrigin(C.slotOf(v, 42))
                compare(mins[i].x, o.x, mins[i].text)
                compare(mins[i].y, o.y, mins[i].text)
                compare(mins[i].x, Math.round(mins[i].x))
            }
            // the long ticks: 12, each where eosHubTick puts the long tick of its slot
            var ticks = visibleAll(f, "eosHubDialTick")
            compare(ticks.length, 12)
            var seen = {}
            for (i = 0; i < ticks.length; i++) {
                var mid = ticks[i].mapToItem(dial, ticks[i].width / 2, ticks[i].height / 2)
                var best = -1
                for (var j = 0; j < 60; j++) {
                    var l = dial.eosHubTick(j)
                    if (near((l.x1 + l.x2) / 2, mid.x, 0.01) && near((l.y1 + l.y2) / 2, mid.y, 0.01))
                        best = j
                }
                verify(best >= 0, "tick " + i)
                compare(C.slotValue(best, 42) >= 0, true)
                seen[best] = true
            }
            compare(Object.keys(seen).length, 12)
            // the hub's time items: two digits in 12 h, the always-on weight, fully on
            var hh = find(f, "eosHubHour"), mm = find(f, "eosHubMinute")
            compare(hh.text, "06")
            compare(mm.text, "42")
            verify(visibleIn(hh) && visibleIn(mm))
            compare(hh.opacity, 1)
            compare(hh.eosHubZeroPad, true)
            compare(hh.renderType, Text.NativeRendering)
            compare(hh.font.weight, Font.Light)
            compare(hh.font.pixelSize, 90)
            compare(mm.font.pixelSize, 40)
            // the covers: the black disk and the 70 px circle, both visible
            var covers = visibleAll(f, "eosHubCover")
            compare(covers.length, 2)
            var disk = covers.filter(function (c) { return c.border.width === 0 })[0]
            compare(String(disk.color), "#000000")
            compare(disk.x, 254)
            compare(disk.width, 68)
            var ring = covers.filter(function (c) { return c.border.width > 0 })[0]
            compare(ring.width, 70)
            compare(ring.radius, 35)
            shoot("concentric-0642-ambient.png")
            // the hour, the minute and the dial's turn at another minute
            f = show(10, 9, 30, true, true)
            compare(find(f, "eosHubHour").text, "10")
            compare(find(f, "eosHubMinute").text, "09")
            compare(find(f, "eosConcentricMinutesLongTicks").rotation, 54)
            compare(find(f, "eosConcentricMinutesShortTicks").rotation, 0)
            shoot("concentric-1009-ambient.png")
        }
        function test_dial2_and_24h() {
            var f = show(18, 5, 0, true, false, "dial2")
            compare(f.ticksShown, false)
            compare(visibleAll(f, "eosHubDialTick").length, 0)
            verify(!find(f, "eosConcentricAmbientTicks").visible)
            verify(!find(f, "eosConcentricMinutesTicks").visible)
            verify(!find(f, "eosConcentricMinutesShortTicks").visible)
            verify(!find(f, "eosConcentricMinutesLongTicks").visible)
            compare(find(f, "eosHubHour").text, "18")
            compare(find(f, "eosHubMinute").text, "05")
            compare(visibleAll(f, "eosHubDialNumeral").length, 12)
            ld.source = ""
        }

        // ---- A-06: Half Dial ----
        function test_a06_half_numbers() {
            compare(C.LAYOUTS, ["dial1", "dial2", "half"])
            compare(C.LAYOUT_NAMES[2], "Half Dial")
            compare(C.shiftOf("half"), -142)
            compare(C.shiftOf("dial1"), 0)
            // the pill: 70 + 66 px awake (circle centres 143 and 176 units), the 70 px circle always-on
            compare(C.pillWidth(0, C.pillReach("half")), 136)
            compare(C.pillWidth(1, C.pillReach("half")), 70)
            compare(C.pillWidth(0, C.pillReach("dial1")), 170)
            // the hour: 40 units of 44, its first digit's ink 0.7 px from the left edge after the shift
            compare(C.HALF.hourPx, Math.round(C.HOUR.px * 40 / 44))
            verify(near(C.HALF.hourInkLeft + C.HALF.shift, 0.727, 0.001))
            // the vignette: the left half, nothing inside 151.2 px, black at 201.6 px; 81 % at the bezel
            compare(C.vignetteAt(192, 192), 0)
            compare(C.vignetteAt(192 - 151, 192), 0)
            verify(near(C.vignetteAt(0, 192), (192 / 201.6 - 0.75) / 0.25, 1e-9))
            verify(near(C.vignetteAt(192, 0), C.vignetteAt(0, 192), 1e-9))
            compare(C.vignetteAt(300, 10), 0)
            // the bulbs: 86 px at the stock bounds x 2
            compare(C.HALF.bulbs.top.x, 222.4)
            compare(C.HALF.bulbs.center.y, 150)
            compare(C.HALF.bulbs.bottom.y, 262)
            compare(C.HALF.defaults, { top: "weather", center: "datemonth", bottom: "heartrate" })
        }
        function test_a06_half_awake() {
            var f = show(10, 9, 30, false, true, "half")
            compare(f.half, true)
            compare(f.ticksShown, true)
            compare(find(f, "eosConcentricDialLayer").x, -142)
            compare(find(f, "eosConcentricTimeLayer").x, -142)
            // the dials round x 50: "30" of the seconds dial in the pill at 3 o'clock
            var thirty = findAll(f, "eosConcentricSecond").filter(function (t) { return t.text === "30" })[0]
            verify(near(middleOf(thirty).x, 50 + 160, 0.75) && near(middleOf(thirty).y, 192, 0.75))
            var ten = findAll(f, "eosHubDialNumeral").filter(function (t) { return t.text === "10" })[0]
            var want = C.pointAt(C.MINUTES_RADIUS, C.numeralAngle(10, 9.5))
            verify(near(middleOf(ten).x, want.x - 142, 0.75) && near(middleOf(ten).y, want.y, 0.75))
            // the pill: from x 109, 136 wide
            var pill = findAll(f, "eosHubCover").filter(function (c) { return c.border.width > 0 })[0]
            var pr = pill.mapToItem(top, 0, 0)
            compare(pr.x, 109)
            compare(pill.width, 136)
            // the hour 82 px, its ink at the bezel; the minute in the pill
            var hour = find(f, "eosConcentricHour")
            compare(hour.px, 82)
            verify(near(hour.mapToItem(top, hour.inkLeft, 0).x, 0.727, 0.01))
            var minute = find(f, "eosConcentricMinute")
            verify(near(minute.mapToItem(top, minute.inkLeft, 0).x, 266.5 - 142, 0.01))
            // the three bulbs, active, where stock has them
            var slots = findAll(f, "eosComplication")
            compare(slots.length, 3)
            var ids = ["top", "center", "bottom"]
            for (var i = 0; i < 3; i++) {
                var s = slots.filter(function (x) { return x.slotId === ids[i] })[0]
                verify(s.visible && s.eosActive, ids[i])
                var b = C.HALF.bulbs[ids[i]]
                var p = s.mapToItem(top, 0, 0)
                verify(near(p.x, b.x, 0.01) && near(p.y, b.y, 0.01), ids[i] + " " + p.x + "," + p.y)
                compare(s.width, 86)
                compare(s.shape, "bulb")
                compare(s.defaultSource, C.HALF.defaults[ids[i]])
            }
            // the vignette over the dial, under the pill and the time
            var shade = find(f, "eosHubShade")
            verify(visibleIn(shade))
            compare(shade.eosHubShadeRadius, 201.6)
            compare(shade.eosHubShadeFrom, 0.75)
            verify(shade.z <= pill.parent.z)
            shoot("concentric-half-1009-awake.png")
        }
        function test_a06_half_ambient() {
            var f = show(6, 42, 5, true, true, "half")
            verify(!find(f, "eosConcentricSecondsDial").visible)
            verify(find(f, "eosConcentricAmbientTicks").visible)
            // the dial on the whole minute at the hub's slot origins (in the moved dial)
            var dial = find(f, "eosHubDial")
            var mins = findAll(f, "eosHubDialNumeral")
            for (var i = 0; i < mins.length; i++) {
                var o = dial.eosHubSlotOrigin(C.slotOf(parseInt(mins[i].text, 10), 42))
                compare(mins[i].x, o.x, mins[i].text)
                compare(mins[i].y, o.y, mins[i].text)
            }
            // the pill is the 70 px circle at x 109; both covers on
            var covers = visibleAll(f, "eosHubCover")
            compare(covers.length, 2)
            var ring = covers.filter(function (c) { return c.border.width > 0 })[0]
            compare(ring.width, 70)
            compare(ring.mapToItem(top, 0, 0).x, 109)
            // the hub's time items: the hour at 82 px, Light
            compare(find(f, "eosHubHour").font.pixelSize, 82)
            compare(find(f, "eosHubHour").text, "06")
            // the bulbs dimmed (the slots' always-on opacity), the vignette still there
            var slots = visibleAll(f, "eosComplication")
            compare(slots.length, 3)
            verify(near(slots[0].opacity, Kit.AMBIENT_SLOT_ALPHA, 1e-6))
            verify(visibleIn(find(f, "eosHubShade")))
            shoot("concentric-half-0642-ambient.png")
        }
        function test_a06_dial1_unchanged() {
            var f = show(10, 9, 30, false, true)
            compare(find(f, "eosConcentricDialLayer").x, 0)
            verify(!find(f, "eosHubShade").visible)
            compare(visibleAll(f, "eosComplication").length, 0)
            compare(find(f, "eosConcentricHour").px, 90)
            ld.source = ""
        }

        // ---- A-21: the font is Roboto (the user's choice: keep the current font), digits one advance wide ----
        function allTexts(item, out) {
            out = out || []
            if (!item)
                return out
            if (item.font !== undefined && item.text !== undefined && item.horizontalAlignment !== undefined)
                out.push(item)
            var d = item.children
            if (d)
                for (var i = 0; i < d.length; i++)
                    allTexts(d[i], out)
            return out
        }
        function test_a21_roboto() {
            compare(Kit.FONT, "Roboto")
            var modes = [false, true]
            for (var a = 0; a < modes.length; a++) {
                var f = show(10, 9, 30, modes[a], true)
                var texts = allTexts(f)
                verify(texts.length >= 28, "numerals, hour and minute: " + texts.length)
                for (var i = 0; i < texts.length; i++) {
                    compare(texts[i].font.family, "Roboto", texts[i].objectName + " " + texts[i].text)
                    compare(texts[i].renderType, Text.NativeRendering, texts[i].objectName)
                }
            }
            // the hub's glyph cells: every digit one advance wide in the dial's and the time's weights
            var weights = [Font.Light, Font.Normal, Font.Medium]
            for (var w = 0; w < weights.length; w++) {
                digitProbe.font.weight = weights[w]
                var adv = digitProbe.advanceWidth("0")
                for (var dgt = 1; dgt <= 9; dgt++)
                    compare(digitProbe.advanceWidth(String(dgt)), adv, "weight " + weights[w] + " digit " + dgt)
            }
            ld.source = ""
        }

        // ---- the fresh carousel (facepicker.js) ----
        function test_carousel_order() {
            // the faces of the image, in their folder's order
            var installed = ["000-default-digital.qml", "010-analog-aviator.qml", "018-modular.qml", "019-list.qml",
                             "020-stacked.qml", "021-classic.qml", "022-large.qml", "023-bold-numerals.qml",
                             "027-concentric.qml", "028-big-time.qml", "029-analog-arcs.qml"].map(function (f) {
                return "file:///usr/share/asteroid-launcher/watchfaces/" + f
            })
            var current = "file:///usr/share/asteroid-launcher/watchfaces/027-concentric.qml"
            var names = FP.defaults(installed, current).map(function (e) { return FP.plainName(e.file) })
            // S15: Concentric, Utility, Classic, ..., Big Time last (A-07); the face on the watch once
            compare(names[0], "concentric")
            compare(names[1], "modular")
            compare(names[2], "classic")
            compare(names[names.length - 1], "big-time")
            compare(names.length, 9)
            compare(names, ["concentric", "modular", "classic", "bold-numerals", "list", "stacked",
                            "default-digital", "analog-arcs", "big-time"])
        }
    }
}
