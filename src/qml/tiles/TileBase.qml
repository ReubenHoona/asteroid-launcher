/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import org.asteroid.utils
import "../pager.js" as Pager

/*
 * The frame of a tile, as Wear OS lays its tiles out (protolayout-material3
 * PrimaryLayout, "M3 primary layout"): black; at the top a 24 dp slot for
 * the tile's app icon, which the carousel draws (TilesIndicator: no time
 * on tiles), 3 dp from the top; under it the coloured title (titleSmall, 14 sp
 * on a 16 sp line, 14.5 % margins either side); the content in the middle
 * with 7.1 % side margins; and an optional edge button at the bottom (46 dp
 * tall, 3 dp from the edge, 52 % wide, primary / onPrimary). A tap anywhere
 * that is not a button is clicked() (as a Wear OS tile's clickable: it opens
 * the tile's app) and shows the ripple; a long press (400 ms, the platform's
 * long-press timeout) opens the tiles editor.
 *
 * "live" is true while the tile is on screen (the panels grid hides the
 * panels nobody sees). Tiles only read and show their data while live, so a
 * hidden tile never makes the home screen draw.
 */
Item {
    id: tile

    property string title: ""
    property color accent: Theme.color.primary
    readonly property bool live: visible
    property string chipText: ""
    property string chipIcon: ""
    // the edge button's colours (stock filledButtonColors: primary / onPrimary;
    // a tile may take another container, e.g. the clock tiles' green)
    property color chipColor: Theme.color.primary
    property color chipContentColor: Theme.color.onPrimary
    // drawn small as a picture of itself (the tiles editor): no press, no ripple
    property bool preview: false
    default property alias content: body.data
    readonly property alias body: body
    readonly property alias chip: chip
    readonly property alias titleItem: titleLabel
    // the tap area, for the long press timeout and the tests
    readonly property alias tapArea: bodyArea
    readonly property bool pressed: bodyArea.pressed
    // MainScreen.launchApp gives a launch from a tile no origin of its own
    readonly property bool tileFrame: true

    signal chipClicked()
    signal clicked()

    // the layout, in dp (PrimaryLayout.kt HEADER_*, PrimaryLayoutMargins DEFAULT,
    // EdgeButton.kt: EDGE_BUTTON_HEIGHT_DP 46, BOTTOM_MARGIN_DP 3,
    // HORIZONTAL_MARGIN_PERCENT_SMALL 24; the slot above is 3 + 24 + 2 dp)
    readonly property real titleTop: Theme.size.tileAppIconTop + Theme.size.tileAppIcon + Theme.dp(2)
    readonly property real titleSideMargin: width * 0.145
    readonly property real bodySideMargin: width * 0.071
    readonly property real titleGap: Theme.dp(4)
    readonly property real edgeHeight: Theme.size.edgeButtonExtraSmall
    readonly property real edgeWidth: width * 0.52
    readonly property real edgeBodyGap: Theme.dp(4)

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#000000"
    }

    // the tap feedback of the renderer's theme: the shared bounded ripple
    Ripple {
        radius: width / 2
        pressed: bodyArea.pressed && !tile.preview
        pressX: bodyArea.mouseX
        pressY: bodyArea.mouseY
    }

    MouseArea {
        id: bodyArea
        anchors.fill: parent
        pressAndHoldInterval: Pager.LONG_PRESS_MS
        onClicked: tile.clicked()
        onPressAndHold: {
            Haptics.longPress()
            if (typeof desktop !== "undefined" && desktop.openTilesEditor)
                desktop.openTilesEditor()
        }
    }

    Label {
        id: titleLabel
        x: tile.titleSideMargin
        y: tile.titleTop
        width: tile.width - 2 * tile.titleSideMargin
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: tile.title
        color: tile.accent
        role: "titleSmall"
    }

    Item {
        id: body
        anchors {
            top: titleLabel.bottom
            topMargin: tile.titleGap
            bottom: parent.bottom
            bottomMargin: chip.visible ? Theme.size.edgeButtonBottomGap + tile.edgeHeight + tile.edgeBodyGap
                                       : Math.round(tile.height * 0.12)
            left: parent.left
            right: parent.right
            leftMargin: tile.bodySideMargin
            rightMargin: tile.bodySideMargin
        }
    }

    // Wear OS's edge button: hugs the round edge under the content
    EdgeButton {
        id: chip
        objectName: "tileChip"
        visible: tile.chipText !== "" || tile.chipIcon !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        width: tile.edgeWidth
        preferredHeight: tile.edgeHeight
        text: tile.chipText
        iconName: tile.chipIcon
        containerColor: tile.chipColor
        contentColor: tile.chipContentColor
        onClicked: {
            Haptics.click()
            tile.chipClicked()
        }
    }
}
