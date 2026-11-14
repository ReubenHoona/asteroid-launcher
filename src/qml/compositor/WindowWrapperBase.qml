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
    opacity: opening && motion ? motion.alpha : 1

    transform: Scale {
        origin.x: wrapper.width / 2
        origin.y: wrapper.height / 2
        xScale: wrapper.openScale
        yScale: wrapper.openScale
    }

    Component.onCompleted: {
        window.parent = wrapper
        window.x = 0
        window.y = 0
    }

    layer.enabled: smoothBorders && DeviceSpecs.hasRoundScreen
    layer.effect: CircleMaskShader { }
}
