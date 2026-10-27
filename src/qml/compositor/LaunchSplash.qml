/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * Launch feedback as on Wear OS: the moment an application icon is tapped,
 * a disc in the colours of the application grows out of the icon to fill
 * the screen, with the icon in the middle, and stays until the window of
 * the application is there to fade in over it. An application can take a
 * second or two to start; without this the launcher just sat there.
 *
 * start(rect, centerColor, outerColor, iconName) with rect the icon in
 * scene coordinates (an empty rect zooms from the middle), finish() when the
 * window is shown (fades out under it), cancel() to drop it at once. A
 * launch that brings up no window gives up after 6 s.
 *
 * GPU-cheap: one rounded rectangle with a two-stop gradient and an icon,
 * moved by a Scale and a Translate transform; nothing is laid out again.
 */
Item {
    id: splash

    property var easing: [0.4, 0, 0.2, 1, 1, 1]
    readonly property bool active: visible && !fadeOut.running

    property rect from: Qt.rect(0, 0, 0, 0)
    property real progress: 0
    visible: false

    function start(rect, centerColor, outerColor, iconName) {
        fadeOut.stop()
        from = rect && rect.width > 0 ? rect
                                       : Qt.rect(width * 0.375, height * 0.375, width * 0.25, height * 0.25)
        disc.centerColor = centerColor ? centerColor : "#444444"
        disc.outerColor = outerColor ? outerColor : "#111111"
        icon.name = iconName ? iconName : ""
        opacity = 1
        progress = 0
        visible = true
        zoom.restart()
        giveUp.restart()
    }

    function finish() {
        if (!visible || fadeOut.running)
            return
        giveUp.stop()
        // the window fades in over the splash in 150 ms: leave after it
        fadeOut.restart()
    }

    function cancel() {
        giveUp.stop()
        zoom.stop()
        fadeOut.stop()
        visible = false
    }

    NumberAnimation {
        id: zoom
        target: splash
        property: "progress"
        from: 0
        to: 1
        duration: 250
        easing.type: Easing.BezierSpline
        easing.bezierCurve: splash.easing
    }

    SequentialAnimation {
        id: fadeOut
        PauseAnimation { duration: 150 }
        NumberAnimation { target: splash; property: "opacity"; to: 0; duration: 150 }
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

    Rectangle {
        id: disc

        property color centerColor
        property color outerColor

        width: splash.width
        height: splash.height
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: disc.outerColor }
            GradientStop { position: 0.5; color: disc.centerColor }
            GradientStop { position: 1.0; color: disc.outerColor }
        }

        // from the icon's rectangle to the whole screen
        readonly property real startScale: Math.max(splash.from.width / splash.width, splash.from.height / splash.height)
        readonly property real scaleNow: startScale + (1 - startScale) * splash.progress
        readonly property real startDx: splash.from.x + splash.from.width / 2 - splash.width / 2
        readonly property real startDy: splash.from.y + splash.from.height / 2 - splash.height / 2

        transform: [
            Scale {
                origin.x: disc.width / 2
                origin.y: disc.height / 2
                xScale: disc.scaleNow
                yScale: disc.scaleNow
            },
            Translate {
                x: disc.startDx * (1 - splash.progress)
                y: disc.startDy * (1 - splash.progress)
            }
        ]

        Icon {
            id: icon
            anchors.centerIn: parent
            width: parent.width * 0.3
            height: width
            color: "white"
            visible: name !== ""
        }
    }
}
