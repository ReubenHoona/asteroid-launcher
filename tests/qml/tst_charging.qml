// SPDX-License-Identifier: BSD-3-Clause
//
// The rules and numbers of the charging screen (src/qml/charging/charging.js), as
// stock CP3A's ChargingComposeActivity in the Wear OS 6 emulator's look (N61-18,
// S03-c): layout (charging-battery-01, the measure policy imm.java, the unread dot's
// slot), level and colours (-08), clock and chip (ICU "EEE d" through
// org.asteroid.utils DateFormat), intro (-06), pulse (-07), plug and unplug
// (-02, -03), the quality screen rule (app-inventory-03) and the bolt glyph, whose
// vertices must be Qt.point values for PathPolyline (D60-10). Staged as module
// LauncherQml: charging/ (the four files of src/qml/charging),
// complications/ClockSource.qml (the tests/qml/stage double) and
// compositor/windowmotion.js; the real org.asteroid.utils (ICU), not the mock.
// Run by motion-wt/wo04/run.sh (qmltestrunner under qemu-aarch64 on the image rootfs).
import QtQuick
import QtTest
import org.asteroid.utils
import "LauncherQml/charging/charging.js" as Charging

TestCase {
    name: "ChargingRules"

    function near(a, b, eps, msg) { verify(Math.abs(a - b) <= eps, (msg || "") + " " + a + " vs " + b) }

    // the bolt as PathPolyline reads it
    Path {
        id: boltPath
        PathPolyline { id: boltLine; path: Charging.boltClosed() }
    }
    Path {
        id: halfPath
        PathPolyline { id: halfLine; path: Charging.partial(Charging.boltHalves().a, 0.5) }
    }

    // ---- layout: charging-battery-01, imm.java
    function test_layout_numbers() {
        var L = Charging.LAYOUT
        compare(L.ringStrokeDp, 8)
        compare(L.ringInsetDp, 2)
        near(L.ringGapDp, 8 / 3, 1e-9)
        compare(L.ringAlpha, 1)
        compare(L.percentTopDp, 16)
        compare(L.percentWeight, 500)
        compare(L.boltDp, 24)
        compare(L.boltGapDp, 6)
        compare(L.pillGapDp, 4)
        compare(L.hoursCornerDp, 40)
        compare(L.minutesCornerDp, 26)
        compare(L.digitSp, 53)
        compare(L.digitWeight, 800)
        compare(L.digitRiseDp, 1.75)
        compare(L.chipPadXDp, 6)
        compare(L.chipPadYDp, 0)
        compare(L.chipIconDp, 16)
        compare(L.chipIconGapDp, 8)
        // the layout sits in the screen's 2 dp padding (mnw.java); the bottom slot 12 dp above
        // its bottom under 225 dp, 14 dp from 225 dp (imm.java)
        compare(L.padDp, 2)
        compare(L.slotBottomDp, 12)
        compare(L.slotBottomLargeDp, 14)
        compare(L.largeScreenDp, 225)
        verify(L.chipGapDp === undefined)
        verify(L.unreadBottomDp === undefined)
        // the unread dot: 5 dp, in the bottom slot (S03-c)
        compare(L.unreadDp, 5)
        // pills: (192 - 192 * 0.1666 - 4) / 2 = 78 dp, 0.3646 of 192 = 70 dp
        near(Charging.pillWidthDp(192), 78, 0.01)
        near(Charging.pillHeightDp(192), 70, 0.01)
    }
    function test_bottom_slot_and_chip_place() {
        // PW2 (192 dp): 2 + 12 = 14 dp from the edge; a 225 dp screen: 2 + 14 = 16 dp
        compare(Charging.slotBottomDp(192), 14)
        compare(Charging.slotBottomDp(224), 14)
        compare(Charging.slotBottomDp(225), 16)
        // the chip is centred between the clock's bottom and the slot's top (imm.java):
        // 384 px: clock 122..262 px, slot top 384 - 28 = 356 px, a 56 px chip -> 281 px
        compare(Charging.chipTop(262, 356, 56), 281)
        compare(Charging.chipTop(262, 356, 32), 293)
        // the slot is the dot's: 5 dp with unread notifications, else empty (its top is its bottom)
        compare(Charging.slotHeightDp(true), 5)
        compare(Charging.slotHeightDp(false), 0)
        compare(Charging.chipTop(262, 384 - 2 * Charging.slotBottomDp(192), 32), 293)
        // with the dot: (262 + 346 - 32) / 2 = 288, the emulator's chip top (S03-c, y 288-319)
        compare(Charging.chipTop(262, 384 - 2 * (Charging.slotBottomDp(192) + Charging.slotHeightDp(true)), 32), 288)
    }

    // ---- level and colours: charging-battery-08
    function test_level_and_low() {
        compare(Charging.LOW_LEVEL, 15)
        compare(Charging.clampLevel(82), 82)
        compare(Charging.clampLevel(82.4), 82)
        compare(Charging.clampLevel(-1), 0)
        compare(Charging.clampLevel(130), 100)
        compare(Charging.clampLevel(undefined), 0)
        verify(Charging.isLow(15))
        verify(!Charging.isLow(16))
        verify(Charging.isLow(0))
        verify(!Charging.isLow(100))
    }
    function test_roles() {
        var n = Charging.roles(false), l = Charging.roles(true)
        // the emulator's (S03-c, C8)
        compare(n.ring.join(), "primaryDim,1")
        compare(n.track.join(), "surfaceContainerLow,1")
        compare(n.pill.join(), "surfaceContainerLow,1")
        compare(n.digit.join(), "onSurface,1")
        compare(n.chip.join(), "surfaceContainerLow,1")
        compare(n.chipText.join(), "tertiaryDim,1")
        compare(n.percent.join(), "tertiaryDim,1")
        compare(n.bolt.join(), "tertiaryDim,0.96")
        // the low set and the intro bolt stay CP3A's (no capture under 15 %)
        compare(l.ring.join(), "errorDim,0.8")
        compare(l.track.join(), "error,0.48")
        compare(l.pill.join(), "onError,1")
        compare(l.digit.join(), "errorDim,1")
        compare(l.chip.join(), "onError,1")
        compare(l.chipText.join(), "errorDim,1")
        compare(l.percent.join(), "onBackground,0.8")
        compare(l.bolt.join(), "onBackground,0.8")
        compare(Charging.COLOR_MS, 300)
        compare(Charging.introBoltRole(false).join(), "primaryDim,0.8")
        compare(Charging.introBoltRole(true).join(), "errorDim,0.8")
    }

    // ---- the clock and the chip
    function test_clock_parts() {
        var d = new Date(2026, 10, 14, 0, 5)
        compare(Charging.clockParts(d, true).hours, "12")
        compare(Charging.clockParts(d, true).minutes, "05")
        compare(Charging.clockParts(d, false).hours, "00")
        d = new Date(2026, 10, 14, 12, 30)
        compare(Charging.clockParts(d, true).hours, "12")
        compare(Charging.clockParts(d, false).hours, "12")
        d = new Date(2026, 10, 14, 13, 7)
        compare(Charging.clockParts(d, true).hours, "01")     // zero padded 'hh', no AM/PM
        compare(Charging.clockParts(d, true).minutes, "07")
        compare(Charging.clockParts(d, false).hours, "13")
        d = new Date(2026, 10, 14, 23, 59)
        compare(Charging.clockParts(d, true).hours, "11")
        compare(Charging.clockParts(d, false).hours, "23")
    }
    // D60-11: the date is ICU's best pattern for the skeleton "EEE d" in the locale (ini.java:2651)
    function test_date_skeleton() {
        compare(Charging.DATE_SKELETON, "EEE d")
        var d = new Date(2026, 10, 23, 13, 7)                   // a Monday
        function inLocale(loc) { return function (dt, sk) { return DateFormat.format(dt, sk, loc) } }
        compare(Charging.dateText(d, inLocale("en_US")), "23 Mon")
        compare(Charging.dateText(d, inLocale("en")), "23 Mon")
        compare(Charging.dateText(d, inLocale("C")), "23 Mon")      // Qt's C = ICU's en_US
        compare(Charging.dateText(d, inLocale("en_GB")), "Mon 23")
        compare(Charging.dateText(d, inLocale("en_NZ")), "Mon 23")
        compare(Charging.dateText(d, inLocale("de_DE")), "Mo., 23.")
        compare(Charging.dateText(d, inLocale("fr_FR")), "lun. 23")
        compare(Charging.dateText(d, inLocale("ja_JP")), "23日(月)")
        // the skeleton is ICU's, with or without the space
        compare(DateFormat.icuPattern(Charging.DATE_SKELETON, "en_US"), "d EEE")
        compare(DateFormat.icuPattern("EEEd", "en_US"), "d EEE")
        compare(DateFormat.icuPattern(Charging.DATE_SKELETON, "en_GB"), "EEE d")
    }
    function test_chip_date_or_alarm() {
        var fmt = function (dt, sk) { return DateFormat.format(dt, sk, "en_US") }
        var now = new Date(2026, 10, 13, 22, 0)                 // a Friday
        var h = 3600 * 1000
        // no alarm: the date 'EEE d'
        var c = Charging.chip(now, 0, false, "AM", "PM", fmt)
        compare(c.kind, "date")
        compare(c.text, "13 Fri")
        compare(Charging.chip(now, 0, false, "AM", "PM", function (dt, sk) { return DateFormat.format(dt, sk, "en_GB") }).text, "Fri 13")
        // an alarm in 9 h: its time, 'HHmm' in 24 h and 'hmm' in 12 h
        var at = new Date(now.getTime() + 9 * h)                // 07:00 Saturday
        c = Charging.chip(now, at.getTime(), false, "AM", "PM", fmt)
        compare(c.kind, "alarm")
        compare(c.text, "07:00")
        c = Charging.chip(now, at.getTime(), true, "AM", "PM", fmt)
        compare(c.text, "7:00 AM")
        at = new Date(2026, 10, 14, 19, 5)
        compare(Charging.alarmText(at, true, "AM", "PM"), "7:05 PM")
        compare(Charging.alarmText(new Date(2026, 10, 14, 0, 30), true, "AM", "PM"), "12:30 AM")
        // the 24 h limit: exactly 24 h counts, a minute more does not; a past alarm does not
        verify(Charging.alarmShown(now.getTime(), now.getTime() + 24 * h))
        verify(!Charging.alarmShown(now.getTime(), now.getTime() + 24 * h + 60000))
        verify(!Charging.alarmShown(now.getTime(), now.getTime() - 1))
        verify(!Charging.alarmShown(now.getTime(), 0))
        compare(Charging.chip(now, now.getTime() + 25 * h, false, "AM", "PM", fmt).kind, "date")
    }

    // ---- curves and springs
    function test_bezier_and_spring() {
        compare(Charging.bezier(0.2, 0, 0, 1, 0), 0)
        compare(Charging.bezier(0.2, 0, 0, 1, 1), 1)
        verify(Charging.bezier(0.2, 0, 0, 1, 0.5) > 0.8)        // ease out: most of the way early
        near(Charging.bezier(0.25, 0.25, 0.75, 0.75, 0.3), 0.3, 1e-4)   // linear
        var prev = 0
        for (var i = 1; i <= 20; i++) {
            var v = Charging.bezier(0.094, 0.497, 0.342, 1, i / 20)
            verify(v >= prev)
            prev = v
        }
        // 1 - (1 + wt) e^(-wt): at wt = 1 it is 1 - 2/e
        near(Charging.springAt(1000 / Math.sqrt(500), 500), 1 - 2 / Math.E, 1e-9)
        compare(Charging.springAt(0, 75), 0)
        verify(Charging.springAt(5000, 75) > 0.9999)
        // the slow spring (75) takes about 770 ms to 99 % (6.64 / sqrt(k))
        near(Charging.springSettle(75, 0.99), 767, 3)
        near(Charging.springSettle(260, 0.99), 412, 3)
        near(Charging.springSettle(1400, 0.99), 177, 3)
    }

    // ---- the intro: charging-battery-06
    function test_intro_constants() {
        var I = Charging.INTRO
        near(I.scaleFrom, 2.83333, 1e-4)
        near(I.scaleTo, 1.0625, 1e-9)
        compare(I.scaleMs, 1000)
        compare(I.traceMs, 500)
        compare(I.strokeFromPx, 2.5)
        compare(I.strokeStart, 167)
        compare(I.strokeEnd, 500)
        compare(I.fillStart, 167)
        compare(I.fillEnd, 500)
        compare(I.outlineFadeStart, 267)
        compare(I.outlineFadeEnd, 583)
        compare(I.ringStiffness, 75)
        compare(I.ringScaleStiffness, 1400)
        near(I.ringScaleFrom, 0.9, 1e-9)
        compare(I.ringRotationFrom, -90)
        compare(I.riseDp, 24)
        compare(I.riseStiffness, 500)
        compare(I.riseFadeStiffness, 260)
        compare(I.clockDelay, 50)
        compare(I.chipDelay, 100)
        compare(I.boltMoveStiffness, 500)
        // the whole intro is over in about two seconds
        verify(Charging.INTRO_END > 1900 && Charging.INTRO_END < 2300, "end " + Charging.INTRO_END)
    }
    function test_intro_bolt_phase() {
        var a = Charging.introAt(0)
        compare(a.trace, 0)
        near(a.boltScale, 2.83333, 1e-4)
        near(a.stroke, 2.5, 1e-9)
        compare(a.fill, 0)
        compare(a.outline, 1)
        compare(a.ring, 0)
        compare(a.percent, 0)
        compare(a.boltMove, 0)
        compare(a.clockFade, 0)
        compare(a.chipFade, 0)
        compare(a.dot, 0)
        // 250 ms: the outline is tracing, the fill is starting, the stroke is thinning
        var m = Charging.introAt(250)
        verify(m.trace > 0.5 && m.trace < 1, "trace " + m.trace)
        verify(m.fill > 0 && m.fill < 1)
        verify(m.stroke > 0 && m.stroke < 2.5)
        compare(m.outline, 1)
        verify(m.boltScale < 2.83333 && m.boltScale > 1.0625)
        // 500 ms: traced, filled, stroke 0
        var b = Charging.introAt(500)
        compare(b.trace, 1)
        compare(b.fill, 1)
        compare(b.stroke, 0)
        verify(b.outline < 1 && b.outline > 0)
        // 583 ms: the outline is gone
        compare(Charging.introAt(583).outline, 0)
        // 1000 ms: scale 1.06, the ring has not started
        var c = Charging.introAt(1000)
        near(c.boltScale, 1.0625, 1e-9)
        compare(c.ring, 0)
        compare(c.ringRotation, -90)
        near(c.ringScale, 0.9, 1e-9)
        // the scale never goes up
        var prev = 10
        for (var t = 0; t <= 1000; t += 50) {
            var s = Charging.introAt(t).boltScale
            verify(s <= prev + 1e-9)
            prev = s
        }
    }
    function test_intro_ring_and_rise() {
        // 300 ms after the ring fires: progress, rotation and scale are on their springs
        var t = Charging.INTRO.ringAt + 300
        var r = Charging.introAt(t)
        near(r.ring, Charging.springAt(300, 75), 1e-12)
        near(r.ringRotation, -90 * (1 - Charging.springAt(300, 75)), 1e-9)
        near(r.ringScale, 0.9 + 0.1 * Charging.springAt(300, 1400), 1e-9)
        near(r.percent, Charging.springAt(300, 260), 1e-12)
        near(r.boltMove, Charging.springAt(300, 500), 1e-12)
        // the clock starts 50 ms after the ring, the chip 100 ms, the bottom slot 150 ms
        near(r.clockRise, Charging.springAt(250, 500), 1e-12)
        near(r.clockFade, Charging.springAt(250, 260), 1e-12)
        near(r.chipRise, Charging.springAt(200, 500), 1e-12)
        near(r.chipFade, Charging.springAt(200, 260), 1e-12)
        near(r.dot, Charging.springAt(150, 260), 1e-12)
        verify(r.clockRise > r.chipRise)
        compare(Charging.introAt(Charging.INTRO.ringAt + 40).clockFade, 0)
        compare(Charging.introAt(Charging.INTRO.ringAt + 90).chipFade, 0)
        compare(Charging.introAt(Charging.INTRO.ringAt + 140).dot, 0)
        // the end: everything at rest
        var e = Charging.introAt(Charging.INTRO_END)
        verify(e.ring > 0.998 && e.ringScale > 0.9999 && e.clockFade > 0.998 && e.chipFade > 0.998 && e.dot > 0.998)
        verify(Math.abs(e.ringRotation) < 0.1)
        compare(e.trace, 1)
        compare(e.fill, 1)
        compare(e.outline, 0)
        compare(e.stroke, 0)
    }

    // ---- the pulse: charging-battery-07
    function test_pulse_keyframes() {
        compare(Charging.PULSE.loopMs, 3000)
        compare(Charging.PULSE.holdMs, 1000)
        compare(Charging.PULSE.low, 0.3)
        compare(Charging.PULSE.curve.join(), "0.2,0,0,1")
        compare(Charging.pulseAlpha(0), 1)
        compare(Charging.pulseAlpha(1000), 1)
        near(Charging.pulseAlpha(2000), 0.3, 1e-9)
        near(Charging.pulseAlpha(3000), 1, 1e-9)
        near(Charging.pulseAlpha(4500), Charging.pulseAlpha(1500), 1e-9)
        // the ramps ease out: halfway in time is over halfway in value
        verify(Charging.pulseAlpha(1500) < 0.65)
        verify(Charging.pulseAlpha(2500) > 0.65)
        var prev = 1
        for (var t = 1000; t <= 2000; t += 100) {
            var a = Charging.pulseAlpha(t)
            verify(a <= prev + 1e-9)
            prev = a
        }
    }
    function test_pulse_runs() {
        verify(Charging.pulseRuns(82, true, true))
        verify(Charging.pulseRuns(99, true, true))
        verify(!Charging.pulseRuns(100, true, true))
        verify(!Charging.pulseRuns(82, false, true))
        verify(!Charging.pulseRuns(82, true, false))
    }

    // ---- plug and unplug: charging-battery-02, -03
    function test_plug_in() {
        var r = Charging.plugChange({ plugged: true, was: false, theater: false, bedtime: false, displayOff: true })
        verify(r.show && r.wake && r.intro)
        verify(!r.linger && !r.hide)
        verify(r.sound)                     // the plug-in sound (ngfd eos_charging_sound)
        verify(r.feedback === undefined)    // no plug-in vibration (FP-C1: stock plays none)
        r = Charging.plugChange({ plugged: true, was: false, theater: false, bedtime: false, displayOff: false })
        verify(r.show && r.wake && r.intro && r.sound)
        // Do Not Disturb: the screen as usual, no sound
        r = Charging.plugChange({ plugged: true, was: false, theater: false, bedtime: false, dnd: true, displayOff: false })
        verify(r.show && r.wake && r.intro && !r.sound)
        // Theater: no wake; the intro only if the display is on anyway; no sound
        r = Charging.plugChange({ plugged: true, was: false, theater: true, bedtime: false, displayOff: true })
        verify(r.show && !r.wake && !r.intro && !r.sound)
        r = Charging.plugChange({ plugged: true, was: false, theater: true, bedtime: false, displayOff: false })
        verify(r.show && !r.wake && r.intro && !r.sound)
        // Bedtime: the screen stays dark, no sound
        r = Charging.plugChange({ plugged: true, was: false, theater: false, bedtime: true, displayOff: true })
        verify(r.show && !r.wake && !r.intro && !r.sound)
        r = Charging.plugChange({ plugged: true, was: false, theater: false, bedtime: true, displayOff: false })
        verify(r.show && !r.wake && r.intro && !r.sound)
    }
    function test_unplug() {
        var r = Charging.plugChange({ plugged: false, was: true, theater: false, bedtime: false, displayOff: true })
        verify(r.wake && r.linger && !r.show && !r.hide && !r.intro)
        verify(!r.sound)                    // the unplug plays nothing
        r = Charging.plugChange({ plugged: false, was: true, theater: true, bedtime: false, displayOff: true })
        verify(!r.wake && !r.linger && r.hide)
        r = Charging.plugChange({ plugged: false, was: true, theater: true, bedtime: false, displayOff: false })
        verify(!r.wake && r.linger && !r.hide)
        r = Charging.plugChange({ plugged: false, was: true, theater: false, bedtime: true, displayOff: true })
        verify(!r.wake && r.hide)
        compare(Charging.UNPLUG_HOLD_MS, 1000)
        compare(Charging.FADE_STIFFNESS, 260)
        // no change, no action
        r = Charging.plugChange({ plugged: true, was: true })
        verify(!r.show && !r.wake && !r.linger && !r.hide && !r.sound)
        verify(Charging.wakesOnPlug(false, false))
        verify(!Charging.wakesOnPlug(true, false))
        verify(!Charging.wakesOnPlug(false, true))
    }
    function test_screen_up_table() {
        verify(Charging.screenUp(true, false, false))
        verify(!Charging.screenUp(true, true, false))     // the crown closed it
        verify(!Charging.screenUp(false, false, false))
        verify(Charging.screenUp(false, false, true))     // the 1 s after the unplug
        verify(Charging.screenUp(true, true, true))
    }

    // ---- the charging quality screen: app-inventory-03
    function test_quality_rule() {
        compare(Charging.PROBLEM.misalignedAfterMs, 30000)
        compare(Charging.PROBLEM.moistureRecheckMs, 65000)
        compare(Charging.PROBLEM.iconDp, 24)
        compare(Charging.problemText("misaligned"), "Check if charger is aligned and has power")
        compare(Charging.problemText("moisture"), "Dry watch and charger, wait 1 min for charging to resume")
        compare(Charging.problemText("unsupported"), "Unsupported charger")
        verify(Charging.misaligned({ plugged: true, charging: false, full: false }))
        verify(!Charging.misaligned({ plugged: true, charging: true, full: false }))
        verify(!Charging.misaligned({ plugged: true, charging: false, full: true }))
        verify(!Charging.misaligned({ plugged: false, charging: false, full: false }))
    }

    // ---- the bolt glyph
    function test_bolt_paths() {
        var h = Charging.boltHalves()
        compare(h.a.length, 4)
        compare(h.b.length, 4)
        // both sides run from the top to the tip
        compare(h.a[0].join(), h.b[0].join())
        compare(h.a[3].join(), h.b[3].join())
        compare(Charging.partial(h.a, 0).length, 1)
        compare(Charging.partial(h.a, 1).length, 4)
        var half = Charging.partial(h.a, 0.5)
        verify(half.length >= 2 && half.length <= 4)
        var len = 0, total = 0, i
        for (i = 1; i < half.length; i++) len += Math.hypot(half[i].x - half[i - 1].x, half[i].y - half[i - 1].y)
        for (i = 1; i < h.a.length; i++) total += Math.hypot(h.a[i][0] - h.a[i - 1][0], h.a[i][1] - h.a[i - 1][1])
        near(len, total / 2, 1e-6)
        compare(Charging.boltClosed().length, 7)
        // 20 of 24 units tall, as the 24 dp ic_power
        var ys = Charging.BOLT.points.map(function (p) { return p[1] })
        near(Math.max.apply(null, ys) - Math.min.apply(null, ys), 20, 1e-9)
    }
    // D60-10: PathPolyline takes Qt.point vertices only; plain {x, y} objects all read as 0,0
    function test_bolt_vertices_are_points() {
        var c = Charging.boltClosed(), p = Charging.BOLT.points
        for (var i = 0; i < c.length; i++) {
            compare(c[i], Qt.point(p[i % p.length][0], p[i % p.length][1]), "vertex " + i)
            compare(String(c[i]), String(Qt.point(p[i % p.length][0], p[i % p.length][1])))
        }
        var half = Charging.partial(Charging.boltHalves().a, 0.5)
        for (i = 0; i < half.length; i++)
            compare(String(half[i]), String(Qt.point(half[i].x, half[i].y)))
        // as the Path of Bolt.qml reads them: the polyline starts at the top vertex and the
        // path has the bolt's length, not 0
        compare(boltLine.start, Qt.point(13, 2))
        compare(halfLine.start, Qt.point(13, 2))
        var perim = 0
        for (i = 1; i < c.length; i++) perim += Math.hypot(c[i].x - c[i - 1].x, c[i].y - c[i - 1].y)
        verify(perim > 50, "perimeter " + perim)
        var mid = boltPath.pointAtPercent(0.5)
        verify(mid.x > 1 || mid.y > 1, "the path is not at 0,0: " + mid)
        var tip = halfPath.pointAtPercent(1)
        verify(Math.hypot(tip.x - 13, tip.y - 2) > 5, "half the outline leaves the top: " + tip)
    }
}
