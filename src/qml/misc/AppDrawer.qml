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
 * anywhere is the swipe back from an app's root (the list is an activity in
 * stock; motion B4): it shrinks to 0.70 with its right edge on the screen's,
 * the face grows 0.85 -> 0.93 under the dims, and past the back rule its left
 * edge springs off (1.0/600) while the face comes to 1; else it springs back
 * (1.0/1500). The crown button closes it too. A swipe right on
 * the watchface pulls it in under the finger (dragBy/release from the
 * panels grid), for watches whose crown press is not set up.
 *
 * "source" is the app launcher chosen in Settings (the Wear list by
 * default); it is created once, at start, so opening costs no loading.
 */
Item {
    id: drawer

    // the launcher to show; a change while the list is open cross-fades (D4, _switchTo)
    property url source
    onSourceChanged: _switchTo(source)
    property alias launcher: launcher
    // 0 closed .. 1 open
    property real progress: 0
    readonly property bool isOpen: progress > 0

    /* The swipe back (motion B4; CrossTaskBackAnimation.java:25-34,84-87,108-160,
     * windowmotion.js back() and commit(), as WindowTransitions does for an app):
     * "" none, "swipe" the finger (the smoothed progress), "cancel" the progress
     * springing back, "commit" the left edge springing to the width */
    property string _back: ""
    property real _commitLeft0: 0
    property real _commitHomeDim0: 0
    property real _commitAppDim0: 0
    readonly property var _backPose: _back === "commit"
        ? WM.commit(commitSpring.value, _commitLeft0, _commitHomeDim0, _commitAppDim0, width)
        : (_back === "swipe" ? WM.back(dismissArea.smoothedProgress, width)
           : (_back === "cancel" ? WM.back(cancelSpring.value, width) : null))

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
    readonly property real faceScale: movesFace ? (_backPose ? _backPose.homeScale
                                                  : (_mode === "open" ? opening.behindScale
                                                     : (_mode === "close" ? closing.faceScale : 1))) : 1
    readonly property real faceAlpha: movesFace && !_backPose && _mode === "close" ? closing.faceAlpha : 1
    readonly property real faceDim: movesFace ? (_backPose ? _backPose.homeDim
                                                 : (_mode === "open" ? opening.behindDim : 0)) : 0
    readonly property bool faceMoving: movesFace && (_mode !== "" || _back !== "")
    /* What is behind the list whatever it is (the face, or the application under
     * Recents: WindowTransitions reads these): the closing task of the app launch
     * transition, 1 -> 0.70 under a black dim 0 -> 0.5 on the opening's baseline
     * spring (behindP = its p); on the way back from 0.70 to 1 on the face's spring
     * (WatchfaceReveal q); behind a back swipe the swipe's home pose. At rest open
     * the end of the opening (under the list's opaque disc). */
    readonly property real behindP: _mode === "open" ? opening.p
                                    : (_mode === "close" ? 1 - closing.q : (isOpen ? 1 : 0))
    readonly property real behindScale: _backPose ? _backPose.homeScale
                                        : (_mode === "open" ? opening.behindScale : 1 - WM.LAUNCH.behindDrop * behindP)
    readonly property real behindDim: _backPose ? _backPose.homeDim
                                      : (_mode === "open" ? opening.behindDim : WM.LAUNCH.behindDim * behindP)
    readonly property bool behindMoving: _mode !== "" || _back !== ""

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
        commitSpring.stop()
        cancelSpring.stop()
        _back = ""
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
        // a swipe back already taking the list off ends at once; one on its way
        // back or under the finger gives way to the close
        if (_back === "commit") {
            closeNow()
            return
        }
        if (_back !== "") {
            commitSpring.stop()
            cancelSpring.stop()
            _back = ""
            dismissArea.reset()
            dismissArea.state = ""
        }
        // a list closing in the middle of its opening goes on from the size it has
        var a0 = Math.max(0, Math.min(1, (1 - _scale) / WM.HOME.topDrop))
        _mode = "close"
        closing.start(a0)
    }

    // at once, without the opening animation (back from an app)
    function openNow() {
        opening.stop()
        closing.stop()
        commitSpring.stop()
        cancelSpring.stop()
        _back = ""
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
        _endSwitch()
        commitSpring.stop()
        cancelSpring.stop()
        _back = ""
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
            commitSpring.stop()
            cancelSpring.stop()
            state = "swipe"
            drawer._back = "swipe"
        }
        onFinished: {
            var p = smoothedProgress
            if (committed) {
                // the left edge springs off from where the swipe left it, the dims
                // go on from theirs (CrossTaskDismissalAnimation)
                var b = WM.back(p, drawer.width)
                drawer._commitLeft0 = b.appLeft
                drawer._commitHomeDim0 = b.homeDim
                drawer._commitAppDim0 = b.appDim
                commitSpring.snapTo(b.appLeft)
                drawer._back = "commit"
                commitSpring.animateTo(drawer.width)
            } else {
                cancelSpring.snapTo(p)
                drawer._back = "cancel"
                cancelSpring.animateTo(0, smoothedVelocity)
            }
        }
        states: State { name: "swipe" }

        Item {
            id: content
            anchors.fill: parent
            // opening: 0.45 -> 1 and fading in (the launch springs); closing:
            // 1 -> 0.60 and fading out; swiped back: pinned to the right edge,
            // shrinking to 0.70 under its dim, no fade (B4)
            opacity: drawer._warming ? 1 : drawer._alpha
            transform: [
                Scale {
                    origin.x: content.width / 2
                    origin.y: content.height / 2
                    xScale: drawer._scale * (drawer._backPose ? drawer._backPose.appScale : 1)
                    yScale: xScale
                },
                // the left edge at appLeft: the scaled list's own left edge is w (1 - s) / 2
                Translate { x: drawer._backPose ? drawer._backPose.appLeft - content.width * (1 - drawer._backPose.appScale) / 2 : 0 }
            ]

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#000000"
            }
            // the black dim over the list while it is swiped back
            Rectangle {
                z: 1000
                anchors.fill: parent
                radius: width / 2
                color: "black"
                opacity: drawer._backPose ? drawer._backPose.appDim : 0
                visible: opacity > 0
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
            // the old view while the new one comes in (D4): a still picture of it, taken
            // only for the switch
            ShaderEffectSource {
                id: oldView
                anchors.fill: parent
                visible: false
                live: false
                hideSource: false
            }
        }
    }

    /* A new view (Grid view, List view) while the list is open: the AnimatedContent of
     * the switch (izy.java changeUiModeFromViewSwitcher; D/ivh.java:19-22, hdu.java:578-590,
     * launcher_ui_mode_reload_fade_anim_duration_ms 100): the old view fades out in 100 ms
     * and the new one fades in in 100 ms after 100 ms, both linear (motion D4). The old view
     * is pictured in the frames before the swap; the swap waits two frames (one may have
     * been on its way already). */
    property url _pendingSource
    property bool _switching: false
    property int _switchFrames: 0
    function _switchTo(s) {
        _endSwitch()
        if (launcher.source == s)
            return
        if (!isOpen || s == "" || launcher.source == "" || !launcher.item || Motion.animationScale === 0) {
            launcher.source = s
            return
        }
        _pendingSource = s
        _switchFrames = 0
        _switching = true
        oldView.sourceItem = launcher
        oldView.visible = true
        oldView.opacity = 1
        oldView.scheduleUpdate()
    }
    function _swap() {
        if (!_switching)
            return
        _switching = false
        launcher.opacity = 0
        launcher.source = _pendingSource
        viewFade.restart()
    }
    function _endSwitch() {
        if (_switching) {
            _switching = false
            launcher.source = _pendingSource
        }
        viewFade.stop()
        launcher.opacity = 1
        oldView.visible = false
        oldView.sourceItem = null
    }
    Connections {
        target: drawer.Window.window
        enabled: drawer._switching
        function onFrameSwapped() {
            if (++drawer._switchFrames >= 2)
                drawer._swap()
        }
    }
    ParallelAnimation {
        id: viewFade
        NumberAnimation { target: oldView; property: "opacity"; to: 0; duration: 100 }
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: launcher; property: "opacity"; from: 0; to: 1; duration: 100 }
        }
        onFinished: {
            oldView.visible = false
            oldView.sourceItem = null
        }
    }

    // the swipe let go short of the back rule: the progress springs back (B4, WM.BACK.cancel)
    WearSpring {
        id: cancelSpring
        stiffness: WM.BACK.cancel.stiffness
        dampingRatio: WM.BACK.cancel.dampingRatio
        visibilityThreshold: 0.0005
        onFinished: if (drawer._back === "cancel") {
            drawer._back = ""
            dismissArea.state = ""
            dismissArea.reset()
        }
    }

    // past it: the list's left edge springs to the width, the face comes to 1 (B4, WM.BACK.commit)
    WearSpring {
        id: commitSpring
        stiffness: WM.BACK.commit.stiffness
        dampingRatio: WM.BACK.commit.dampingRatio
        stopAtFraction: WM.BACK.commit.stopAtFraction
        visibilityThreshold: WM.BACK.commit.visibleChange
        onFinished: if (drawer._back === "commit") drawer.closeNow()
    }
}
