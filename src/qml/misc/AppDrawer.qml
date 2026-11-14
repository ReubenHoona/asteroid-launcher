/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "compositor"
import "compositor/windowmotion.js" as WM

/*
 * The app list of the Wear layout, over the watchface: Wear OS opens it
 * with the crown button and it comes in as an app does (the launch
 * transition: 0.45 -> 1 on a spring, fading in, the face behind it shrinking
 * to 0.70 under a 50 % dim) and goes as the crown in an app does (0.60, the
 * face growing from 0.5; W2-launcher-window-motion). A swipe right from
 * anywhere follows the finger, squeezes it and closes it past half the
 * screen or on a flick; the crown button closes it too. A swipe right on
 * the watchface pulls it in under the finger (dragBy/release from the
 * panels grid), for watches whose crown press is not set up.
 *
 * "source" is the app launcher chosen in Settings (the Wear list by
 * default); it is created once, at start, so opening costs no loading.
 */
Item {
    id: drawer

    property alias source: launcher.source
    property alias launcher: launcher
    // 0 closed .. 1 open
    property real progress: 0
    readonly property bool isOpen: progress > 0
    readonly property real _dismiss: dismissArea.state === "swipe" ? dismissArea.progress : 0

    /* The motion (motion-transitions-05, -06): "open" runs the app launch
     * springs (AppOpen), "close" the way back to the face (WatchfaceReveal);
     * "" is at rest, or a finger pulling the list in (dragBy). progress is
     * how open the list is for the code that reads it. The face behind is
     * drawn by MainScreen from face* (only for the app list over the face:
     * movesFace). */
    property string _mode: ""
    property bool movesFace: true
    // the springs, for the tests
    readonly property QtObject openMotion: opening
    readonly property QtObject closeMotion: closing
    readonly property real _scale: _mode === "close" ? closing.topScale
                                   : (_mode === "open" ? opening.scale : WM.LAUNCH.startScale + (1 - WM.LAUNCH.startScale) * progress)
    readonly property real _alpha: _mode === "close" ? closing.topAlpha
                                   : (_mode === "open" ? opening.alpha : progress)
    readonly property real faceScale: movesFace ? (_mode === "open" ? opening.behindScale
                                                  : (_mode === "close" ? closing.faceScale : 1)) : 1
    readonly property real faceAlpha: movesFace && _mode === "close" ? closing.faceAlpha : 1
    readonly property real faceDim: movesFace && _mode === "open" ? opening.behindDim : 0
    readonly property bool faceMoving: movesFace && _mode !== ""

    visible: progress > 0 || _warming
    anchors.fill: parent

    /* Draw the list once where nobody sees it (into a tiny layer, the list
     * itself hidden), so its first opening does not make its textures,
     * icons and text in its first frames */
    property bool _warming: false
    property int _warmFrames: 0
    function prewarm() {
        if (isOpen || _warming)
            return
        _warmFrames = 0
        _warming = true
    }
    Connections {
        target: drawer.Window.window
        enabled: drawer._warming
        function onFrameSwapped() {
            if (++drawer._warmFrames >= 2)
                drawer._warming = false
        }
    }
    ShaderEffectSource {
        // a pixel in the screen's corner, under the round mask
        width: 1
        height: 1
        z: -1
        opacity: 0.01
        visible: drawer._warming
        sourceItem: drawer._warming ? content : null
        hideSource: true
        textureSize: Qt.size(32, 32)
    }

    AppOpen {
        id: opening
        onPChanged: if (drawer._mode === "open") drawer.progress = p
        onFinished: if (drawer._mode === "open") { drawer._mode = ""; drawer.progress = 1 }
    }

    WatchfaceReveal {
        id: closing
        onAChanged: if (drawer._mode === "close") drawer.progress = 1 - a
        onFinished: if (drawer._mode === "close") {
            drawer._mode = ""
            drawer.progress = 0
            drawer.reset()
        }
    }

    function open() {
        closing.stop()
        dismissArea.reset()
        dismissArea.state = ""
        if (progress >= 1 && _mode === "")
            return
        // a list pulled in by a finger goes on from where it is
        var from = progress
        _mode = "open"
        // the content slides up as the list opens (app-launcher-08)
        if (launcher.item && launcher.item.intro)
            launcher.item.intro()
        opening.start(from)
    }

    function close() {
        opening.stop()
        if (progress <= 0)
            return
        // a list closing in the middle of its opening goes on from the size it has
        var a0 = Math.max(0, Math.min(1, (1 - _scale) / WM.HOME.topDrop))
        _mode = "close"
        closing.start(a0)
    }

    // at once, without the opening animation (back from an app)
    function openNow() {
        opening.stop()
        closing.stop()
        _mode = ""
        dismissArea.reset()
        dismissArea.state = ""
        progress = 1
    }

    function closeNow() {
        opening.stop()
        closing.stop()
        _mode = ""
        progress = 0
        reset()
    }

    function reset() {
        dismissArea.reset()
        dismissArea.state = ""
        if (launcher.item && launcher.item.resetPosition)
            launcher.item.resetPosition()
    }

    // pulled in from the watchface
    function dragBy(dx) {
        opening.stop()
        closing.stop()
        _mode = ""
        progress = Math.max(0, Math.min(1, progress + dx / width))
    }
    function release(velocity) {
        if (progress > 0.35 || velocity > 10)
            open()
        else
            close()
    }

    // nothing under the open list takes a touch
    MouseArea {
        anchors.fill: parent
        enabled: drawer.isOpen
    }

    BackSwipeArea {
        id: dismissArea
        anchors.fill: parent
        swipeEnabled: drawer.progress >= 1
        // no touch reaches the list while it is only drawn to warm it up
        enabled: drawer.progress > 0

        onStarted: {
            dismissAnim.stop()
            settleAnim.stop()
            state = "swipe"
        }
        onFinished: {
            if (committed) {
                dismissAnim.restart()
            } else {
                settleAnim.restart()
            }
        }
        states: State { name: "swipe" }

        Item {
            id: content
            anchors.fill: parent
            // opening: 0.45 -> 1 and fading in (the launch springs); closing:
            // 1 -> 0.60 and fading out; swiped away: follows the finger,
            // squeezes to 0.8 and fades in the last part
            opacity: drawer._warming ? 1 : drawer._alpha * (drawer._dismiss < 0.6 ? 1 : 1 - (drawer._dismiss - 0.6) / 0.4)
            transform: [
                Scale {
                    origin.x: content.width / 2
                    origin.y: content.height / 2
                    xScale: drawer._scale * (1 - 0.2 * drawer._dismiss)
                    yScale: xScale
                },
                Translate { x: dismissArea.state === "swipe" ? dismissArea.value - 0.1 * drawer._dismiss * content.width : 0 }
            ]

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#000000"
            }

            Loader {
                id: launcher
                anchors.fill: parent
                // what the app launchers expect of their panel
                property bool fakePressed: false
                property bool toTopAllowed: false
                property bool toBottomAllowed: false
                property bool toLeftAllowed: false
                property bool toRightAllowed: false
                property bool forbidTop: false
                property bool forbidBottom: false
                property bool forbidLeft: false
                property bool forbidRight: false
            }
        }
    }

    // a new view (Grid view, List view): it fades in over 100 ms (izy.java changeUiModeFromViewSwitcher)
    Connections {
        target: launcher
        function onSourceChanged() {
            if (drawer.isOpen && launcher.source != "" && Motion.animationScale > 0)
                viewFade.restart()
        }
    }
    NumberAnimation {
        id: viewFade
        target: launcher
        property: "opacity"
        from: 0
        to: 1
        duration: 100
    }

    NumberAnimation {
        id: settleAnim
        target: dismissArea
        property: "value"
        to: 0
        duration: 200
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0, 0, 0.2, 1, 1, 1]
        onFinished: { dismissArea.state = ""; dismissArea.reset() }
    }

    SequentialAnimation {
        id: dismissAnim
        NumberAnimation {
            target: dismissArea
            property: "value"
            to: drawer.width
            duration: 200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0, 0, 0.2, 1, 1, 1]
        }
        ScriptAction { script: drawer.closeNow() }
    }
}
