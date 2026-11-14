/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import org.asteroid.utils
import org.nemomobile.lipstick
import "../pager.js" as Pager

/*
 * The frame of a tile, as Wear OS lays its tiles out (protolayout-material3
 * PrimaryLayout, "M3 primary layout"): black; at the top a 24 dp slot for
 * the tile's app icon, which the carousel draws (TilesIndicator: no time
 * on tiles), 3 dp from the top; under it the coloured title (titleSmall, 14 sp
 * on a 16 sp line, 14.5 % margins either side); the content in the middle
 * with 5.2 % side margins (PrimaryLayoutMargins MID, ehr.java:72-81; 3 %
 * with sideMarginFraction for MIN) and an optional edge button at the bottom
 * (46 dp tall, 3 dp from the edge, 52 % wide, primary / onPrimary). Without
 * an edge button the content ends 19.6 % of the height above the bottom, or,
 * with a bottom text (bottomLabel / bottomValue: 26 % side margins, 5.2 %
 * under it, 6 dp above it), above that. The title is white (onBackground),
 * never the tile's accent (tiles-individual-02, -04).
 *
 * Stock's tile has no catch-all click: each card or button is its own
 * clickable (TileCard, tiles-individual-32) and a tap on empty black does
 * nothing. backgroundTap keeps the old tap-anywhere clicked() and its ripple
 * for a tile that has not been moved to cards yet; a long press (400 ms, the
 * platform's long-press timeout) opens the tiles editor either way.
 *
 * "live" is true while the tile is on screen (the panels grid hides the
 * panels nobody sees). Tiles only read and show their data while live, so a
 * hidden tile never makes the home screen draw.
 */
Item {
    id: tile

    property string title: ""
    // content colour a tile may still use; the title is no longer in it
    property color accent: Theme.color.primary
    // stock draws the title in onBackground, white (TITLE_SMALL, cno.java:381-397)
    property color titleColor: Theme.color.onBackground
    readonly property bool live: visible
    // on screen and drawing: not in ambient, not behind an app. Tiles that
    // count (the timer) tick only while this holds
    readonly property bool awake: live && Lipstick.compositor.homeActive && !Lipstick.compositor.displayAmbient
    property string chipText: ""
    property string chipIcon: ""
    // the edge button's colours (stock filledButtonColors: primary / onPrimary;
    // a tile may take another container, e.g. the clock tiles' green)
    property color chipColor: Theme.color.primary
    property color chipContentColor: Theme.color.onPrimary
    // drawn small as a picture of itself (the tiles editor): no press, no ripple
    property bool preview: false
    // a tap on the tile that is no card or button is clicked() (the old
    // catch-all). Stock has none: a tile built of TileCards sets this false
    property bool backgroundTap: true
    // the content's side margins as a share of the width: 5.2 % (MID, with a
    // title) or 3 % (MIN, the running timer)
    property real sideMarginFraction: 0.052
    // the bottom text slot (the tiles of one value: Main goal, Heart rate...)
    property string bottomLabel: ""
    property string bottomValue: ""
    default property alias content: body.data
    readonly property alias body: body
    readonly property alias chip: chip
    readonly property alias titleItem: titleLabel
    readonly property alias bottomText: bottomSlot
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
    readonly property real bodySideMargin: width * sideMarginFraction
    readonly property real titleGap: Theme.dp(4)
    readonly property real edgeHeight: Theme.size.edgeButtonExtraSmall
    // 52 % wide for an icon (stock, tiles-individual-03). The W1 EdgeButton keeps its text 20 dp
    // from the screen edge, which leaves 38 px of text room at 200 px: a text button
    // ("Open", "Music") is 70 % wide, where "Open" has about 80 px, until the control's
    // content window is looked at again (NOTES: for the coordinator)
    readonly property real edgeWidth: width * (chipText !== "" ? 0.7 : 0.52)
    readonly property real edgeBodyGap: Theme.dp(4)
    // no edge button: the content ends 19.6 % above the bottom (ehr.java:72-81)
    readonly property real noBottomMargin: Math.round(height * 0.196)
    // a bottom text: 26 % sides, 5.2 % from the bottom, 6 dp under the content
    readonly property bool hasBottomText: bottomLabel !== "" || bottomValue !== ""
    readonly property real bottomTextSide: width * 0.26
    readonly property real bottomTextBottom: Math.round(height * 0.052)
    readonly property real bottomTextGap: Theme.dp(6)

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#000000"
    }

    // the tap feedback of the renderer's theme: the shared bounded ripple
    Ripple {
        radius: width / 2
        pressed: bodyArea.pressed && !tile.preview && tile.backgroundTap
        pressX: bodyArea.mouseX
        pressY: bodyArea.mouseY
    }

    MouseArea {
        id: bodyArea
        anchors.fill: parent
        pressAndHoldInterval: Pager.LONG_PRESS_MS
        onClicked: if (tile.backgroundTap) tile.clicked()
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
        // no title (stock's is optional: the idle Timer, the Assistant): no line, the content moves up
        height: text === "" ? 0 : Theme.type.titleSmall.lineHeight
        color: tile.titleColor
        maximumLineCount: 1
        role: "titleSmall"
    }

    Item {
        id: body
        anchors {
            top: titleLabel.bottom
            topMargin: tile.titleGap
            bottom: parent.bottom
            bottomMargin: chip.visible ? Theme.size.edgeButtonBottomGap + tile.edgeHeight + tile.edgeBodyGap
                                       : tile.hasBottomText ? tile.bottomTextBottom + bottomSlot.height + tile.bottomTextGap
                                                            : tile.noBottomMargin
            left: parent.left
            right: parent.right
            leftMargin: tile.bodySideMargin
            rightMargin: tile.bodySideMargin
        }
    }

    // the bottom text slot: label and value on one line, 26 % side margins
    Row {
        id: bottomSlot
        visible: tile.hasBottomText && !chip.visible
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: tile.bottomTextBottom
        width: Math.min(implicitWidth, tile.width - 2 * tile.bottomTextSide)
        height: visible ? implicitHeight : 0
        spacing: Theme.dp(4)
        Label {
            id: bottomLabelItem
            visible: text !== ""
            text: tile.bottomLabel
            role: "bodyMedium"
            color: Theme.color.onSurface
            maximumLineCount: 1
        }
        Label {
            id: bottomValueItem
            visible: text !== ""
            text: tile.bottomValue
            role: "titleSmall"
            color: Theme.color.onSurface
            maximumLineCount: 1
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
            tile.chipClicked()
        }
    }
}
