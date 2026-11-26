// SPDX-FileCopyrightText: 2022 Timo Könnecke <github.com/moWerk>
// SPDX-FileCopyrightText: 2022 Darrel Griét <dgriet@gmail.com>
// SPDX-FileCopyrightText: 2022 Ed Beroset <github.com/beroset>
// SPDX-FileCopyrightText: 2016 Florent Revest <revestflo@gmail.com>
// SPDX-License-Identifier: BSD-3-Clause

import Qt5Compat.GraphicalEffects
import QtQuick
import org.asteroid.controls
import org.asteroid.utils

Item {
    anchors.fill: parent

    Item {
        id: root

        anchors.centerIn: parent
        height: Math.min(parent.width, parent.height)
        width: height

        Item {
            id: watchfaceRoot

            anchors.centerIn: parent
            width: parent.width
            height: width
            layer.enabled: true
            layer.effect: DropShadow {
                horizontalOffset: root.height * .0062
                verticalOffset: root.height * .0062
                radius: root.height * .0166
                samples: 12
                color: Qt.rgba(0, 0, 0, .84)
            }
            

            Text {
                id: dowText

                x: parent.width * .373 - width / 2
                y: parent.height * .324 - height / 2
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .051
                    family: "Xolonium"
                }
                text: Qt.formatDate(wallClock.time, "dddd").toUpperCase()
            }

            Text {
                id: hourText
                // the sensor hub draws these digits in always-on (HubOffload)
                objectName: "eosHubHour"

                x: parent.width * .625 - width
                y: parent.height * .61 - height * .75
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .36
                    family: "Xolonium"
                }
                text: {
                    var h = wallClock.time.getHours()
                    if (use12H.value) { h = h % 12; if (h === 0) h = 12 }
                    return (h < 10 && !use12H.value ? "0" : "") + h
                }
            }

            Text {
                id: minuteText
                objectName: "eosHubMinute"

                x: parent.width * .64
                y: parent.height * .611 - height * .75
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .17
                    family: "Xolonium"
                }
                text: Qt.formatTime(wallClock.time, "mm")
            }

            Text {
                id: amPmText

                x: parent.width * .645
                y: parent.height * .465 - height * .75
                visible: use12H.value
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .057
                    family: "Xolonium"
                }
                text: wallClock.time.toLocaleString(Qt.locale("en_EN"), "AP")
            }

            Text {
                id: dateText

                x: parent.width * .626 - width / 2
                y: parent.height * .675 - height / 2
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .051
                    family: "Xolonium"
                }
                text: Qt.formatDate(wallClock.time, "dd MMMM").toUpperCase()
            }

            // Complication slots, a line above and one under the time (the
            // launcher draws the chosen data in them, and only the date in
            // always-on: ComplicationView.qml)
            Item {
                objectName: "eosComplication"
                property string slotId: "top"
                property string shape: "text"
                property string defaultSource: "battery"
                property color tint: "white"
                property string fontFamily: "Xolonium"
                x: parent.width * .3
                y: parent.height * .14
                width: parent.width * .4
                height: parent.height * .07
            }
            Item {
                objectName: "eosComplication"
                property string slotId: "bottom"
                property string shape: "text"
                property string defaultSource: "steps"
                property color tint: "white"
                property string fontFamily: "Xolonium"
                x: parent.width * .3
                y: parent.height * .76
                width: parent.width * .4
                height: parent.height * .07
            }
        }

        Component.onCompleted: {
            burnInProtectionManager.widthOffset = Qt.binding(function() { return width * .2 })
            burnInProtectionManager.heightOffset = Qt.binding(function() { return height * .2 })
        }
    }
}
