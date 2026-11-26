// SPDX-FileCopyrightText: 2023 Timo Könnecke <github.com/moWerk>
// SPDX-FileCopyrightText: 2022 Darrel Griét <dgriet@gmail.com>
// SPDX-FileCopyrightText: 2022 Ed Beroset <github.com/beroset>
// SPDX-FileCopyrightText: 2016 Sylvia van Os <iamsylvie@openmailbox.org>
// SPDX-FileCopyrightText: 2015 Florent Revest <revestflo@gmail.com>
// SPDX-FileCopyrightText: 2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
// SPDX-License-Identifier: BSD-3-Clause

import Qt5Compat.GraphicalEffects
import QtQuick

Item {
    property string imgPath: "../watchfaces-img/funky-town-words-"

    anchors.fill: parent

    Item {
        anchors.centerIn: parent
        height: Math.min(parent.width, parent.height)
        width: height
        Component.onCompleted: {
            burnInProtectionManager.leftOffset = Qt.binding(function() {
                return width * 0.4;
            });
            burnInProtectionManager.rightOffset = Qt.binding(function() {
                return width * 0.05;
            });
            burnInProtectionManager.topOffset = Qt.binding(function() {
                return height * 0.4;
            });
            burnInProtectionManager.bottomOffset = Qt.binding(function() {
                return height * 0.05;
            });
        }

        Image {
            anchors.centerIn: parent
            source: imgPath + wallClock.time.toLocaleString(Qt.locale(), "hh am").slice(0, 2) + (displayAmbient ? "-bw.svg" : ".svg")
            sourceSize.width: parent.width
            sourceSize.height: parent.height
            width: parent.width
            height: parent.height
        }

        Image {
            anchors.centerIn: parent
            source: imgPath + wallClock.time.toLocaleString(Qt.locale("en_EN"), "ap").toLowerCase().slice(0, 2) + ".svg"
            visible: use12H.value
            sourceSize.width: parent.width
            sourceSize.height: parent.height
            width: parent.width
            height: parent.height
        }

        Text {
            id: minuteDisplay

            renderType: Text.NativeRendering
            color: displayAmbient ? "#000" : "#fff"
            text: wallClock.time.toLocaleString(Qt.locale(), "mm")

            anchors {
                bottom: parent.bottom
                bottomMargin: parent.height * 0.15
                horizontalCenter: parent.horizontalCenter
                horizontalCenterOffset: parent.width * 0.2
            }

            font {
                pixelSize: parent.height * 0.22
                family: "Source Sans Pro"
                weight: Font.Light
            }

            Behavior on text {
                enabled: !displayAmbient

                SequentialAnimation {
                    NumberAnimation {
                        target: minuteDisplay
                        property: "opacity"
                        to: 0
                    }

                    PropertyAction {
                    }

                    NumberAnimation {
                        target: minuteDisplay
                        property: "opacity"
                        to: 1
                    }

                }

            }

        }

    }

}
