/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "../desktop.js" as Desktop

/*
 * Bedtime mode coming on while the screen is on, as stock (the Mode
 * Manager's BedtimeModeController): "Starting Bedtime mode…" over
 * everything for two seconds, then the watch face; the launcher's modes
 * engine turns the screen off right after (modes.h, BedtimeScreenOffMs).
 */
Item {
    id: screen
    anchors.fill: parent
    visible: opacity > 0
    opacity: 0

    Connections {
        target: typeof modes !== "undefined" ? modes : null
        function onBedtimeStarting() {
            fadeOut.stop()
            screen.opacity = 1
            hold.restart()
        }
    }
    Timer {
        id: hold
        interval: 2000
        onTriggered: {
            if (Desktop.desktop && Desktop.desktop.showWatchface)
                Desktop.desktop.showWatchface()
            fadeOut.start()
        }
    }
    NumberAnimation { id: fadeOut; target: screen; property: "opacity"; to: 0; duration: 300 }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }
    MouseArea { anchors.fill: parent }
    Column {
        anchors.centerIn: parent
        width: Dims.w(76)
        spacing: Dims.h(4)
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Dims.l(18)
            height: width
            name: "ios-moon"
            color: Theme.color.primary
        }
        Label {
            objectName: "bedtimeStarting"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            clip: false
            //% "Starting Bedtime mode…"
            text: qsTrId("id-bedtime-starting")
            font.pixelSize: Dims.l(7.4)
            font.styleName: "SemiCondensed Medium"
        }
    }
}
