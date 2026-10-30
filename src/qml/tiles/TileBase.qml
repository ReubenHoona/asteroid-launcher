/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import org.asteroid.utils

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
    // drawn small as a picture of itself (the tiles editor): no curved time
    property bool preview: false
    default property alias content: body.data
    readonly property alias body: body

    signal chipClicked()
    signal clicked()

    /*
     * The page dots under the tiles (MainScreen's ArcPageIndicator: the watch
     * face and every tile, along the bottom of the round screen): stock keeps
     * the indicator at the bottom edge under the tile's primary chip, never
     * over it. The chip sits above the dots under it, for as many dots as
     * there are (the same geometry as ArcPageIndicator: 6 dp dots 4 dp apart,
     * 6 dp from the edge), 2 dp clear; at least 6 % from the bottom as before.
     */
    readonly property int pageDots: typeof desktop !== "undefined" && desktop && desktop.tileCount > 0
                                    ? desktop.tileCount + 1 : 0
    readonly property real chipBottomMargin: {
        var base = Math.round(height * 0.06)
        if (pageDots <= 0 || width <= 0 || height <= 0)
            return base
        var s = Math.min(width, height), dp = s / 192, dot = 6 * dp, spacing = 4 * dp
        var half = Math.round(width * 0.5) / 2 + dot / 2
        var top = height
        if (!DeviceSpecs.hasRoundScreen) {
            top = height - 6 * dp - dot
        } else {
            var r = s / 2 - 6 * dp - dot / 2, step = (dot + spacing) / r
            for (var i = 0; i < pageDots; i++) {
                var a = (i - (pageDots - 1) / 2) * step
                var x = r * Math.sin(a)
                if (Math.abs(x) < half)
                    top = Math.min(top, height / 2 + r * Math.cos(a) - dot / 2)
            }
        }
        return Math.max(base, Math.ceil(height - top + 2 * dp))
    }

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

    TimeText { visible: !tile.preview }

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
        objectName: "tileChip"
        visible: tile.chipText !== "" || tile.chipIcon !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: tile.chipBottomMargin
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
