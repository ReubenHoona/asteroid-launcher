/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * One button of an open notification's input row: a pill-shaped container (96 px
 * tall in the row, the colour the row gives it) with a 26 dp icon in primary
 * (SysUI kpg.java:237-245). The row (NotificationActions) debounces the taps.
 */
MouseArea {
    id: button

    property string icon: ""
    property string description: ""
    property color containerColor: Theme.color.surfaceContainerHigh
    readonly property alias container: containerRect

    signal triggered()

    height: Theme.dp(48)
    Accessible.role: Accessible.Button
    Accessible.name: description
    onClicked: triggered()

    Rectangle {
        id: containerRect
        anchors.fill: parent
        radius: height / 2
        color: button.containerColor
        Ripple {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.color.primary
            pressed: button.pressed
            pressX: button.mouseX
            pressY: button.mouseY
        }
    }
    Icon {
        anchors.centerIn: parent
        width: Theme.dp(26)
        height: width
        name: button.icon
        color: Theme.color.primary
    }
}
