// N61-34 (WO-61-L5): back from an app as Wear OS 6 does it (emulator M04 and its 1x run V04):
//  - under the finger the app shrinks 1 -> 0.69 about its right edge's centre and the face behind is drawn at
//    0.93 -> 0.97 (its outer ring at least 176 px from the centre), dimmed 0.5 -> 0.18 (CP3A's dim rule: by the
//    app's left edge);
//  - let go past the rule, the app flies off in about 130 ms (stiffness 2000; CP3A 600, about 240 ms) while the
//    face comes to full size and to the before-commit dim (V04: the hour digits 0.982 -> 0.997 of their size,
//    brightness to 0.82-0.87);
//  - the face is then held there for 100 ms (V04: 70-100 ms after the window has gone) and steps to full
//    brightness in one frame, with no spring (`landing`, WM.land()).
// The same for the app list and Recents swiped back to the face (AppDrawer, the list being an activity in stock).
// windowmotion.js pose values at p 0, 0.5 and 1; WindowTransitions and Recents (an AppDrawer) sampled at every
// frame after the release, each frame timed on the clock the motions run on (the animation timer, `tick`): a
// slow or busy machine gives fewer, later frames, not other results. Staged as the qrc lays it out (st/qml,
// st/applauncher).
// Run by newlook-wt/l5h/run.sh (MODE=st; qmltestrunner under qemu-aarch64 on the image rootfs).
import QtQuick
import QtTest
import org.asteroid.controls
import org.nemomobile.lipstick
import "st/qml/desktop.js" as Desktop
import "st/qml/compositor/windowmotion.js" as WM

Item {
    id: top
    width: 384
    height: 384

    // the launcher's context objects the list reads
    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: alb
        function centerColor(p) { return "#3366aa" }
        function outerColor(p) { return "#000000" }
        function glyphColor(p) { return "#ffffff" }
        function ownIcon(p) { return false }
    }
    QtObject {
        id: desktop
        function launchApp(item, from) {}
        function openAppInfo(item) {}
    }
    ListModel {
        id: launcherModel
        property int itemCount: count
    }
    QtObject {
        id: lipstickComp
        property bool homeActive: true
        property int screenOrientation: 1
        property bool displayAmbient: false
        property bool displayDimmed: false
        // LipstickCompositor.offloadBoost (CR-46): the window transitions that asked for it
        property int boosts: 0
        function offloadBoost() { boosts++ }
        // LipstickCompositor's app start trace (eosappstart.h): what WindowTransitions logged
        property bool appStartTraced: false
        property var traced: []
        function appStartTrace(stage, what) { traced = traced.concat([stage + (what ? " " + what : "")]) }
        signal displayOff()
        signal displayOn()
        signal displayAboutToBeOn()
        signal displayAboutToBeOff()
        signal displayAmbientUpdate()
    }
    // compositor.qml's parts as WindowTransitions reads them through the context
    QtObject {
        id: root
        property real width: 384
        property bool assistantShown: false
        property bool systemModal: false
        property bool headsUpShown: false
    }
    QtObject {
        id: comp
        property bool displayIsOff: false
        property bool appActive: false
        property var topmostWindow: null
        property bool alertShown: false
        property bool topmostWindowRequestsGesturesDisabled: false
        property int left: 0
        signal displayOff()
        function leaveApp(w) { left++; appActive = false; topmostWindow = null }
        function recents() { return [] }
    }
    Item { id: appLayer; property bool ready: true }
    Item { id: winA; property Item window: null }
    // a window wrapper as WindowTransitions.openWindow sets it up, in its layer
    Item {
        id: layerT
        property bool ready: true
        Item { id: winT; property Item window: null; property QtObject motion: null; property bool opening: false }
    }
    // the spring maths of the commit, without a frame clock
    WearSpring { id: probe }
    // The motions' clock. The springs (WearSpring) and the landing's Timer (a QML Timer) go by the animation
    // timer: on a busy machine its frames come later and further apart, and each motion is where its own time
    // says. `tick`, a spring of next to no stiffness let go at 1000 units/s, reads its own run in ms
    // (tc.tickMs()). Started in the turn of a release, just after the commit spring, it starts on the same frame
    // and is moved after it in every frame: at its valueChanged the frame's poses are set (one sample a frame).
    WearSpring {
        id: tick
        stiffness: 0.000001
        dampingRatio: 1
        property var sampler: null
        onValueChanged: if (sampler) sampler()
    }
    // the landing's own time in ms: started in the turn its Timer starts, just before it (tc.recordRelease())
    QtObject { id: heldClock; property real ms: 0 }
    NumberAnimation { id: held; target: heldClock; property: "ms"; from: 0; to: 100000; duration: 100000 }

    Loader { id: rl; width: 384; height: 384; active: false; source: Qt.resolvedUrl("st/qml/Recents.qml") }
    Loader { id: tl; width: 384; height: 384; active: false; source: Qt.resolvedUrl("st/qml/compositor/WindowTransitions.qml") }
    Binding { target: tl.item; property: "recents"; value: rl.item; when: tl.status === Loader.Ready }

    TestCase {
        id: tc
        name: "BackMotion"
        when: windowShown

        property var recents: null
        property var wt: null
        // the motion being recorded (recordRelease)
        property var rec: null

        function initTestCase() {
            Lipstick.compositor = lipstickComp
            Desktop.compositorRoot = comp
            // what WindowTransitions sets on MainScreen's desktop while a window leaves
            if (!Desktop.desktop)
                Desktop.desktop = { aboutToMinimize: false, aboutToClose: false }
            rl.active = true
            tl.active = true
            tryCompare(rl, "status", Loader.Ready, 30000)
            tryCompare(tl, "status", Loader.Ready, 30000)
            recents = rl.item
            wt = tl.item
            recents.show()
            recents.entries = entries(2)
            tryCompare(recents, "_mode", "", 5000)
            wait(200)
            recents.closeNow()
        }

        function init() {
            stopRecord()
            if (recents.isOpen)
                recents.closeNow()
            lipstickComp.homeActive = true
            comp.appActive = false
            comp.topmostWindow = null
        }

        function entries(n) {
            var e = []
            for (var i = 0; i < n; i++)
                e.push({ item: { title: "App " + i, iconId: "ios-help", filePath: "/usr/share/applications/app" + i + ".desktop",
                                 exec: "/usr/bin/app" + i },
                         key: "app" + i, desktop: "app" + i, front: false, ongoing: false, status: "" })
            return e
        }

        // the first sample for which pred holds, or null
        function first(s, pred) {
            for (var i = 0; i < s.length; i++)
                if (pred(s[i]))
                    return s[i]
            return null
        }

        // tick's run in ms: its value is t e^(-w t) (t in ms, w = sqrt(stiffness) = 0.001 a second)
        function tickMs() {
            return Math.round(tick.value * Math.exp(1e-6 * tick.value))
        }

        // The motion a release has just started (call it in the release's turn, after it), until the landing has
        // ended and the clock is 300 ms past the release: s, a sample a frame, { t: ms since the release on the
        // motions' clock, ...pose() }; end, the landing's end, { t, held: the landing's own ms, before: t of the
        // frame before, ...pose() }. changed: the signal on which landing() turns true (the landing's Timer is
        // started after it in that turn) and, the Timer run out, atRest().
        function recordRelease(pose, changed, landing, atRest) {
            var r = { s: [], landed: false, end: null, changed: changed }
            r.turned = function () {
                if (!r.landed && landing()) {
                    r.landed = true
                    held.stop()
                    heldClock.ms = 0
                    held.start()
                } else if (r.landed && r.end === null && atRest()) {
                    var e = pose()
                    e.t = tickMs()
                    e.held = Math.round(heldClock.ms)
                    e.before = 0
                    for (var i = 0; i < r.s.length; i++)
                        if (r.s[i].t < e.t)
                            e.before = r.s[i].t
                    r.end = e
                }
            }
            changed.connect(r.turned)
            rec = r
            tick.snapTo(0)
            tick.sampler = function () {
                var x = pose()
                x.t = tickMs()
                r.s.push(x)
            }
            tick.animateTo(0, 1000)
            tryVerify(function () { return r.end !== null && r.s.length > 0 && r.s[r.s.length - 1].t >= 300 }, 5000,
                      "the landing over, the clock 300 ms past the release")
            stopRecord()
            return r
        }

        function stopRecord() {
            tick.sampler = null
            tick.stop()
            held.stop()
            if (rec)
                rec.changed.disconnect(rec.turned)
            rec = null
        }

        // The commit and the landing of a recording (the app's or the list's; gone: the first frame after the
        // commit): the app off the screen about 130 ms after the release (stock about 120 ms; CP3A's 600 took
        // about 240 ms): the last frame of the commit before 140 ms, the first after it at 115 ms or later (not
        // a cut); then the face held for 100 ms of the landing's own time, its Timer ending it at the first
        // frame at or after that, and at rest from then on
        function checkTimes(r, gone, inCommit, what) {
            var during = r.s.filter(function (x) { return inCommit(x) && x.t > 0 })
            verify(during.length > 0, "frames of the commit")
            var last = during[during.length - 1]
            verify(last.t < 140, what + " still there " + last.t + " ms after the release")
            verify(gone.t >= 115, what + " gone " + gone.t + " ms after the release")
            var e = r.end
            verify(e.held >= 100, "held " + e.held + " ms (100)")
            verify(e.held - (e.t - e.before) < 100,
                   "the landing ended at the first frame after 100 ms: " + (e.held - (e.t - e.before)) + " ms a frame before")
            console.log(what + ": gone " + gone.t + " ms after the release, the face held " + e.held + " ms; "
                        + r.s.length + " frames to " + r.s[r.s.length - 1].t + " ms")
            return during
        }

        // ---- the numbers ----

        function test_01_values() {
            compare(WM.BACK.closingMin, 0.69)
            compare(WM.BACK.openingMin, 0.93)
            compare(WM.BACK.openingBeforeCommit, 0.97)
            compare(WM.BACK.dimBackMax, 0.50)
            compare(WM.BACK.dimBackBeforeCommit, 0.18)
            compare(WM.BACK.dimBackMin, 0)
            compare(WM.BACK.commit.stiffness, 2000)
            compare(WM.BACK.commit.dampingRatio, 1.0)
            compare(WM.BACK.landMs, 100)
            // the window's left edge at 98 % of the way off (stopAtFraction) about 130 ms after the release
            // (stock about 120 ms; CP3A's 600 about 240 ms)
            var ms = probe.settleMs(WM.BACK.commit.stiffness, WM.BACK.commit.dampingRatio, 1 - WM.BACK.commit.stopAtFraction)
            verify(ms >= 115 && ms <= 140, "the commit settles in " + ms + " ms")
            verify(probe.settleMs(600, 1.0, 0.02) > 220, "CP3A's took longer")
            // the CP3A curve, cancel and smoothing stay
            compare(JSON.stringify(WM.BACK.bezier), "[0,0.2,0.8,1]")
            compare(WM.BACK.cancel.stiffness, 1500)
            compare(WM.BACK.smooth.stiffness, 1500)
        }

        // the pose at p 0, 0.5 and 1 (e = CubicBezier(0, 0.2, 0.8, 1)(p))
        function test_02_pose_at_p() {
            var W = 384
            var a = WM.back(0, W)
            fuzzyCompare(a.appScale, 1, 1e-9)
            fuzzyCompare(a.appLeft, 0, 1e-9)
            fuzzyCompare(a.homeScale, 0.93, 1e-9)
            fuzzyCompare(a.homeDim, 0.5, 1e-9)
            var m = WM.back(0.5, W)
            var e = WM.bezier(0, 0.2, 0.8, 1, 0.5)
            fuzzyCompare(m.e, e, 1e-9)
            verify(e > 0.6 && e < 0.7, "e(0.5) " + e)
            fuzzyCompare(m.appScale, 1 - 0.31 * e, 1e-9)
            fuzzyCompare(m.appLeft, W * 0.31 * e, 1e-6)
            fuzzyCompare(m.homeScale, 0.93 + 0.04 * e, 1e-9)
            // the dim by the app's left edge (CrossTaskBackAnimation.onGestureProgress)
            fuzzyCompare(m.homeDim, 0.5 + (0.18 - 0.5) * 0.31 * e, 1e-9)
            var b = WM.back(1, W)
            fuzzyCompare(b.appScale, 0.69, 1e-9)
            fuzzyCompare(b.appLeft, W * 0.31, 1e-6)
            fuzzyCompare(b.homeScale, 0.97, 1e-9)
            fuzzyCompare(b.homeDim, 0.5 + (0.18 - 0.5) * 0.31, 1e-6)
            // the face's outer ring (190 px at rest) at least 176 px from the centre at any p
            for (var p = 0; p <= 1.0001; p += 0.05)
                verify(WM.back(p, W).homeScale * 190 >= 176, "ring at p " + p)
        }

        // the commit goes on from the release pose and ends with the face full size at the before-commit dim
        function test_03_commit_and_land_pose() {
            var W = 384
            var s = WM.back(0.6, W)
            var c0 = WM.commit(s.appLeft, s.appLeft, s.homeDim, s.appDim, W, s.homeScale)
            fuzzyCompare(c0.appScale, s.appScale, 1e-6)
            fuzzyCompare(c0.homeScale, s.homeScale, 1e-9)
            fuzzyCompare(c0.homeDim, s.homeDim, 1e-9)
            fuzzyCompare(c0.appDim, s.appDim, 1e-9)
            var half = WM.commit((s.appLeft + W) / 2, s.appLeft, s.homeDim, s.appDim, W, s.homeScale)
            fuzzyCompare(half.homeScale, (s.homeScale + 1) / 2, 1e-9)
            fuzzyCompare(half.homeDim, (s.homeDim + 0.18) / 2, 1e-9)
            fuzzyCompare(half.appScale, 0.69, 1e-9)
            var c1 = WM.commit(W, s.appLeft, s.homeDim, s.appDim, W, s.homeScale)
            fuzzyCompare(c1.homeScale, 1, 1e-9)
            fuzzyCompare(c1.homeDim, 0.18, 1e-9)
            fuzzyCompare(c1.appScale, 0.69, 1e-9)
            var l = WM.land(W)
            compare(l.homeScale, 1)
            compare(l.homeDim, 0.18)
        }

        // ---- an application swiped back (WindowTransitions) ----

        // drag to px, let the smoothing spring settle, let go past the rule; a sample every frame with its time
        // since the release on the motions' clock (recordRelease) until the motion is over
        function swipeApp(px) {
            comp.appActive = true
            comp.topmostWindow = winA
            comp.left = 0
            var drag = []
            wt.beginBack()
            for (var i = 1; i <= 10; i++) {
                wt.feedBack(px * i / 10, false)
                wait(16)
                drag.push({ hs: wt.homeScale, hd: wt.homeDim, as: wt.appScale, mode: wt.layerMode })
            }
            wait(250)
            drag.push({ hs: wt.homeScale, hd: wt.homeDim, as: wt.appScale, mode: wt.layerMode })
            var release = { hs: wt.homeScale, hd: wt.homeDim, as: wt.appScale }
            wt.endBack(true)
            var r = recordRelease(function () {
                return { mode: wt.layerMode, hs: wt.homeScale, hd: wt.homeDim, as: wt.appScale, left: comp.left }
            }, wt.landingChanged, function () { return wt.landing }, function () { return !wt.landing })
            return { drag: drag, release: release, r: r }
        }

        function test_04_app_drag_face_nearly_full_size() {
            var r = swipeApp(240)
            for (var i = 0; i < r.drag.length; i++) {
                var d = r.drag[i]
                compare(d.mode, "swipe")
                verify(d.hs >= 0.93 - 1e-9 && d.hs <= 0.97 + 1e-9, "face 0.93..0.97 under the finger: " + d.hs)
                verify(d.hd <= 0.5 + 1e-9 && d.hd >= 0.18, "dimmed: " + d.hd)
            }
            var last = r.drag[r.drag.length - 1]
            verify(last.as < 0.8, "the app shrunk under the finger: " + last.as)
            wt.settleAll()
        }

        // The times are the motions' clock's (ms since the release; see tick): every frame of it is checked,
        // so a loaded machine (fewer, later frames) checks the same
        function test_05_app_flies_off_then_face_steps_in() {
            var sw = swipeApp(240)
            var r = sw.r
            var s = r.s
            var gone = first(s, function (x) { return x.mode !== "commit" })
            verify(gone !== null, "the commit ended")
            var during = checkTimes(r, gone, function (x) { return x.mode === "commit" }, "the app")
            compare(gone.left, 1, "the app left (AppLifecycle.leaveApp)")
            // in the commit: the face grows to full size and brightens to the before-commit dim, the app shrinks
            // to 0.69; from 40 ms on (50 ms after the release the app is on its way) the face is past 0.97 and the
            // app at 0.69
            verify(first(during, function (x) { return x.t >= 40 }) !== null, "frames of the commit from 40 ms on")
            for (var j = 0; j < during.length; j++) {
                var c = during[j]
                verify(c.hs >= sw.release.hs - 1e-9 && c.hs < 1, "face between the release and full size: " + c.hs + " at " + c.t + " ms")
                verify(c.hd < 0.5 && c.hd > 0.18, "face brightening: " + c.hd + " at " + c.t + " ms")
                verify(c.as >= 0.69 - 1e-9 && c.as <= sw.release.as + 1e-9, "the app between its release size and 0.69: " + c.as + " at " + c.t + " ms")
                if (c.t < 40)
                    continue
                verify(c.hs > 0.97 - 1e-6, "face nearly full size at " + c.t + " ms: " + c.hs)
                verify(c.as <= 0.70, "the app at 0.69 at " + c.t + " ms: " + c.as)
            }
            // landing: full size, at the before-commit dim, from the frame the app went to the landing's end (so
            // 60 ms after the app has gone the face is still held): no fade
            var end = r.end
            for (var i = 0; i < s.length; i++) {
                var x = s[i]
                if (x.t < gone.t || x.t > end.t)
                    continue
                compare(x.mode, "land", "the face held at " + x.t + " ms")
                fuzzyCompare(x.hs, 1, 1e-9)
                fuzzyCompare(x.hd, 0.18, 1e-9)
            }
            // then one step to rest: no frame between 0.18 and 0, at rest from then on (to 300 ms after the release)
            compare(end.mode, "")
            compare(end.hs, 1)
            compare(end.hd, 0)
            for (var k = 0; k < s.length; k++) {
                if (s[k].t <= end.t)
                    continue
                compare(s[k].mode, "", "at rest at " + s[k].t + " ms")
                compare(s[k].hs, 1)
                compare(s[k].hd, 0)
            }
        }

        // a swipe of px let go past the rule; returns once the app has gone (the landing on)
        function flingApp(px) {
            comp.appActive = true
            comp.topmostWindow = winA
            wt.beginBack()
            wt.feedBack(px, false)
            wait(250)
            wt.endBack(true)
            tryVerify(function () { return wt.landing }, 1000, "the landing after the commit")
        }

        function test_06_a_new_swipe_or_the_display_off_ends_the_landing() {
            flingApp(240)
            // the next app swiped back at once
            comp.appActive = true
            comp.topmostWindow = winA
            wt.beginBack()
            compare(wt.landing, false, "a new swipe ends the landing")
            compare(wt.layerMode, "swipe")
            wt.endBack(false)
            tryCompare(wt, "layerMode", "", 2000)
            compare(wt.homeDim, 0)
            // the display going off lands everything
            flingApp(240)
            wt.settleAll()
            compare(wt.landing, false)
            compare(wt.layerMode, "")
            compare(wt.homeDim, 0)
            compare(wt.homeScale, 1)
        }

        // ---- the app list (Recents, an AppDrawer) swiped back to the face ----

        function test_07_list_swiped_back_lands_the_same_way() {
            recents.show()
            recents.entries = entries(2)
            tryCompare(recents, "_mode", "", 3000)
            compare(recents.movesFace, true)
            wait(100)
            mousePress(recents, 40, 192)
            var drag = []
            for (var i = 1; i <= 12; i++) {
                mouseMove(recents, 40 + 20 * i, 192)
                wait(16)
                if (recents._back === "swipe")
                    drag.push({ fs: recents.faceScale, fd: recents.faceDim })
            }
            wait(200)
            verify(drag.length > 3, "frames of the swipe: " + drag.length)
            for (var j = 0; j < drag.length; j++)
                verify(drag[j].fs >= 0.93 - 1e-9 && drag[j].fs <= 0.97 + 1e-9, "face 0.93..0.97: " + drag[j].fs)
            mouseRelease(recents, 280, 192)
            compare(recents._back, "commit", "let go past the rule")
            // the times on the motions' clock, as test_05's
            var r = recordRelease(function () {
                return { back: recents._back, fs: recents.faceScale, fd: recents.faceDim, moving: recents.faceMoving,
                         open: recents.isOpen }
            }, recents._backChanged, function () { return recents._back === "land" }, function () { return recents._back === "" })
            var s = r.s
            var gone = first(s, function (x) { return x.back !== "commit" })
            verify(gone !== null && gone.back === "land", "the list gone, the face held: " + (gone ? gone.back : "none"))
            checkTimes(r, gone, function (x) { return x.back === "commit" }, "the list")
            compare(gone.open, false)
            fuzzyCompare(gone.fs, 1, 1e-9)
            fuzzyCompare(gone.fd, 0.18, 1e-9)
            compare(gone.moving, true)
            var end = r.end
            for (var i = 0; i < s.length; i++) {
                var x = s[i]
                if (x.t < gone.t || x.t > end.t)
                    continue
                compare(x.back, "land", "the face held at " + x.t + " ms")
                fuzzyCompare(x.fd, 0.18, 1e-9)
            }
            compare(end.fs, 1)
            compare(end.fd, 0)
            compare(end.moving, false)
            for (var k = 0; k < s.length; k++)
                if (s[k].t > end.t)
                    compare(s[k].back, "", "at rest at " + s[k].t + " ms")
        }

        function test_08_reopening_ends_the_landing() {
            recents.show()
            recents.entries = entries(2)
            tryCompare(recents, "_mode", "", 3000)
            wait(100)
            mousePress(recents, 40, 192)
            for (var i = 1; i <= 12; i++) {
                mouseMove(recents, 40 + 20 * i, 192)
                wait(16)
            }
            wait(200)
            mouseRelease(recents, 280, 192)
            tryCompare(recents, "_back", "land", 1000)
            recents.show()
            verify(recents._back !== "land", "opened again: no landing")
            tryCompare(recents, "_mode", "", 3000)
            compare(recents.faceDim, 0)
            recents.closeNow()
        }

        // CR-46: each window transition asks the compositor for the display offload daemon's frame pacing
        // boost once, at its start (the compositor sends "boost 500" with the display on only)
        function test_09_window_transitions_ask_the_boost() {
            lipstickComp.boosts = 0
            // a back swipe: the finger's drag has the touch boost, the commit asks
            comp.appActive = true
            comp.topmostWindow = winA
            wt.beginBack()
            wt.feedBack(240, false)
            wait(100)
            compare(lipstickComp.boosts, 0, "nothing while the finger drags")
            wt.endBack(true)
            compare(lipstickComp.boosts, 1, "the commit")
            tryVerify(function () { return wt.landing }, 1000, "the landing after the commit")
            wt.settleAll()
            // a swipe let go before the rule springs back: no window transition
            comp.appActive = true
            comp.topmostWindow = winA
            wt.beginBack()
            wt.feedBack(30, false)
            wait(100)
            wt.endBack(false)
            tryCompare(wt, "layerMode", "", 2000)
            compare(lipstickComp.boosts, 1, "a cancelled swipe")
            // the crown's close (WatchfaceReveal)
            comp.appActive = true
            comp.topmostWindow = winA
            wt.closeTopmost()
            tryCompare(lipstickComp, "boosts", 2, 500, "the crown's close")
            tryCompare(wt, "closing", false, 3000)
            // a launch (AppOpen, the springs of the splash or the window)
            wt.launch.start()
            tryCompare(lipstickComp, "boosts", 3, 500, "the launch")
            tryCompare(wt.launch, "inProgress", false, 3000)
            compare(lipstickComp.boosts, 3, "once per transition")
        }

        // The app start trace (EOS_APPSTART_TRACE): WindowTransitions logs the launch springs and the
        // window it opens through LipstickCompositor.appStartTrace, only while appStartTraced is true
        function test_10_app_start_trace() {
            lipstickComp.traced = []
            lipstickComp.appStartTraced = false
            wt.launch.start()
            tryCompare(wt.launch, "inProgress", false, 3000)
            wt.openWindow(winT, true)
            compare(lipstickComp.traced.length, 0, "nothing with the trace off")

            lipstickComp.appStartTraced = true
            // the splash starts the springs, the window comes while they run
            wt.launch.start()
            tryVerify(function () { return wt.launch.inProgress }, 500)
            wt.openWindow(winT, true)
            verify(winT.opening)
            tryCompare(wt.launch, "inProgress", false, 3000)
            compare(lipstickComp.traced, ["launch motion start centre", "open window zooming over the splash",
                                          "launch motion end with the window"])
            // a window that comes after the springs: at rest
            lipstickComp.traced = []
            wt.openWindow(winT, true)
            compare(lipstickComp.traced, ["open window at rest"])
            // a window without a splash starts the springs itself
            lipstickComp.traced = []
            wt.openWindow(winT, false)
            tryCompare(wt.launch, "inProgress", false, 3000)
            compare(lipstickComp.traced, ["launch motion start centre", "open window zooming", "launch motion end with the window"])
            lipstickComp.appStartTraced = false
            lipstickComp.traced = []
        }
    }
}
