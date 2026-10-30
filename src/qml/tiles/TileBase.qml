/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The frame of a tile, as Wear OS lays its tiles out: black, the time on
 * the top arc, a coloured title, the content in the middle and an optional
 * chip at the bottom edge. A tap anywhere that is not a button is clicked()
 * (as a Wear OS tile's clickable: it opens the tile's app); a long press
 * opens the tiles editor.
 *
 * "live" is true while the tile is on screen (the panels grid hides the
 * panels nobody sees). Tiles only read and show their data while live, so a
 * hidden tile never makes the home screen draw.
 */
Item {
    id: tile

    property string title: ""
    property color accent: "#a8c7fa"
    readonly property bool live: visible
    property string chipText: ""
    property string chipIcon: ""
    default property alias content: body.data
    readonly property alias body: body

    signal chipClicked()
    signal clicked()

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#000000"
    }

    MouseArea {
        anchors.fill: parent
        pressAndHoldInterval: 500
        onClicked: tile.clicked()
        onPressAndHold: {
            Haptics.longPress()
            if (typeof desktop !== "undefined" && desktop.openTilesEditor)
                desktop.openTilesEditor()
        }
    }

    TimeText { }

    Label {
        id: titleLabel
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(tile.height * 0.15)
        width: Math.round(tile.width * 0.6)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: tile.title
        color: tile.accent
        // Wear OS title small, 14 sp
        font.pixelSize: Math.round(tile.height * 0.068)
        font.styleName: "SemiCondensed Medium"
    }

    Item {
        id: body
        anchors {
            top: titleLabel.bottom
            topMargin: Math.round(tile.height * 0.02)
            bottom: chip.visible ? chip.top : parent.bottom
            bottomMargin: Math.round(tile.height * (chip.visible ? 0.02 : 0.12))
            left: parent.left
            right: parent.right
            leftMargin: Math.round(tile.width * 0.1)
            rightMargin: Math.round(tile.width * 0.1)
        }
    }

    // Wear OS's edge button: a wide pill hugging the bottom of the screen
    MouseArea {
        id: chip
        visible: tile.chipText !== "" || tile.chipIcon !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(tile.height * 0.06)
        width: Math.round(tile.width * 0.5)
        height: Math.round(tile.height * 0.19)
        onClicked: {
            Haptics.click()
            tile.chipClicked()
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: tile.accent
            opacity: chip.pressed ? 0.75 : 1.0
        }

        Row {
            anchors.centerIn: parent
            spacing: Math.round(tile.width * 0.015)
            Icon {
                visible: tile.chipIcon !== ""
                name: tile.chipIcon
                color: "#000000"
                width: Math.round(chip.height * 0.42)
                height: width
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                visible: tile.chipText !== ""
                text: tile.chipText
                color: "#000000"
                font.pixelSize: Math.round(tile.height * 0.06)
                font.styleName: "SemiCondensed Medium"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
