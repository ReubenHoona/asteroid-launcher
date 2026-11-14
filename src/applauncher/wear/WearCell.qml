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
    // A white centre colour (X-Asteroid-Center-Color=#FFFFFF) marks an app that draws its own full-colour icon with
    // its own disc (the Flashlight): the file is drawn as it is, not as a white glyph on a white disc (apps-misc-02)
    readonly property bool ownIcon: discColor.r >= 0.99 && discColor.g >= 0.99 && discColor.b >= 0.99
    readonly property string iconUrl: iconId === "" ? "" : (iconId.charAt(0) === "/" ? "file://" + iconId
                                                                                   : "file:///usr/share/icons/asteroid/" + iconId + ".svg")
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
        visible: !cell.ownIcon
    }

    Image {
        objectName: "ownIcon"
        anchors.fill: disc
        visible: cell.ownIcon && cell.iconUrl !== ""
        source: visible ? cell.iconUrl : ""
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: cell.contentAlpha
    }

    Icon {
        visible: !cell.ownIcon
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
