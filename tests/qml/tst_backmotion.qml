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
// windowmotion.js pose values at p 0, 0.5 and 1; WindowTransitions and Recents (an AppDrawer) sampled at fixed
// times after the release. Staged as the qrc lays it out (st/qml, st/applauncher).
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
    // the spring maths of the commit, without a frame clock
    WearSpring { id: probe }

    Loader { id: rl; width: 384; height: 384; active: false; source: Qt.resolvedUrl("st/qml/Recents.qml") }
    Loader { id: tl; width: 384; height: 384; active: false; source: Qt.resolvedUrl("st/qml/compositor/WindowTransitions.qml") }
    Binding { target: tl.item; property: "recents"; value: rl.item; when: tl.status === Loader.Ready }

    TestCase {
        id: tc
        name: "BackMotion"
        when: windowShown

        property var recents: null
        property var wt: null

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

        // the sample nearest to t ms
        function at(s, t) {
            var best = s[0]
            for (var i = 1; i < s.length; i++)
                if (Math.abs(s[i].t - t) < Math.abs(best.t - t))
                    best = s[i]
            return best
        }
        // the first sample for which pred holds, or null
        function first(s, pred) {
            for (var i = 0; i < s.length; i++)
                if (pred(s[i]))
                    return s[i]
            return null
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

        // drag to px, let the smoothing spring settle, let go past the rule; sample every frame with its time
        // since the release until the motion is over
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
            var t0 = Date.now()
            wt.endBack(true)
            var s = []
            for (var k = 0; k < 200; k++) {
                s.push({ t: Date.now() - t0, mode: wt.layerMode, hs: wt.homeScale, hd: wt.homeDim, as: wt.appScale,
                         ax: wt.appX, landing: wt.landing, left: comp.left })
                if (wt.layerMode === "" && k > 0)
                    break
                wait(10)
            }
            return { drag: drag, s: s }
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

        function test_05_app_flies_off_then_face_steps_in() {
            var r = swipeApp(240)
            var s = r.s
            var gone = first(s, function (x) { return x.mode !== "commit" })
            verify(gone !== null, "the commit ended")
            // off the screen about 130 ms after the release (stock about 120 ms; CP3A's 600 took about 240 ms)
            verify(gone.t <= 170, "the app gone " + gone.t + " ms after the release")
            verify(gone.t >= 80, "not a cut: " + gone.t + " ms")
            compare(gone.left, 1, "the app left (AppLifecycle.leaveApp)")
            // in the commit: the face grows to full size and brightens to the before-commit dim, the app at 0.69
            var mid = at(s, 50)
            compare(mid.mode, "commit", "50 ms after the release the app is on its way")
            verify(mid.hs > 0.97 - 1e-6 && mid.hs < 1, "face between the release and full size: " + mid.hs)
            verify(mid.hd < 0.5 && mid.hd > 0.18, "face brightening: " + mid.hd)
            verify(mid.as <= 0.70, "the app at 0.69: " + mid.as)
            // landing: full size, at the before-commit dim, for 100 ms
            var l = first(s, function (x) { return x.mode === "land" })
            verify(l !== null, "a landing")
            fuzzyCompare(l.hs, 1, 1e-9)
            fuzzyCompare(l.hd, 0.18, 1e-9)
            var hold = at(s, gone.t + 60)
            compare(hold.mode, "land", "60 ms after the app has gone the face is still held")
            fuzzyCompare(hold.hd, 0.18, 1e-9)
            // then one step to rest: no frame between 0.18 and 0
            var end = first(s, function (x) { return x.mode === "" })
            verify(end !== null, "the motion ended")
            compare(end.hs, 1)
            compare(end.hd, 0)
            var held = end.t - gone.t
            console.log("back: the app gone " + gone.t + " ms after the release, the face held " + held + " ms")
            verify(held >= 90 && held <= 160, "held " + held + " ms after the app has gone (100)")
            for (var i = 0; i < s.length; i++)
                verify(s[i].mode !== "land" || Math.abs(s[i].hd - 0.18) < 1e-9, "no fade in the landing")
            // fixed times: 300 ms after the release everything is at rest
            compare(at(s, 300).mode, "")
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
            var t0 = Date.now()
            mouseRelease(recents, 280, 192)
            var s = []
            for (var k = 0; k < 200; k++) {
                s.push({ t: Date.now() - t0, back: recents._back, fs: recents.faceScale, fd: recents.faceDim,
                         moving: recents.faceMoving, open: recents.isOpen })
                if (recents._back === "" && k > 0)
                    break
                wait(10)
            }
            var gone = first(s, function (x) { return x.back !== "commit" })
            verify(gone !== null && gone.back === "land", "the list gone, the face held: " + (gone ? gone.back : "none"))
            verify(gone.t <= 170, "the list gone " + gone.t + " ms after the release")
            compare(gone.open, false)
            fuzzyCompare(gone.fs, 1, 1e-9)
            fuzzyCompare(gone.fd, 0.18, 1e-9)
            compare(gone.moving, true)
            var end = first(s, function (x) { return x.back === "" })
            verify(end !== null, "the landing ended")
            compare(end.fs, 1)
            compare(end.fd, 0)
            compare(end.moving, false)
            var held = end.t - gone.t
            verify(held >= 90 && held <= 160, "held " + held + " ms (100)")
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
    }
}
