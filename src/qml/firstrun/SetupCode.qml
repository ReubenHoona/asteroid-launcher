/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "setup.js" as Setup

/* The pairing code screen of the setup (setup-wizard-09), as stock's ConfirmComposableScreen: a black
 * screen, "Secure" (or "Legacy" for a PIN) in the title style on one line with its top at 10 % of the
 * height, the six digits in the small numeral style (30 sp, weight 600) with 11 dp of letter spacing,
 * centred, and a looping animation around them. There are no buttons: the watch has answered already, the
 * phone's screen shows the same code to compare.
 *
 * Power (M1): the loop (1.67 s) runs only while the page is shown with the display on. */
Item {
    id: page
    objectName: "setupCode"

    // "secure" or "legacy"
    property string kind: "secure"
    property string code: ""
    property bool displayOn: true
    property bool active: visible
    readonly property bool animating: displayOn && active && !Motion.reduceMotion
    readonly property alias title: title
    readonly property alias codeLabel: codeLabel
    readonly property alias ring: ring
    // the loop's turn, 0 .. 1
    property real turn: 0

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    Label {
        id: title
        objectName: "setupCodeTitle"
        x: (page.width - width) / 2
        y: Math.round(page.height * Setup.code.top)
        width: page.width * 0.72
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        role: "titleMedium"
        color: Theme.color.primary
        text: page.kind === "legacy"
              //% "Legacy"
              ? qsTrId("id-setup-code-legacy") + localeManager.changesObserver
              //% "Secure"
              : qsTrId("id-setup-code-secure") + localeManager.changesObserver
    }

    Label {
        id: codeLabel
        objectName: "setupCodeDigits"
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        role: "numeralSmall"
        color: Theme.color.onBackground
        font.letterSpacing: Theme.dp(Setup.code.spacingDp)
        text: page.code
        Accessible.name: text.split("").join(" ")
    }

    // the loop: an arc that goes round the code
    Item {
        id: ring
        objectName: "setupCodeRing"
        anchors.centerIn: parent
        width: Math.min(page.width, page.height) * 0.94
        height: width
        rotation: page.turn * 360
        ProgressArc {
            anchors.fill: parent
            strokeWidth: Theme.dp(4)
            color: Theme.color.primary
            startAngle: 270
            sweepAngle: 100
            opacity: 0.9
        }
        ProgressArc {
            anchors.fill: parent
            strokeWidth: Theme.dp(4)
            color: Theme.color.primaryDim
            startAngle: 90
            sweepAngle: 40
            opacity: 0.5
        }
    }

    NumberAnimation {
        target: page
        property: "turn"
        from: 0
        to: 1
        duration: Setup.code.loopMs
        loops: Animation.Infinite
        running: page.animating
        easing.type: Easing.Linear
    }
}
