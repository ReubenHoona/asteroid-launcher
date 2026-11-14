/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The wait after too many tries (W3-launcher-a11y-security,
 * accessibility-lock-security-05; stock UnlockAttemptDialog): "Too many
 * attempts", the live countdown "Try again in %1 sec" / "%1 min %2 sec" /
 * "%1 hr %2 min" / "Try again in 24 hr", and one round button. `parts` is
 * lock.js waitParts(ms) of the time left; the owner refreshes it once a
 * second while this is up and the display is on, and closes the dialog when
 * the wait is over.
 */
Item {
    id: dialog
    objectName: "lockoutDialog"

    property bool shown: false
    // lock.js waitParts(): { kind, a, b }
    property var parts: ({ kind: "seconds", a: 0, b: 0 })
    readonly property alias message: countdown
    readonly property alias heading: titleLabel
    readonly property alias button: okButton

    signal dismissed()

    visible: shown
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 100 } }

    function two(n) { return (n < 10 ? "0" : "") + n }

    //% "Try again in %1 sec"
    readonly property string secondsText: qsTrId("id-lock-try-seconds")
    //% "Try again in %1 min %2 sec"
    readonly property string minutesText: qsTrId("id-lock-try-minutes")
    //% "Try again in %1 hr %2 min"
    readonly property string hoursText: qsTrId("id-lock-try-hours")
    //% "Try again in 24 hr"
    readonly property string dayText: qsTrId("id-lock-try-day")
    readonly property string countdownText: parts.kind === "day" ? dayText
        : parts.kind === "hours" ? hoursText.arg(parts.a).arg(two(parts.b))
        : parts.kind === "minutes" ? minutesText.arg(parts.a).arg(two(parts.b))
        : secondsText.arg(parts.a)

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.92
    }

    Label {
        id: titleLabel
        objectName: "lockoutTitle"
        role: "titleMedium"
        width: parent.width * 0.76
        x: (parent.width - width) / 2
        y: parent.height * 0.20
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Theme.color.onSurface
        //% "Too many attempts"
        text: qsTrId("id-lock-too-many")
    }
    Label {
        id: countdown
        objectName: "lockoutCountdown"
        role: "bodyMedium"
        width: parent.width * 0.76
        x: (parent.width - width) / 2
        y: titleLabel.y + titleLabel.height + Theme.dp(8)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Theme.color.onSurfaceVariant
        text: dialog.countdownText
    }

    // the one round button
    Rectangle {
        id: okButton
        objectName: "lockoutButton"
        width: Theme.dp(52)
        height: width
        radius: width / 2
        color: Theme.color.primaryContainer
        x: (parent.width - width) / 2
        y: parent.height - height - parent.height * 0.10
        Icon {
            anchors.centerIn: parent
            width: Theme.dp(24)
            height: width
            name: "ms-check"
            color: Theme.color.onPrimaryContainer
        }
        MouseArea {
            anchors.fill: parent
            onClicked: dialog.dismissed()
        }
        Accessible.role: Accessible.Button
        //% "OK"
        Accessible.name: qsTrId("id-lock-ok")
        Accessible.onPressAction: dialog.dismissed()
    }
}
