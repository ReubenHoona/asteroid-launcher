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

Item {
    id: wrapper

    property Item window
    property bool smoothBorders: false
    width: window !== null ? Dims.w(100) : 0
    height: window !== null ? Dims.h(100) : 0

    /* Wear OS window open (AOSP frameworks/base core/res/res
     * anim-watch/rounded_window_enter.xml): scale 0.75 -> 1 over 250 ms and
     * alpha 0.25 -> 1 over 150 ms about the middle of the screen, with the
     * watch window interpolator (0.4, 0, 0.2, 1). Over the launch splash,
     * which already zoomed out of the icon, the window only fades in. */
    property real openScale: 1
    readonly property var _easing: [0.4, 0, 0.2, 1, 1, 1]

    transform: Scale {
        origin.x: wrapper.width / 2
        origin.y: wrapper.height / 2
        xScale: wrapper.openScale
        yScale: wrapper.openScale
    }

    ParallelAnimation {
        id: zoomIn
        NumberAnimation {
            target: wrapper; property: "openScale"; from: 0.75; to: 1; duration: 250
            easing.type: Easing.BezierSpline; easing.bezierCurve: wrapper._easing
        }
        NumberAnimation {
            target: wrapper; property: "opacity"; from: 0.25; to: 1; duration: 150
            easing.type: Easing.BezierSpline; easing.bezierCurve: wrapper._easing
        }
        onFinished: wrapper.parent.ready = true
    }

    NumberAnimation {
        id: fadeIn
        target: wrapper; property: "opacity"; from: 0; to: 1; duration: 150
        easing.type: Easing.BezierSpline; easing.bezierCurve: wrapper._easing
        onFinished: wrapper.parent.ready = true
    }

    function animateIn(overSplash) {
        zoomIn.stop()
        fadeIn.stop()
        openScale = 1
        if (overSplash)
            fadeIn.start()
        else
            zoomIn.start()
    }

    Component.onCompleted: {
        window.parent = wrapper
        window.x = 0
        window.y = 0
    }

    layer.enabled: smoothBorders && DeviceSpecs.hasRoundScreen
    layer.effect: CircleMaskShader { }
}
