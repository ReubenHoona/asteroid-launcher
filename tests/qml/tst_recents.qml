// WO-10: Recents (misc/Recents.qml over misc/AppDrawer.qml, the list applauncher/wear/WearRecents.qml)
// and what is behind it (compositor/WindowTransitions.qml), staged as the qrc lays them out (st/qml,
// st/applauncher):
//  - D60-24: Recents over an application: the application is the app launch transition's closing
//    task, 1 -> 0.70 (scale 1 - 0.3 p) under a black dim 0.5 p on the opening's baseline spring, and
//    back to 1 when Recents closes (on the face's spring q); the face is not moved
//    (WearAppLaunchMixinTransition$$ExternalSyntheticLambda0.java:29-35, WearAppLaunchMixinTransition
//    .java:63 BaselineAnimator 1.0/260).
//  - D60-25: Recents over the face moves the face as the app list does (the values MainScreen's faceStack
//    multiplies in): open 1 -> 0.70 and a dim 0.5 p on the same spring; close (WearOpenWatchface) scale and
//    alpha 0.5 + 0.5 q on 1.0/260 (WearOpenWatchfaceMixinTransition.java:105, $$ExternalSyntheticLambda2
//    .java:28-32).
//  - D60-09: once the list has come in, its scroll indicator shows for 2 s (RotaryInput.flashIndicator,
//    qml-asteroid 7913885), only when the list scrolls; not during the opening (stock M01: it fades in
//    at the end of the zoom).
// Run by motion-wt/wo10/run.sh (qmltestrunner under qemu-aarch64 on the image rootfs).
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
        property int launches: 0
        function launchApp(item, from) { launches++ }
        function openAppInfo(item) {}
    }
    ListModel {
        id: launcherModel
        property int itemCount: count
    }

    // lipstick's compositor object (Lipstick.compositor): is the home screen in front?
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
        signal displayOff()
        function leaveApp(w) {}
        function recents() { return [] }
    }
    Item { id: appLayer; property bool ready: true }

    Loader { id: rl; width: 384; height: 384; active: false; source: Qt.resolvedUrl("st/qml/Recents.qml") }
    Loader { id: tl; width: 384; height: 384; active: false; source: Qt.resolvedUrl("st/qml/compositor/WindowTransitions.qml") }
    Binding { target: tl.item; property: "recents"; value: rl.item; when: tl.status === Loader.Ready }

    TestCase {
        id: tc
        name: "Recents"
        when: windowShown

        property var recents: null
        property var wt: null

        function initTestCase() {
            Lipstick.compositor = lipstickComp
            Desktop.compositorRoot = comp
            rl.active = true
            tl.active = true
            tryCompare(rl, "status", Loader.Ready, 30000)
            tryCompare(tl, "status", Loader.Ready, 30000)
            recents = rl.item
            wt = tl.item
            compare(wt.recents, recents)
            // the list loaded and drawn once, so the frames of an opening are not one long first frame
            recents.show()
            recents.entries = entries(2)
            tryCompare(recents, "_mode", "", 5000)
            tryCompare(recents.launcher, "status", Loader.Ready, 5000)
            wait(200)
            recents.closeNow()
        }

        function init() {
            if (recents.isOpen)
                recents.closeNow()
            lipstickComp.homeActive = true
            comp.appActive = false
        }

        function entries(n) {
            var e = []
            for (var i = 0; i < n; i++)
                e.push({ item: { title: "App " + i, iconId: "ios-help", filePath: "/usr/share/applications/app" + i + ".desktop",
                                 exec: "/usr/bin/app" + i },
                         key: "app" + i, desktop: "app" + i, front: false, ongoing: false, status: "" })
            return e
        }

        // the shared scroll indicator RotaryInput puts on the window (PositionIndicator)
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
        function indicatorOn(view) {
            var ind = indicator()
            return ind !== null && ind.shown && ind.flickable === view
        }

        // open (show) and sample each frame until the motion is over: [{ mode, p, q, scale, dim, ... }]
        function sample(start, mode) {
            var s = []
            start()
            for (var i = 0; i < 300; i++) {
                if (recents._mode === mode)
                    s.push({ p: recents.openMotion.p, q: recents.closeMotion.q,
                             scale: recents.behindScale, dim: recents.behindDim,
                             appScale: wt.appScale, appDim: wt.appDim,
                             moving: wt.recentsMoving, over: wt.recentsOverApp,
                             faceScale: recents.faceScale, faceAlpha: recents.faceAlpha, faceDim: recents.faceDim,
                             faceMoving: recents.faceMoving })
                if (recents._mode === "" && i > 0)
                    break
                wait(16)
            }
            compare(recents._mode, "", "the motion ended")
            return s
        }

        // ---- D60-24: Recents over an application ----

        function test_01_over_app_open_shrinks_and_dims_the_app() {
            lipstickComp.homeActive = false
            comp.appActive = true
            var s = sample(function () { recents.show(); recents.entries = entries(2) }, "open")
            compare(recents.movesFace, false, "over an application: the face does not move")
            verify(s.length >= 3, "frames of the opening: " + s.length)
            var mid = false
            for (var i = 0; i < s.length; i++) {
                var f = s[i]
                // the closing task of the app launch: scale 1 - 0.3 p, dim 0.5 p
                fuzzyCompare(f.scale, 1 - 0.3 * f.p, 1e-6, "scale 1 - 0.3 p at p " + f.p)
                fuzzyCompare(f.dim, 0.5 * f.p, 1e-6, "dim 0.5 p at p " + f.p)
                compare(f.appScale, f.scale, "the application layer takes the scale")
                compare(f.appDim, f.dim, "and the dim")
                verify(f.over && f.moving, "Recents over the application, moving")
                compare(f.faceScale, 1)
                compare(f.faceDim, 0)
                compare(f.faceMoving, false)
                if (f.p > 0.2 && f.p < 0.8)
                    mid = true
            }
            verify(mid, "a frame in the middle of the opening: " + s.map(function (f) { return f.p.toFixed(3) }).join(" "))
            // at rest: the end of the opening, under the opaque disc
            compare(recents.progress, 1)
            fuzzyCompare(wt.appScale, 0.70, 1e-9)
            fuzzyCompare(wt.appDim, 0.5, 1e-9)
            compare(wt.recentsOverApp, true)
            compare(wt.recentsMoving, false, "at rest: no circle mask, no black under the layers")
        }

        function test_02_over_app_close_brings_the_app_back() {
            lipstickComp.homeActive = false
            comp.appActive = true
            recents.show()
            recents.entries = entries(2)
            tryCompare(recents, "_mode", "", 3000)
            var s = sample(function () { recents.close() }, "close")
            verify(s.length >= 3, "frames of the closing: " + s.length)
            for (var i = 0; i < s.length; i++) {
                var f = s[i]
                // back from 0.70 to 1 on the face's spring q
                fuzzyCompare(f.scale, 1 - 0.3 * (1 - f.q), 1e-6, "scale at q " + f.q)
                fuzzyCompare(f.dim, 0.5 * (1 - f.q), 1e-6, "dim at q " + f.q)
                compare(f.appScale, f.scale)
                compare(f.appDim, f.dim)
                compare(f.faceScale, 1)
            }
            compare(recents.isOpen, false)
            compare(wt.recentsOverApp, false)
            compare(wt.appScale, 1)
            compare(wt.appDim, 0)
        }

        function test_03_over_the_face_the_app_layer_is_not_touched() {
            var s = sample(function () { recents.show(); recents.entries = entries(2) }, "open")
            compare(recents.movesFace, true, "over the face: the face moves")
            for (var i = 0; i < s.length; i++) {
                compare(s[i].over, false)
                compare(s[i].appScale, 1)
                compare(s[i].appDim, 0)
            }
        }

        // ---- D60-25: Recents over the face moves the face ----

        function test_04_over_the_face_open_moves_the_face() {
            compare(WM.LAUNCH.baseline.stiffness, 260)
            compare(WM.LAUNCH.baseline.dampingRatio, 1.0)
            compare(WM.LAUNCH.behindDrop, 0.30)
            compare(WM.LAUNCH.behindDim, 0.5)
            var s = sample(function () { recents.show(); recents.entries = entries(2) }, "open")
            compare(recents.movesFace, true)
            verify(s.length >= 3, "frames of the opening: " + s.length)
            for (var i = 0; i < s.length; i++) {
                var f = s[i]
                fuzzyCompare(f.faceScale, 1 - 0.3 * f.p, 1e-6, "face scale 1 - 0.3 p at p " + f.p)
                fuzzyCompare(f.faceDim, 0.5 * f.p, 1e-6, "face dim 0.5 p at p " + f.p)
                compare(f.faceAlpha, 1)
                compare(f.faceMoving, true, "the face is cropped to a circle while it moves")
            }
            // at rest under the opaque disc: the face as it was
            compare(recents.faceScale, 1)
            compare(recents.faceDim, 0)
            compare(recents.faceMoving, false)
        }

        function test_05_over_the_face_close_grows_the_face_from_half() {
            compare(WM.HOME.face.stiffness, 260)
            compare(WM.HOME.face.dampingRatio, 1.0)
            compare(WM.HOME.faceStart, 0.5)
            recents.show()
            recents.entries = entries(2)
            tryCompare(recents, "_mode", "", 3000)
            var s = sample(function () { recents.close() }, "close")
            verify(s.length >= 3, "frames of the closing: " + s.length)
            for (var i = 0; i < s.length; i++) {
                var f = s[i]
                fuzzyCompare(f.faceScale, 0.5 + 0.5 * f.q, 1e-6, "face scale 0.5 + 0.5 q at q " + f.q)
                fuzzyCompare(f.faceAlpha, 0.5 + 0.5 * f.q, 1e-6, "face alpha 0.5 + 0.5 q at q " + f.q)
                compare(f.faceDim, 0)
                compare(f.faceMoving, true)
            }
            compare(recents.faceScale, 1)
            compare(recents.faceAlpha, 1)
            compare(recents.faceMoving, false)
        }

        // ---- D60-09: the scroll indicator when the list has come in ----

        function test_06_indicator_once_the_list_has_come_in() {
            tryVerify(function () { var ind = indicator(); return ind === null || !ind.shown }, 5000, "no indicator before")
            recents.show()
            recents.entries = entries(8)
            var during = false
            for (var i = 0; i < 300 && recents._mode === "open"; i++) {
                if (recents.launcher.item && indicatorOn(recents.launcher.item.view))
                    during = true
                wait(16)
            }
            compare(recents._mode, "", "the opening ended")
            var view = recents.launcher.item.view
            verify(view.contentHeight + view.topMargin + view.bottomMargin > view.height, "8 rows scroll")
            compare(during, false, "not while the list zooms in")
            tryVerify(function () { return indicatorOn(view) }, 1000, "the indicator on the list once it has come in")
            var ind = indicator()
            wait(1500)
            verify(ind.shown, "still there 1.5 s later")
            tryVerify(function () { return !ind.shown }, 3000, "hidden about 2 s later")
            compare(recents.flashIndicator(), true, "flashIndicator() took the list")
        }

        // the indicator only for a list that scrolls: the decision is RotaryInput's (qml-asteroid); an
        // empty Recents (header and empty text) and a list of 8 rows, whichever of them scroll
        function test_07_indicator_only_for_a_list_that_scrolls() {
            var counts = [0, 8]
            for (var c = 0; c < counts.length; c++) {
                if (recents.isOpen)
                    recents.closeNow()
                tryVerify(function () { var ind = indicator(); return ind === null || !ind.shown }, 5000, "no indicator before")
                recents.show()
                recents.entries = entries(counts[c])
                tryCompare(recents, "_mode", "", 3000)
                var view = recents.launcher.item.view
                var scrolls = view.contentHeight + view.topMargin + view.bottomMargin > view.height + 1
                if (counts[c] === 8)
                    verify(scrolls)
                wait(300)
                compare(indicatorOn(view), scrolls, counts[c] + " rows, scrolls " + scrolls)
            }
        }
    }
}
