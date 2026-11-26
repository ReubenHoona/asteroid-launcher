// SPDX-FileCopyrightText: 2023 Timo Könnecke <github.com/moWerk>
// SPDX-License-Identifier: LGPL-2.1-or-later

import Qt5Compat.GraphicalEffects
import QtQuick

Item {
    anchors.fill: parent

    Item {
        id: root

        anchors.centerIn: parent
        height: Math.min(parent.width, parent.height)
        width: height

        Item {
            id: watchfaceRoot

            anchors.centerIn: root
            width: root.width
            height: width
            layer.enabled: true

            Text {
                id: hourDisplay

                renderType: Text.NativeRendering
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                text: use12H.value ? wallClock.time.toLocaleString(Qt.locale(), "h ap").split(" ")[0] : wallClock.time.toLocaleString(Qt.locale(), "HH")

                anchors {
                    centerIn: watchfaceRoot
                    verticalCenterOffset: -watchfaceRoot.height * 0.218
                }

                font {
                    pixelSize: watchfaceRoot.height * 0.4
                    letterSpacing: watchfaceRoot.height * 0.006
                    family: "Outfit"
                    weight: Font.Medium
                }

            }

            Text {
                id: apDisplay

                renderType: Text.NativeRendering
                visible: use12H.value
                color: "#ddffffff"
                text: wallClock.time.toLocaleString(Qt.locale(), "ap").toUpperCase()

                anchors {
                    left: hourDisplay.right
                    leftMargin: watchfaceRoot.height * 0.01
                    bottom: watchfaceRoot.verticalCenter
                    bottomMargin: watchfaceRoot.height * 0.22
                }

                font {
                    pixelSize: watchfaceRoot.height * 0.076
                    family: "Outfit"
                    letterSpacing: watchfaceRoot.height * 0.006
                }

            }

            Text {
                id: monthDisplay

                anchors.centerIn: watchfaceRoot
                renderType: Text.NativeRendering
                color: "#ddffffff"
                horizontalAlignment: Text.AlignHCenter
                text: wallClock.time.toLocaleString(Qt.locale(), "MMM dd").replace(".", "").toUpperCase()

                font {
                    pixelSize: watchfaceRoot.height * 0.1
                    letterSpacing: watchfaceRoot.height * 0.006
                    family: "Outfit"
                    weight: Font.Light
                }

            }

            Text {
                id: minuteDisplay

                renderType: Text.NativeRendering
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                text: wallClock.time.toLocaleString(Qt.locale(), "mm")

                anchors {
                    centerIn: watchfaceRoot
                    verticalCenterOffset: watchfaceRoot.height * 0.21
                }

                font {
                    pixelSize: watchfaceRoot.height * 0.4
                    letterSpacing: watchfaceRoot.height * 0.006
                    family: "Outfit"
                    weight: Font.Light
                }

            }

            layer.effect: DropShadow {
                transparentBorder: true
                horizontalOffset: watchfaceRoot.height * 0.01
                verticalOffset: watchfaceRoot.height * 0.01
                radius: watchfaceRoot.height * 0.018
                samples: 9
                color: "#99000000"
            }

        }

    }

}
