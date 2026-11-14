/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "setup.js" as Setup

/* "Connecting" (setup-wizard-02 e): the orbit animation (3 s a turn) after the phone bonded, with the
 * accessible text "Pairing success" (stock postpair_connected). The page says `played` once the first turn
 * is over; the setup moves on when that is so and the link is up.
 *
 * Power (M1): the orbit runs only while shown with the display on. */
Item {
    id: page
    objectName: "setupConnecting"

    property bool displayOn: true
    property bool active: visible
    readonly property bool animating: displayOn && active && !Motion.reduceMotion
    // one full orbit has been shown
    property bool played: false
    // 0 .. 1 of the orbit
    property real turn: 0

    Accessible.role: Accessible.StaticText
    //% "Pairing success"
    Accessible.name: qsTrId("id-setup-pairing-success") + localeManager.changesObserver

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    Item {
        id: orbit
        objectName: "setupOrbit"
        anchors.centerIn: parent
        width: Math.min(page.width, page.height) * 0.46
        height: width

        Icon {
            anchors.centerIn: parent
            width: parent.width * 0.4
            height: width
            name: "ios-bluetooth"
            color: Theme.color.primary
        }

        Repeater {
            model: 3
            Rectangle {
                required property int index
                readonly property real a: (page.turn + index / 3) * 2 * Math.PI
                width: Theme.dp(12) - index * Theme.dp(2)
                height: width
                radius: width / 2
                color: index === 0 ? Theme.color.primary : Theme.color.primaryDim
                opacity: 1 - index * 0.25
                x: orbit.width / 2 + Math.cos(a) * orbit.width / 2 - width / 2
                y: orbit.height / 2 + Math.sin(a) * orbit.height / 2 - height / 2
            }
        }
    }

    NumberAnimation {
        id: spin
        target: page
        property: "turn"
        from: 0
        to: 1
        duration: Setup.connecting.orbitMs
        loops: Animation.Infinite
        running: page.animating
        easing.type: Easing.Linear
        onFinished: page.played = true
        onRunningChanged: if (!running) page.turn = 0
    }

    // the animation only counts while it is seen; with it stopped (Reduce animations, a dark display) a first
    // turn is as long a wait as the stock one, so the page counts it by a single shot
    Timer {
        id: firstTurn
        interval: Setup.connecting.orbitMs
        running: page.active && !page.played
        onTriggered: page.played = true
    }
}
