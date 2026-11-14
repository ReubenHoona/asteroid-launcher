/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "lock.js" as Lock

/*
 * The boot lock screen (W3-launcher-a11y-security, accessibility-lock-security-10):
 * after a restart with a lock set, until the first unlock, stock draws
 * BootupLockscreenContainer (bootup_lock_screen_v2.xml) instead of the face:
 * the curved time, a centred 80 dp filled lock badge with a 2 px outline and
 * a 36 dp lock icon, "Unlock" under it (title2 in the primary colour, 4 dp
 * gap, 146 dp wide). It fades out in 300 ms when the watch is unlocked; a tap
 * opens the bouncer (tapped()).
 */
Item {
    id: boot
    objectName: "bootupLock"

    // up while the watch is locked since the restart
    property bool shown: false
    signal tapped()

    readonly property real badgeSize: Theme.dp(Lock.BOOT.badgeDp)
    readonly property alias badge: badgeRect
    readonly property alias title: titleLabel
    readonly property alias fade: fadeAnim

    opacity: 0
    visible: opacity > 0

    onShownChanged: {
        fadeAnim.stop()
        if (shown) {
            opacity = 1
        } else {
            fadeAnim.to = 0
            fadeAnim.start()
        }
    }
    Component.onCompleted: opacity = shown ? 1 : 0

    NumberAnimation {
        id: fadeAnim
        target: boot
        property: "opacity"
        duration: Lock.BOOT.fadeMs
        easing.type: Easing.Linear
    }

    // it covers the face: the same black as the lock's own backdrop
    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    TimeText { }

    Column {
        id: stack
        anchors.centerIn: parent
        spacing: Theme.dp(Lock.BOOT.gapDp)

        Rectangle {
            id: badgeRect
            objectName: "bootupBadge"
            width: boot.badgeSize
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.color.primaryContainer
            border.width: Lock.BOOT.outlinePx
            border.color: Theme.color.primary
            Icon {
                objectName: "bootupIcon"
                anchors.centerIn: parent
                width: Theme.dp(Lock.BOOT.iconDp)
                height: width
                name: "ms-lock"
                color: Theme.color.onPrimaryContainer
            }
            Accessible.role: Accessible.Graphic
            //% "Lock icon"
            Accessible.name: qsTrId("id-lock-icon")
        }

        Label {
            id: titleLabel
            objectName: "bootupTitle"
            width: Theme.dp(Lock.BOOT.titleWidthDp)
            horizontalAlignment: Text.AlignHCenter
            role: "titleMedium"
            color: Theme.color.primary
            //% "Unlock"
            text: qsTrId("id-lock-unlock")
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: boot.shown
        onClicked: boot.tapped()
    }
}
