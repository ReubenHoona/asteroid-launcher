/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "windowmotion.js" as WM

/*
 * The starting window of Wear OS (WearStartingWindowTypeAlgorithm,
 * W2-launcher-window-motion): from the moment an application is launched
 * until its window can be shown, the application's icon sits centred on a
 * black window. That window is the opening window of the launch transition:
 * it zooms 0.45 -> 1 about the middle of the screen on the launch springs
 * (WindowTransitions.launch, WearAppLaunchMixinTransition) while the face or
 * the app list behind it shrinks and dims; it does not grow out of the
 * tapped icon.
 *
 *   - the icon is the application's own, as the app list draws it: a disc in
 *     the application's colour with a white glyph. An application without a
 *     colour shows its bare glyph, scaled 1.25 (splash_icon_no_background_scale_factor)
 *   - it is shown at least 400 ms, and only when the display is on
 *   - it leaves as Wear OS's TYPE_FADE_OUT does (starting_window_exit_animation_type
 *     = 1): the icon fades out linearly in 50 ms, the whole window fades out
 *     in 200 ms starting at 50 ms (250 ms in all)
 *
 * start(rect, centerColor, outerColor, iconName) (rect and outerColor are
 * not used any more), finish() when the window of the application is shown,
 * cancel() to drop it at once. A launch that brings up no window gives up
 * after 6 s.
 *
 * Nothing runs unless it is shown: the launch springs, one pause and the
 * exit fade; no animation of its own while it waits.
 */
Item {
    id: splash

    // the launch springs (AppOpen), set by compositor.qml
    property QtObject motion: null
    // the starting window only shows with the display on
    property bool displayOn: true
    readonly property bool active: visible && !exitAnim.running
    visible: false

    // for the tests
    readonly property Item glyphItem: glyph
    readonly property Item iconItem: icon
    readonly property Item discItem: disc
    property bool _hasDisc: false
    property bool _finishAsked: false
    property bool _minDone: true

    function start(rect, centerColor, outerColor, iconName) {
        if (!displayOn)
            return
        exitAnim.stop()
        _hasDisc = !!centerColor
        disc.color = centerColor ? centerColor : "transparent"
        icon.name = iconName ? iconName : ""
        glyph.opacity = 1
        opacity = 1
        _finishAsked = false
        _minDone = false
        visible = true
        if (motion)
            motion.start()
        minHold.restart()
        giveUp.restart()
    }

    // the window of the application is shown: leave, after the minimum time
    function finish() {
        if (!visible || exitAnim.running)
            return
        giveUp.stop()
        _finishAsked = true
        if (_minDone)
            _leave()
    }

    function cancel() {
        giveUp.stop()
        minHold.stop()
        exitAnim.stop()
        _finishAsked = false
        _minDone = true
        visible = false
        // the launch springs land (the display went off, the assistant opened)
        if (motion)
            motion.settle()
    }

    function _leave() {
        if (Motion.animationScale === 0) {
            visible = false
            return
        }
        exitAnim.restart()
    }

    // at least 400 ms on screen
    SequentialAnimation {
        id: minHold
        PauseAnimation { duration: WM.SPLASH.minShownMs }
        ScriptAction {
            script: {
                splash._minDone = true
                if (splash._finishAsked)
                    splash._leave()
            }
        }
    }

    // TYPE_FADE_OUT: the icon 50 ms, the window 200 ms after 50 ms
    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            NumberAnimation {
                target: glyph; property: "opacity"; to: 0
                duration: WM.SPLASH.iconFadeMs; easing.type: Easing.Linear
            }
            SequentialAnimation {
                PauseAnimation { duration: WM.SPLASH.revealDelayMs }
                NumberAnimation {
                    target: splash; property: "opacity"; to: 0
                    duration: WM.SPLASH.revealMs; easing.type: Easing.Linear
                }
            }
        }
        ScriptAction { script: splash.visible = false }
    }

    // nothing under the splash takes a touch while it covers the screen
    MouseArea {
        anchors.fill: parent
        enabled: splash.active
    }

    Timer {
        id: giveUp
        interval: 6000
        onTriggered: splash.finish()
    }

    // the opening window: zooms with the launch springs, then stands still
    Item {
        id: plate
        anchors.fill: parent
        readonly property bool zooming: splash.motion ? splash.motion.inProgress : false
        scale: zooming ? splash.motion.scale : 1
        opacity: zooming ? splash.motion.alpha : 1

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: WM.SPLASH.background
        }

        Item {
            id: glyph
            anchors.centerIn: parent
            width: splash.width * WM.SPLASH.iconFraction
            height: width

            Rectangle {
                id: disc
                anchors.fill: parent
                radius: width / 2
                visible: splash._hasDisc
            }

            Icon {
                id: icon
                anchors.centerIn: parent
                // the glyph inside the disc's safe zone (as the app list's row), or bare at 1.25
                width: splash._hasDisc ? parent.width * 0.66 : parent.width * WM.SPLASH.bareIconScale
                height: width
                color: "white"
                visible: name !== ""
            }
        }
    }
}
