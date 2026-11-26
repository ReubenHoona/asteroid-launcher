/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * PanelsGrid's trays: the tray's black background stays on the screen while the tray slides
 * over it, so the face dims evenly at TrayRules.backgroundAlpha of how far out the tray is
 * (D60-19; CP3A ihv.java:13-19 from jud.java:189-197 and jul.java:137-142). A committed close
 * is a cut (N61-24, the Wear OS 6 emulator's M06 and M07 close): the tray is gone in one frame
 * and the background fades from the emulator's dim of the cut (the face at 0.35 after the stream,
 * 0.18 after quick settings; no darker than at the release: TrayRules.cutDim) to nothing in
 * 100 ms (the stream) or 115 ms (quick settings) on standardAccel (0.3, 0, 1, 1), sampled at
 * fixed times; a release
 * that reopens keeps the open spring, a close asked for by a gesture its spring. The grid runs on
 * the repo mocks (org.asteroid.launcher's GestureFilterArea stand-in), staged as LauncherQml
 * with tray.js and pager.js. A white face, so the dimming reads as brightness; trays that draw
 * nothing themselves. Screenshots (384x384) go to /tmp/qs-shots.
 */

import QtQuick
import QtTest
import LauncherQml
import "LauncherQml/tray.js" as TrayRules

Item {
    id: root
    width: 384
    height: 384

    // what MainScreen gives the grid
    property bool displayAmbient: false

    Rectangle { anchors.fill: parent; color: "black" }
    Item {
        id: screen
        anchors.fill: parent
        clip: true
        PanelsGrid {
            id: grid
            width: root.width
            height: root.height
            trayMode: true
        }
    }
    Component { id: faceComponent; Rectangle { color: "white" } }
    Component { id: trayComponent; Item { } }

    TestCase {
        name: "PanelsGridTrays"
        when: windowShown

        property Item qs: null
        property Item ns: null

        function findBy(item, pred) {
            if (!item)
                return null
            if (pred(item))
                return item
            var kids = item.children || []
            for (var i = 0; i < kids.length; i++) {
                var r = findBy(kids[i], pred)
                if (r)
                    return r
            }
            return null
        }
        // the background attachTray() made for a row (by its properties: the old ones had no name)
        function background(row) {
            return findBy(grid, function (o) { return o.tray !== undefined && o.row === row && o.radius !== undefined })
        }
        function near(a, b, tol, msg) { verify(Math.abs(a - b) <= tol, (msg || "") + " " + a + " != " + b) }
        // the tray out by f (the finger's way, as applyTrayDrag sets it); checks follow before the
        // grid's 500 ms hide timer
        function pull(row, f) {
            grid.contentY = TrayRules.sign(row) * f * grid.height
            wait(50)
        }
        function brightness(img, x, y) {
            var p = img.pixel(x, y)
            return (p.r + p.g + p.b) / 3
        }

        function initTestCase() {
            grid.addPanel(0, 0, faceComponent, grid.faceHost)
            qs = grid.addPanel(0, -1, trayComponent)
            grid.attachTray(qs, -1)
            ns = grid.addPanel(0, 1, trayComponent)
            grid.attachTray(ns, 1)
        }

        function test_01_background_stays_on_the_screen() {
            var b = background(-1)
            verify(b !== null, "quick settings' background")
            pull(-1, 0.4)
            compare(grid.topTrayFraction, 0.4)
            verify(qs.visible)
            // the tray is 40 % down: its own box is at -230.4 .. 153.6; the background fills the screen
            near(qs.mapToItem(root, 0, 0).y, -230.4, 0.01, "tray top")
            var p = b.mapToItem(root, 0, 0)
            compare(p.x, 0); compare(p.y, 0)
            compare(b.width, 384); compare(b.height, 384); compare(b.radius, 192)
            verify(b.visible)
            near(b.opacity, 0.6, 1e-6, "alpha at 40 %")
            // the face under it dims evenly: top, middle and bottom within 10 % (stock R07slow)
            var img = grabImage(screen)
            var t = brightness(img, 192, 95), m = brightness(img, 192, 193), lo = brightness(img, 192, 325)
            near(t, 0.4, 0.03, "top"); near(m, 0.4, 0.03, "middle"); near(lo, 0.4, 0.03, "bottom")
            verify(Math.max(t, m, lo) - Math.min(t, m, lo) <= 0.1 * Math.max(t, m, lo), "even: " + [t, m, lo])
            img.save("/tmp/qs-shots/grid-01-qs-40.png")
            // half out and more: opaque, still on the screen
            pull(-1, 0.7)
            compare(b.mapToItem(root, 0, 0).y, 0)
            compare(b.opacity, 1)
            // under 25 % it is not drawn at all
            pull(-1, 0.2)
            compare(b.opacity, 0)
            verify(!b.visible)
            // a sideways move of the content (the tiles pager) does not move it either
            pull(-1, 0.4)
            grid.contentX = 40
            wait(20)
            compare(b.mapToItem(root, 0, 0).x, 0)
            grid.contentX = 0
            pull(-1, 0)
        }

        function test_02_stream_background_too() {
            var b = background(1)
            verify(b !== null, "the stream's background")
            pull(1, 0.4)
            compare(grid.bottomTrayFraction, 0.4)
            var p = b.mapToItem(root, 0, 0)
            compare(p.x, 0); compare(p.y, 0)
            near(b.opacity, 0.6, 1e-6)
            // quick settings' background is not drawn meanwhile
            verify(!background(-1).visible)
            var img = grabImage(screen)
            var t = brightness(img, 192, 60), lo = brightness(img, 192, 325)
            near(t, lo, 0.04, "even")
            pull(1, 0)
        }

        // ---- the close cut (N61-24) ----------------------------------------------------------

        // standardAccel (0.3, 0, 1, 1) at time fraction x (the curve's y where its x is x)
        function accel(x) {
            if (x <= 0)
                return 0
            if (x >= 1)
                return 1
            var lo = 0, hi = 1, u = 0.5
            for (var i = 0; i < 40; i++) {
                u = (lo + hi) / 2
                var bx = 3 * (1 - u) * (1 - u) * u * 0.3 + 3 * (1 - u) * u * u + u * u * u
                if (bx < x)
                    lo = u
                else
                    hi = u
            }
            return 3 * (1 - u) * u * u + u * u * u
        }
        // the background's alpha d ms into the fade from a0 over ms (as the NumberAnimation runs it)
        function fadeAt(a0, d, ms) { return a0 * (1 - accel(d / ms)) }
        function settleOpen(row) {
            grid.moveTo(0, 0)
            wait(20)
            verify(grid.openTray(row, TrayRules.REASON.nonDrag, 0))
            tryVerify(function () { return !grid.trayAnimation.running }, 2000, "the open spring settles")
            compare(grid.currentVerticalPos, row)
            compare(grid.contentY, TrayRules.sign(row) * grid.height)
            verify((row < 0 ? qs : ns).visible)
        }
        // a finger on the open tray: down at y, dy px (+ = down), let go at vy px/s
        function drag(y, dy, vy) {
            grid.pressPosition = Qt.point(192, y)
            grid.touchPosition = Qt.point(192, y)
            grid.swipeStarted(false)
            grid.touchPosition = Qt.point(192, y + dy)
            grid.swipeMoved(false, dy)
            grid.swipeVelocityY = vy
        }
        // the cut, then samples of the fade at fixed times
        function checkCut(row, a0, ms, name) {
            var t0 = Date.now()
            var tray = row < 0 ? qs : ns
            var b = background(row)
            // the same turn as the release: closed, hidden, no spring; the face still at the dim
            compare(grid.currentVerticalPos, 0)
            compare(grid.contentY, 0, "closed in one frame")
            verify(!grid.trayAnimation.running, "no retract spring")
            verify(!tray.visible, "the tray's content is hidden at once")
            near(b.opacity, a0, 1e-6, "the dim at the release")
            verify(b.visible)
            var f = grid.trayCloseFade
            verify(f.running, "the fade runs")
            compare(f.duration, ms)
            compare(f.easing.type, Easing.BezierSpline)
            compare(f.easing.bezierCurve.length, 6)
            var want = [0.3, 0, 1, 1, 1, 1]
            for (var i = 0; i < 6; i++)
                near(f.easing.bezierCurve[i], want[i], 1e-9, "standardAccel " + i)
            // fixed sample times after the release (t0), on the wall clock: 30, 60, 90 ms and the end.
            // The animation clock starts at its first tick after the release (here 15-35 ms later;
            // on the watch the next frame), so a sample may lag the curve by up to 45 ms but never
            // lead it. standardAccel keeps the face dark early: at 60 ms it is still dimmed.
            var samples = [30, 60, 90]
            for (var s = 0; s < samples.length; s++) {
                var left = samples[s] - (Date.now() - t0)
                if (left > 0)
                    wait(left)
                var d = Date.now() - t0
                var o = b.opacity
                verify(o <= a0 + 1e-6 && o >= fadeAt(a0, d + 10, ms) - 0.02, name + " at " + d + " ms: " + o
                       + " ahead of the curve (" + fadeAt(a0, d, ms) + ")")
                verify(o <= fadeAt(a0, d - 45, ms) + 0.02, name + " at " + d + " ms: " + o + " behind the curve ("
                       + fadeAt(a0, d - 45, ms) + ")")
                if (samples[s] === 60 && d < ms - 15)
                    verify(o > 0 && o < a0, name + " at " + d + " ms: between the dim and full: " + o)
                verify(!tray.visible && grid.contentY === 0, "the tray stays away")
            }
            // done in the fade's time (plus the start of the clock): the background gone
            tryVerify(function () { return !f.running }, 400, "the fade ends")
            var took = Date.now() - t0
            verify(took < ms + 60, name + ": the fade took " + took + " ms")
            compare(b.opacity, 0)
            verify(!b.visible)
            compare(grid.trayCloseDim, 0)
        }
        // frames of a cut (a second release, as the grabs hold the event loop): at the release, about
        // 50 ms on, after the fade; the white face reads as the brightness
        function cutFrames(row, a0, name) {
            var tray = row < 0 ? qs : ns
            var t0 = Date.now()
            var img = grabImage(screen)
            img.save("/tmp/qs-shots/grid-" + name + "-cut-0.png")
            // the first frame: the face at the dim everywhere, nothing of the tray on it
            var top = brightness(img, 192, 60), mid = brightness(img, 192, 192), lo = brightness(img, 192, 325)
            verify(Math.abs(top - mid) < 0.02 && Math.abs(lo - mid) < 0.02, "even: " + [top, mid, lo])
            verify(mid <= 1 - a0 + 0.03, name + " frame 0: " + mid)
            // about 50 ms on: a grab holds the event loop and the fade's clock starts at its first tick
            // after it, so the frame is taken once the fade has moved; the face between the dim and full
            var left = 50 - (Date.now() - t0)
            if (left > 0)
                wait(left)
            for (var k = 0; k < 40 && grid.trayCloseDim > a0 - 0.05; k++)
                wait(5)
            var dm = grid.trayCloseDim
            verify(dm < a0 - 0.05 && dm > 0, name + ": the fade moves: " + dm)
            img = grabImage(screen)
            img.save("/tmp/qs-shots/grid-" + name + "-cut-50.png")
            var bm = brightness(img, 192, 192)
            verify(bm > 1 - a0 + 0.02 && bm < 0.99, name + " mid-fade frame: " + bm + " at the dim " + dm)
            wait(250)
            img = grabImage(screen)
            img.save("/tmp/qs-shots/grid-" + name + "-cut-end.png")
            near(brightness(img, 192, 192), 1, 0.01, "the face at full")
            verify(!tray.visible)
        }

        function test_03_close_rules() {
            // N61-24: every close but a gesture's is a cut; the fade after the stream 100 ms, after
            // quick settings 115 ms, on standardAccel (the emulator's M06 98 ms, M07 108 ms at 10x)
            verify(TrayRules.closeCuts(TrayRules.REASON.drag))
            verify(TrayRules.closeCuts(TrayRules.REASON.nonDrag))
            verify(TrayRules.closeCuts(TrayRules.REASON.none))
            verify(!TrayRules.closeCuts(TrayRules.REASON.gesture))
            compare(TrayRules.closeFadeMs(1), 100)
            compare(TrayRules.closeFadeMs(-1), 115)
            compare(TrayRules.CLOSE_FADE_EASING, [0.3, 0, 1, 1])
            // the open spring is unchanged (0.75 / 500, the emulator's M06 0.80 / 488, M07 0.77 / 527)
            var sp = TrayRules.spring(true, TrayRules.REASON.drag)
            compare(sp.dampingRatio, 0.75); compare(sp.stiffness, 500)
            // the curve the samples are checked against
            near(accel(0.5), 0.372, 0.001)
            near(accel(0.25), 0.1285, 0.001)
            verify(fadeAt(1, 50, 100) > 0.6, "still dark half way")
            // the dim of the cut (the emulator's M06/M07 close at 10x): the face at 0.35 after the
            // stream, 0.18 after quick settings, never darker than it showed at the release
            compare(TrayRules.CLOSE_CUT_BRIGHTNESS_STREAM, 0.35)
            compare(TrayRules.CLOSE_CUT_BRIGHTNESS_QS, 0.18)
            near(TrayRules.cutDim(1, 1), 0.65, 1e-9)
            near(TrayRules.cutDim(-1, 1), 0.82, 1e-9)
            near(TrayRules.cutDim(1, 234 / 255), 0.65, 1e-9)
            near(TrayRules.cutDim(-1, 0.6), 0.6, 1e-9)
            near(TrayRules.cutDim(1, 0.3), 0.3, 1e-9)
            compare(TrayRules.cutDim(-1, 0), 0)
        }

        function test_04_quick_settings_close_is_a_cut() {
            settleOpen(-1)
            // the finger up 230.4 px from the bottom, slowly: 40 % out at the release, alpha 0.6
            drag(330, -230.4, -300)
            near(grid.topTrayFraction, 0.4, 1e-6, "the tray follows the finger")
            near(background(-1).opacity, 0.6, 1e-6)
            grid.swipeReleased(false, -300, false)
            checkCut(-1, 0.6, 115, "qs")
            settleOpen(-1)
            drag(330, -230.4, -300)
            grid.swipeReleased(false, -300, false)
            cutFrames(-1, 0.6, "qs")
        }

        function test_05_stream_close_is_a_cut() {
            settleOpen(1)
            // the finger down 200 px from the top: 48 % out, alpha 234/255 (the face at 0.08), the cut
            // shows it at 0.35 (alpha 0.65)
            drag(40, 200, 300)
            near(grid.bottomTrayFraction, 184 / 384, 1e-6)
            near(TrayRules.backgroundAlpha(184 / 384), 234 / 255, 1e-6)
            var a0 = 0.65
            grid.swipeReleased(false, 300, false)
            checkCut(1, a0, 100, "stream")
            settleOpen(1)
            drag(40, 200, 300)
            grid.swipeReleased(false, 300, false)
            cutFrames(1, a0, "stream")
        }

        function test_06_fast_close_from_open() {
            // a flick closes from far out (the face black under the tray, alpha 1): at the cut the face
            // shows at 0.18 (alpha 0.82) and comes up in 115 ms
            settleOpen(-1)
            drag(330, -60, -1500)
            grid.swipeReleased(false, -1500, false)
            checkCut(-1, 0.82, 115, "qs-flick")
        }

        function test_07_release_that_reopens_springs() {
            settleOpen(-1)
            // 84 % out: stays open, on the open spring, no fade
            drag(330, -60, -200)
            grid.swipeReleased(false, -200, false)
            compare(grid.currentVerticalPos, -1)
            verify(grid.trayAnimation.running, "the open spring")
            compare(grid.trayAnimation.dampingRatio, 0.75)
            compare(grid.trayAnimation.stiffness, 500)
            verify(!grid.trayCloseFade.running)
            compare(grid.trayCloseDim, 0)
            tryVerify(function () { return !grid.trayAnimation.running }, 2000)
            compare(grid.contentY, 384)
            // a stream opened by a finger that lets go early goes back as a cut too
            grid.moveTo(0, 0)
            wait(20)
            grid.pressPosition = Qt.point(192, 370)
            grid.touchPosition = Qt.point(192, 370)
            grid.swipeStarted(false)
            grid.swipeMoved(false, -60)
            grid.swipeVelocityY = -100
            grid.swipeReleased(false, -100, false)
            compare(grid.contentY, 0)
            verify(!grid.trayAnimation.running)
            wait(200)
        }

        function test_08_crown_and_closeTray_cut_gesture_springs() {
            // the crown: a cut as the finger's (a close without a finger is committed at once)
            var now = 1e7
            grid.clock = function () { return now }
            grid.moveTo(0, 0)
            verify(grid.crownScrolled(-1), "the crown opens quick settings")
            tryVerify(function () { return !grid.trayAnimation.running }, 2000)
            now += 1000
            verify(grid.crownScrolled(1), "and closes it")
            checkCut(-1, 0.82, 115, "qs-crown")
            // closeTray (Theater mode's close 700 ms later) and the crown button's animateTo
            settleOpen(1)
            verify(grid.closeTray(TrayRules.REASON.nonDrag))
            compare(grid.contentY, 0); verify(!grid.trayAnimation.running)
            compare(grid.trayCloseFade.duration, 100)
            tryVerify(function () { return !grid.trayCloseFade.running }, 400)
            settleOpen(-1)
            grid.animateTo(0, 0)
            compare(grid.contentY, 0); verify(!grid.trayAnimation.running)
            verify(grid.trayCloseFade.running)
            tryVerify(function () { return !grid.trayCloseFade.running }, 400)
            // a close another gesture asked for keeps CP3A's spring (1.0 / 200, to 98 %)
            settleOpen(1)
            verify(grid.closeTray(TrayRules.REASON.gesture))
            verify(grid.trayAnimation.running)
            compare(grid.trayAnimation.dampingRatio, 1.0)
            compare(grid.trayAnimation.stiffness, 200)
            near(grid.trayAnimation.stopAtFraction, 0.98, 1e-9)
            verify(!grid.trayCloseFade.running)
            tryVerify(function () { return !grid.trayAnimation.running }, 2000)
            compare(grid.contentY, 0)
            grid.clock = function () { return Date.now() }
        }
    }
}
