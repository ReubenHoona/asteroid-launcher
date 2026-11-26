// SPDX-FileCopyrightText: 2022 Timo Könnecke <github.com/moWerk>
// SPDX-FileCopyrightText: 2022 Darrel Griét <dgriet@gmail.com>
// SPDX-FileCopyrightText: 2022 Ed Beroset <github.com/beroset>
// SPDX-FileCopyrightText: 2016 Florent Revest <revestflo@gmail.com>
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import Qt5Compat.GraphicalEffects
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
                color: Qt.rgba(0, 0, 0, .80)
                horizontalOffset: root.height * .00625
                verticalOffset: root.height * .00625
                radius: root.height * .0152
                samples: 12
            }

            Text {
                id: hourText
                // the sensor hub draws these digits in always-on (HubOffload)
                objectName: "eosHubHour"

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                    horizontalCenterOffset: parent.height * .003
                    verticalCenterOffset: -parent.height * .212
                }
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .39
                    family: "Roboto"
                    weight: Font.Medium
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

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: parent.height * .19
                }
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .38
                    family: "Roboto"
                    weight: Font.Light
                }
                text: Qt.formatTime(wallClock.time, "mm")
            }

            Text {
                id: dateText

                x: parent.width * .175
                anchors {
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: -parent.height * .002
                }
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .09
                    family: "Raleway"
                    weight: Font.Medium
                }
                text: Qt.formatDate(wallClock.time, "dd")
            }

            Text {
                id: monthText

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: parent.height * .006
                }
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .07
                    family: "Raleway"
                    weight: Font.Normal
                }
                text: Qt.formatDate(wallClock.time, "MMMM").toUpperCase()
            }

            Text {
                id: amPmText

                x: parent.width * .83 - width
                anchors {
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: parent.height * .006
                }
                visible: use12H.value
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .072
                    family: "Raleway"
                    weight: Font.Bold
                }
                text: wallClock.time.toLocaleString(Qt.locale("en_EN"), "AP")
            }

            Text {
                id: secondText

                x: parent.width * .81 - width
                anchors {
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: -parent.height * .002
                }
                visible: !use12H.value && !displayAmbient
                color: "white"
                renderType: Text.NativeRendering
                font {
                    pixelSize: parent.height * .09
                    family: "Roboto"
                    weight: Font.Medium
                }
                text: Qt.formatTime(wallClock.time, "ss")
            }

            // Complication slots, a line above the hour and one under the
            // minutes (the launcher draws the chosen data in them, and only
            // the date in always-on: ComplicationView.qml)
            Item {
                objectName: "eosComplication"
                property string slotId: "top"
                property string shape: "text"
                property string defaultSource: "battery"
                property color tint: "white"
                property string fontFamily: "Roboto"
                x: parent.width * .3
                y: parent.height * .057
                width: parent.width * .4
                height: parent.height * .073
            }
            Item {
                objectName: "eosComplication"
                property string slotId: "bottom"
                property string shape: "text"
                property string defaultSource: "steps"
                property color tint: "white"
                property string fontFamily: "Roboto"
                x: parent.width * .27
                y: parent.height * .844
                width: parent.width * .46
                height: parent.height * .073
            }
        }
    }
}
