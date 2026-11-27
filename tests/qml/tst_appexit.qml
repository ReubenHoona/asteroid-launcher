/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// R5 B-05: an application that closes its window itself leaves with the framework task close exit (motion A6:
// rounded_window_exit, scale 1 -> 0.75 about the centre and alpha 1 -> 0 in 250 ms on (0.4, 0, 0.2, 1)), when it
// is the window in front and seen (lifecycle.js exitsWithMotion); then its delayRemove goes false and lipstick
// removes it. The window is a stand-in with LipstickCompositorWindow's delayRemove and closing(). MODE=st.
import QtQuick
import QtTest
import "st/qml/compositor/lifecycle.js" as Life
import "st/qml/compositor/windowmotion.js" as WM

Item {
    id: top
    width: 384
    height: 384

    Rectangle { anchors.fill: parent; color: "black" }

    Component {
        id: fakeWindow
        Item {
            property bool delayRemove: true
            signal closing()
            Rectangle { anchors.fill: parent; color: "#3060a0" }
        }
    }
    Component {
        id: wrapperComp
        Loader { }
    }

    TestCase {
        name: "AppExit"
        when: windowShown

        function test_01_when_it_moves() {
            verify(Life.exitsWithMotion(true, true, false, false, false))
            verify(!Life.exitsWithMotion(false, true, false, false, false), "not the window in front")
            verify(!Life.exitsWithMotion(true, false, false, false, false), "hidden in the background")
            verify(!Life.exitsWithMotion(true, true, true, false, false), "display off or ambient")
            verify(!Life.exitsWithMotion(true, true, false, true, false), "a system alert")
            verify(!Life.exitsWithMotion(true, true, false, false, true), "a transition already moves it")
            // the numbers are stock's
            compare(WM.EXIT.toScale, 0.75)
            compare(WM.EXIT.durationMs, 250)
            compare(JSON.stringify(WM.EXIT.bezier.slice(0, 4)), "[0.4,0,0.2,1]")
        }

        function test_02_the_exit() {
            var win = createTemporaryObject(fakeWindow, top, { width: 384, height: 384 })
            var ld = createTemporaryObject(wrapperComp, top, { width: 384, height: 384 })
            ld.setSource(Qt.resolvedUrl("st/qml/compositor/WindowWrapperBase.qml"), { window: win })
            tryCompare(ld, "status", Loader.Ready, 10000)
            var w = ld.item
            compare(win.parent, w, "the window sits in its wrapper")
            var spy = createTemporaryObject(spyComp, top, { target: w, signalName: "closedByApp" })
            win.closing()
            compare(spy.count, 1, "lipstick's closing() reaches the wrapper")
            compare(w.exitScale, 1)
            compare(w.opacity, 1)
            w.playExit()
            verify(w.exiting)
            verify(w.exitAnimation.running)
            wait(120)
            verify(w.exitScale < 1 && w.exitScale > 0.75, "on the way: " + w.exitScale)
            verify(w.opacity < 1 && w.opacity > 0, "fading: " + w.opacity)
            compare(win.delayRemove, true, "kept while it moves")
            grabImage(top).save("/tmp/r5ui-shots/b05-exit-mid.png")
            tryCompare(win, "delayRemove", false, 2000)
            compare(w.exitScale, 0.75)
            compare(w.opacity, 0)
        }

        function test_03_at_once() {
            var win = createTemporaryObject(fakeWindow, top, { width: 384, height: 384 })
            var ld = createTemporaryObject(wrapperComp, top)
            ld.setSource(Qt.resolvedUrl("st/qml/compositor/WindowWrapperBase.qml"), { window: win })
            tryCompare(ld, "status", Loader.Ready, 10000)
            var w = ld.item
            w.finishExit()
            compare(win.delayRemove, false)
            compare(w.exitScale, 1)
            verify(!w.exitAnimation.running)
        }
    }
    Component { id: spyComp; SignalSpy { } }
}
