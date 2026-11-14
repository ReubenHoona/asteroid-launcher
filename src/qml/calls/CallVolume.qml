/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * More > Volume (calls-09, calls-11): a screen with a small round "+" 4.75 %
 * from the top, the word "Volume" in the middle, a small round "-" 4.75 %
 * from the bottom and the crown arc (fragment_incall_volume_control.xml;
 * the buttons are WearCircularButtons of size small = Theme.size.iconButtonSmall).
 * The crown changes the volume as in the call screen (IncomingCall's
 * WheelHandler is on while this is open); a swipe right closes it.
 */
Item {
    id: dialog
    objectName: "callVolume"
    anchors.fill: parent

    // 0..1; -1 not known (the arc stays empty)
    property real level: -1
    // One step of the volume, -1 or +1
    signal step(int delta)
    signal closeRequested()

    readonly property real edgeFraction: 0.0475
    readonly property alias arc: edgeArc
    readonly property alias upButton: up
    readonly property alias downButton: down

    BackSwipeArea {
        id: swipe
        anchors.fill: parent
        onFinished: {
            var go = committed
            reset()
            if (go)
                dialog.closeRequested()
        }

        Item {
            width: parent.width
            height: parent.height
            x: swipe.value

            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }

            IconButton {
                id: up
                objectName: "volumeUp"
                size: Theme.size.iconButtonSmall
                variant: "tonal"
                iconName: "ios-volume-up"
                anchors.horizontalCenter: parent.horizontalCenter
                y: dialog.edgeFraction * dialog.height
                //% "Increase volume"
                Accessible.name: qsTrId("id-call-volume-up-a11y") + localeManager.changesObserver
                onClicked: dialog.step(1)
            }

            Label {
                objectName: "volumeLabel"
                anchors.centerIn: parent
                role: "labelMedium"
                //% "Volume"
                text: qsTrId("id-call-volume") + localeManager.changesObserver
            }

            IconButton {
                id: down
                objectName: "volumeDown"
                size: Theme.size.iconButtonSmall
                variant: "tonal"
                iconName: "ios-volume-down"
                anchors.horizontalCenter: parent.horizontalCenter
                y: (1 - dialog.edgeFraction) * dialog.height - height
                //% "Decrease volume"
                Accessible.name: qsTrId("id-call-volume-down-a11y") + localeManager.changesObserver
                onClicked: dialog.step(-1)
            }

            CallVolumeArc {
                id: edgeArc
                level: Math.max(0, dialog.level)
                shown: true
            }
        }
    }
}
