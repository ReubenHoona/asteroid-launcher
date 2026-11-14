/*
 * Copyright (C) 2015 Florent Revest <revestflo@gmail.com>
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
import "qs.js" as QS

/*
 * A quick settings button, as stock CP3A's M3 IconToggleButton (SysUI lah.java:744-824,
 * dcw.java:954-972; androidx IconToggleButton.kt):
 *  - off: surfaceContainer container, onSurface icon, a circle; on: primaryDim
 *    container, onPrimary icon, a rounded square of Theme.shape.medium (18 dp);
 *  - pressed: the corners x 0.66, on a spring of stiffness 1400 (press) and
 *    500 (release), damping 1.0; the colours tween 250 ms, CubicBezier(0, 0, 0, 1);
 *  - disabled: onSurface 12 % container, 38 % icon;
 *  - a second tap within 300 ms is ignored (lah.java:22-31), a long press (400 ms)
 *    is its own signal and no tap;
 *  - the panel's edge morph sets containerAlpha / contentAlpha.
 * The panel's size is the item's width (52 dp); the icon 26 dp (battery and phone
 * 32 dp, flashlight 27 dp).
 *
 * A tap is `activated()`, not `clicked()`: clicked() is the raw mouse signal.
 */
MouseArea {
    id: ma

    width: parent ? parent.width : Theme.dp(52)
    height: width

    property alias icon: ic.name
    property bool checkable: false
    property bool checked: false
    /*! The icon, px. */
    property real iconSize: Theme.dp(26)
    /*! What the screen reader says. */
    property string label: ""

    /* the stock colour roles; the battery saver uses its own */
    property color checkedContainer: Theme.color.primaryDim
    property color checkedContent: Theme.color.onPrimary
    property color uncheckedContainer: Theme.color.surfaceContainer
    property color uncheckedContent: Theme.color.onSurface
    /*! Colour the icon with tintColor when it is off and enabled (the battery at 15 % or less). */
    property bool tinted: false
    property color tintColor: Theme.color.errorDim

    /* the edge morph of the panel */
    property real containerAlpha: 1
    property real contentAlpha: 1

    property int debounce: QS.TAP_DEBOUNCE_MS
    /*! ms; tests replace it. */
    property var clock: function () { return Date.now() }
    property real _last: -1e12
    property bool _held: false

    /*! The tap, once the debounce has let it through. */
    signal activated()
    /*! A press held for 400 ms. */
    signal longPressed()

    /*! What the icon sits in, on top of it: the battery's glyph and percent. */
    default property alias content: _content.data

    pressAndHoldInterval: QS.LONG_PRESS_MS

    readonly property bool lit: checkable && checked
    function _a(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    readonly property color containerColor: !enabled ? _a(Theme.color.onSurface, Theme.alpha.disabledContainer)
                                            : lit ? checkedContainer : uncheckedContainer
    readonly property color contentColor: !enabled ? _a(Theme.color.onSurface, Theme.alpha.disabledContent)
                                          : lit ? checkedContent : tinted ? tintColor : uncheckedContent
    /*! The corner radius the spring is heading for. */
    readonly property real targetRadius: (lit ? Theme.shape.medium : width / 2) * (pressed ? 0.66 : 1)
    readonly property real radius: _morph.value
    readonly property alias shape: _shape

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.checkable: checkable
    Accessible.checked: checked
    Accessible.onPressAction: _tap()

    onPressed: _held = false
    onCanceled: _held = false
    onPressAndHold: {
        _held = true
        longPressed()
    }
    function _tap() {
        var now = clock()
        if (!QS.acceptTap(now, _last, debounce))
            return
        _last = now
        activated()
    }
    onClicked: {
        if (_held) {
            _held = false
            return
        }
        _tap()
    }

    Rectangle {
        id: _shape
        anchors.fill: parent
        radius: ma.radius
        color: ma.containerColor
        opacity: ma.containerAlpha
        Behavior on color {
            ColorAnimation {
                duration: Motion.duration(250)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.easing.standardDecelerate
            }
        }

        WearSpring {
            id: _morph
            to: ma.targetRadius
            stiffness: ma.pressed ? Motion.standard.fastSpatial.stiffness : Motion.standard.defaultSpatial.stiffness
            dampingRatio: 1.0
        }

        Ripple {
            radius: ma.radius
            color: ma.contentColor
            pressed: ma.pressed
            pressX: ma.mouseX
            pressY: ma.mouseY
        }
    }

    Item {
        id: _content
        anchors.fill: parent
        opacity: ma.contentAlpha
    }

    Icon {
        id: ic
        width: ma.iconSize
        height: width
        anchors.centerIn: parent
        color: ma.contentColor
        opacity: ma.contentAlpha
        Behavior on color {
            ColorAnimation {
                duration: Motion.duration(250)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.easing.standardDecelerate
            }
        }
    }
}
