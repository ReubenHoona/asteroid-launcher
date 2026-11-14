/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "WearEdge.js" as Edge

/*
 * One icon of the Wear grid (app-launcher-16): the app's icon 48 dp (96 px),
 * a circle, no label (the content description is the app's name). A press
 * shows the shared ripple over the circle, a long press (400 ms) opens the
 * app's info as the list's rows do.
 */
MouseArea {
    id: cell

    property string title: ""
    property string iconId: ""
    property color discColor: Theme.color.primary
    property real contentAlpha: 1
    property bool fakePressed: false

    readonly property alias disc: disc
    readonly property alias ripple: ripple
    readonly property bool held: _held

    signal activated()
    signal longPressed()

    property bool _held: false

    width: Theme.dp(48)
    height: width
    pressAndHoldInterval: Edge.LONG_PRESS_MS
    onPressed: _held = false
    onPressAndHold: {
        _held = true
        Haptics.longPress()
        longPressed()
    }
    onClicked: if (!_held) activated()

    Accessible.role: Accessible.Button
    Accessible.name: title

    Rectangle {
        id: disc
        anchors.fill: parent
        radius: width / 2
        color: cell.discColor
        opacity: cell.contentAlpha
    }

    Icon {
        anchors.centerIn: disc
        width: disc.width * 0.66
        height: width
        color: "white"
        name: cell.iconId === "" ? "ios-help" : cell.iconId
        opacity: cell.contentAlpha
    }

    Ripple {
        id: ripple
        radius: width / 2
        color: "white"
        pressed: cell.pressed || cell.fakePressed
        pressX: cell.mouseX
        pressY: cell.mouseY
        opacity: cell.contentAlpha
    }
}
