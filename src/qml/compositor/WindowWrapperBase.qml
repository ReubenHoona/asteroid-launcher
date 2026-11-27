/*
 * Copyright (C) 2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 *               2013 Jolla Ltd.
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import QtQuick
import org.asteroid.controls
import org.asteroid.utils
import "windowmotion.js" as WM

Item {
    id: wrapper

    property Item window
    property bool smoothBorders: false
    width: window !== null ? Dims.w(100) : 0
    height: window !== null ? Dims.h(100) : 0

    /* Wear OS opens a window with the app launch transition
     * (WearAppLaunchMixinTransition, W2-launcher-window-motion): scale 0.45
     * -> 1 about the middle of the screen on a spring (damping 1.0,
     * stiffness 260) and alpha 0 -> 1 on a quick one (stiffness 5000),
     * while the face or the app list behind it shrinks. The springs are
     * the compositor's (WindowTransitions.launch, AppOpen); this window
     * follows them while `opening`, from WindowTransitions.openWindow().
     * At rest it is at full size and opaque. */
    property QtObject motion: null
    property bool opening: false
    readonly property real openScale: opening && motion ? motion.scale : 1
    opacity: (opening && motion ? motion.alpha : 1) * exitOpacity

    /* R5 B-05: the application closed its window itself (lipstick keeps the last frame while the window's
     * delayRemove is set and says closing()): the framework task close exit, motion A6
     * (WearMixedTransitionHandler.java:110-131 hands it to the framework's taskCloseExitAnimation,
     * anim-watch/rounded_window_exit.xml: scale 1 -> 0.75 about the centre and alpha 1 -> 0, both 250 ms on
     * (0.4, 0, 0.2, 1); windowmotion.js EXIT), then the window goes (delayRemove false). AppLifecycle decides
     * (lifecycle.js exitsWithMotion) and calls playExit() or finishExit(). */
    signal closedByApp()
    property bool exiting: false
    property real exitScale: 1
    property real exitOpacity: 1
    readonly property alias exitAnimation: exitAnim
    function playExit() {
        exiting = true
        exitAnim.restart()
    }
    function finishExit() {
        exitAnim.stop()
        if (window && window.delayRemove !== undefined)
            window.delayRemove = false
    }
    Connections {
        target: wrapper.window
        ignoreUnknownSignals: true
        function onClosing() { wrapper.closedByApp() }
    }
    ParallelAnimation {
        id: exitAnim
        NumberAnimation {
            target: wrapper; property: "exitScale"; from: 1; to: WM.EXIT.toScale
            duration: Motion.duration(WM.EXIT.durationMs)
            easing.type: Easing.BezierSpline; easing.bezierCurve: WM.EXIT.bezier
        }
        NumberAnimation {
            target: wrapper; property: "exitOpacity"; from: 1; to: 0
            duration: Motion.duration(WM.EXIT.durationMs)
            easing.type: Easing.BezierSpline; easing.bezierCurve: WM.EXIT.bezier
        }
        onFinished: wrapper.finishExit()
    }

    // from a complication or the chip the window also moves out of the tapped
    // element (the origin launch, motion A2: AppOpen dx, dy)
    transform: [
        Scale {
            origin.x: wrapper.width / 2
            origin.y: wrapper.height / 2
            xScale: wrapper.openScale * wrapper.exitScale
            yScale: wrapper.openScale * wrapper.exitScale
        },
        Translate {
            x: wrapper.opening && wrapper.motion ? wrapper.motion.dx : 0
            y: wrapper.opening && wrapper.motion ? wrapper.motion.dy : 0
        }
    ]

    Component.onCompleted: {
        window.parent = wrapper
        window.x = 0
        window.y = 0
    }

    layer.enabled: smoothBorders && DeviceSpecs.hasRoundScreen
    layer.effect: CircleMaskShader { }
}
