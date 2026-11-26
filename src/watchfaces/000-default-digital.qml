// SPDX-FileCopyrightText: 2023 Timo Könnecke <github.com/moWerk>
// SPDX-FileCopyrightText: 2022 Darrel Griët <dgriet@gmail.com>
// SPDX-FileCopyrightText: 2022 Ed Beroset <github.com/beroset>
// SPDX-FileCopyrightText: 2017 Florent Revest <revestflo@gmail.com>
// SPDX-License-Identifier: BSD-3-Clause

import Qt5Compat.GraphicalEffects
import QtQuick

Item {
    anchors.fill: parent

    Item {
        id: root

        // Time values, declarative bindings on the launcher wallClock.
        property int hour24: wallClock.time.getHours()
        property int displayHour: use12H.value ? (hour24 % 12 === 0 ? 12 : hour24 % 12) : hour24
        property int minutes: wallClock.time.getMinutes()
        property string apText: wallClock.time.toLocaleString(Qt.locale("en_EN"), "AP")
        property string dateText: wallClock.time.toLocaleString(Qt.locale(), "d MMM")

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
                color: "black"
                horizontalOffset: 0
                verticalOffset: 0
                radius: root.height * .0235
                samples: 17
            }

            Text {
                id: hourLabel
                // the sensor hub draws these digits in always-on (HubOffload)
                objectName: "eosHubHour"

                anchors {
                    centerIn: parent
                    horizontalCenterOffset: parent.width * (.379 - .5)
                    verticalCenterOffset: parent.height * (.487 - .5)
                }
                color: "white"
                renderType: Text.NativeRendering
                font {
                    family: "Roboto"
                    pixelSize: parent.height * .36
                    weight: Font.Medium
                }
                text: (root.displayHour < 10 && !use12H.value ? "0" : "") + root.displayHour
            }

            Text {
                id: minuteLabel
                objectName: "eosHubMinute"

                anchors {
                    centerIn: parent
                    horizontalCenterOffset: parent.width * (.717 - .5)
                    verticalCenterOffset: parent.height * (.45 - .5)
                }
                color: "white"
                renderType: Text.NativeRendering
                font {
                    family: "Roboto"
                    pixelSize: parent.height * .18
                    weight: Font.Light
                }
                text: root.minutes < 10 ? "0" + root.minutes : "" + root.minutes
            }

            Text {
                id: apLabel

                anchors {
                    centerIn: parent
                    horizontalCenterOffset: parent.width * (.898 - .5)
                    verticalCenterOffset: parent.height * (.368 - .5)
                }
                visible: use12H.value
                color: "white"
                renderType: Text.NativeRendering
                font {
                    family: "Raleway"
                    pixelSize: parent.height * .065
                    weight: Font.Light
                }
                text: root.apText
            }

            Text {
                id: dateLabel

                anchors {
                    centerIn: parent
                    horizontalCenterOffset: parent.width * (.719 - .5)
                    verticalCenterOffset: parent.height * (.587 - .5)
                }
                color: "white"
                renderType: Text.NativeRendering
                font {
                    family: "Raleway"
                    pixelSize: parent.height * .076
                    weight: Font.Light
                }
                text: root.dateText
            }

            // Complication slots: a line above the time and two round ones
            // under it, as the stock digital faces (the launcher draws the
            // chosen data in them, and only the date in always-on:
            // ComplicationView.qml)
            Item {
                objectName: "eosComplication"
                property string slotId: "top"
                property string shape: "text"
                property string defaultSource: "battery"
                property color tint: "white"
                property string fontFamily: "Raleway"
                x: parent.width * .2
                y: parent.height * .19
                width: parent.width * .6
                height: parent.height * .075
            }
            Item {
                objectName: "eosComplication"
                property string slotId: "left"
                property string shape: "circle"
                property string defaultSource: "steps"
                property color tint: "white"
                property string fontFamily: "Raleway"
                width: parent.width * .17
                height: width
                x: parent.width * .39 - width / 2
                y: parent.height * .765 - height / 2
            }
            Item {
                objectName: "eosComplication"
                property string slotId: "right"
                property string shape: "circle"
                property string defaultSource: "heartrate"
                property color tint: "white"
                property string fontFamily: "Raleway"
                width: parent.width * .17
                height: width
                x: parent.width * .61 - width / 2
                y: parent.height * .765 - height / 2
            }
        }

        Component.onCompleted: {
            burnInProtectionManager.widthOffset = Qt.binding(function() { return root.width * .32 })
            burnInProtectionManager.heightOffset = Qt.binding(function() { return root.height * .7 })
        }
    }
}
