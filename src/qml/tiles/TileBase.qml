/*
 * Copyright (C) 2026 eos
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
 * with a bottom text (two lines: bottomLabel, then bottomValue with its icon;
 * 26 % side margins, 5.2 % under it, 6 dp above it), above that. The title
 * is white (onBackground), never the tile's accent (tiles-individual-02, -04).
 *
 * "expressive": the Wear OS 6 look of the Clock and Contacts tiles (the
 * emulator's Timer S13, Next Alarm S14, Favorite contacts S14-c): no icon
 * slot and no title unless one is set (then titleMedium, 16 sp, its capitals
 * from 72 px), the content from 26 dp (52 px), no edge button and no bottom
 * text but a compact pill (pillText: 32 dp tall, 12 dp above the bottom, as
 * wide as its labelSmall label plus 12 dp each side and at least 52 dp,
 * 48 dp touch), 10 dp under the content. The app icon is not permanent over
 * it: it fades when the pager stops (m3Layout false). N61-26
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
    // the wall clock (ms since the epoch) a tile reads the time of day from: the alarm that rings
    // next, today's events, the sun (tests set a fixed one)
    property var clock: function () { return Date.now() }
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
    // an icon before the label (Daily heart rate: the heart, in its own colour) and the value's colour
    // (Main goal: the goal in green); W3-launcher-tiles-content-b
    property string bottomIcon: ""
    property color bottomIconColor: Theme.color.onSurface
    property color bottomValueColor: Theme.color.onSurface
    // the type roles of the bottom text: CP3A's label is 14 sp and its value 16 sp (label glyphs 14 dp and
    // value digits 12 dp tall in Fitbit's tile_primarygoal/heartrate/sleep_preview.xml; 21 and 24 px in
    // Weather's sun/uv_tile_preview.webp)
    property string bottomLabelRole: "titleSmall"
    property string bottomValueRole: "titleMedium"
    default property alias content: body.data
    readonly property alias body: body
    readonly property alias chip: chip
    readonly property alias titleItem: titleLabel
    readonly property alias bottomText: bottomSlot
    readonly property alias bottomIconItem: bottomIconItem
    readonly property alias bottomValueItem: bottomValueItem
    readonly property alias bottomLabelItem: bottomLabelItem
    // the tap area, for the long press timeout and the tests
    readonly property alias tapArea: bodyArea
    readonly property bool pressed: bodyArea.pressed
    // MainScreen.launchApp gives a launch from a tile no origin of its own
    readonly property bool tileFrame: true
    // the layout is an M3 primary layout: the app icon at the top stays on (TilesIndicator.permanent,
    // motion C8). CP3A: the M3_PL tag on the layout's root, which the renderer reports as "icon reserved"
    // (protolayout.renderer arp.java:19-26, auw.java:466-481), keeps sysui's icon at 1 (hxq.java:25-34,
    // jme.java:36-49). CP3A's own tiles all carry it (deskclock Timer and Alarm, cno.java:367-374;
    // contacts Favorites, aha.java:1366-1376; Fitbit, Calendar, Weather, Maps, Assistant), so true here;
    // a tile with a layout of its own sets false and its icon fades when the pager stops (Quick Add). The
    // emulator's expressive tiles show the icon only while the pager moves (M08): false for them
    property bool m3Layout: !expressive
    // the Wear OS 6 layout (see above) and its bottom pill
    property bool expressive: false
    property string pillText: ""
    property color pillColor: Theme.color.primary
    property color pillContentColor: Theme.color.onPrimary
    readonly property alias pill: pillButton

    signal chipClicked()
    signal pillClicked()
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
    readonly property bool hasBottomText: bottomLabel !== "" || bottomValue !== "" || bottomIcon !== ""
    readonly property real bottomTextSide: width * 0.26
    readonly property real bottomTextBottom: Math.round(height * 0.052)
    readonly property real bottomTextGap: Theme.dp(6)
    // the expressive layout, px at 384 (S13: circles from y 52, pill y 296-359; S14-c: the title's ink y 71-94,
    // which Noto Sans' capitals from 72 px draw at 70-94)
    readonly property real expressiveTop: Theme.dp(26)
    readonly property real expressiveTitleCap: Theme.dp(36)
    readonly property real pillHeight: Theme.dp(32)
    readonly property real pillBottom: Theme.dp(12)
    readonly property real pillBodyGap: Theme.dp(10)
    readonly property bool hasPill: expressive && pillText !== ""

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
        // expressive: titleMedium with its capitals from 72 px (S14-c 'Favorites' ink 71-94)
        y: tile.expressive ? tile.expressiveTitleCap - (baselineOffset + titleCap.tightBoundingRect.y) : tile.titleTop
        width: tile.width - 2 * tile.titleSideMargin
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: tile.title
        // no title (stock's is optional: the idle Timer, the Assistant): no line, the content moves up
        height: text === "" ? 0 : Theme.type[role].lineHeight
        color: tile.titleColor
        maximumLineCount: 1
        role: tile.expressive ? "titleMedium" : "titleSmall"
    }
    TextMetrics { id: titleCap; font: titleLabel.font; text: "H" }

    Item {
        id: body
        anchors {
            top: tile.expressive ? parent.top : titleLabel.bottom
            topMargin: !tile.expressive ? tile.titleGap
                       : tile.title === "" ? tile.expressiveTop : titleLabel.y + titleLabel.height + tile.titleGap
            bottom: parent.bottom
            bottomMargin: tile.expressive ? (tile.hasPill ? tile.pillBottom + tile.pillHeight + tile.pillBodyGap : tile.noBottomMargin)
                        : chip.visible ? Theme.size.edgeButtonBottomGap + tile.edgeHeight + tile.edgeBodyGap
                                       : tile.hasBottomText ? tile.bottomTextBottom + bottomSlot.height + tile.bottomTextGap
                                                            : tile.noBottomMargin
            left: parent.left
            right: parent.right
            leftMargin: tile.bodySideMargin
            rightMargin: tile.bodySideMargin
        }
    }

    // the bottom text slot, 26 % side margins: CP3A's two lines (the M3 layout's label over its bottom
    // slot, as in the Fitbit and Weather tile previews), the label and under it the value with its icon,
    // each line centred and no wider than the slot. The value stays whole and a label too long ends in an
    // ellipsis (so does a value that alone is wider than the slot). D60-21. An expressive tile has none
    Column {
        id: bottomSlot
        visible: tile.hasBottomText && !chip.visible && !tile.expressive
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: tile.bottomTextBottom
        width: tile.width - 2 * tile.bottomTextSide
        height: visible ? implicitHeight : 0
        Label {
            id: bottomLabelItem
            visible: text !== ""
            x: (bottomSlot.width - width) / 2
            width: Math.min(implicitWidth, bottomSlot.width)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: tile.bottomLabel
            role: tile.bottomLabelRole
            color: Theme.color.onSurface
            maximumLineCount: 1
        }
        Row {
            id: bottomValueLine
            // from the texts, not the children's visible (a hidden row hides them, and would stay hidden)
            visible: tile.bottomIcon !== "" || tile.bottomValue !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.dp(4)
            Icon {
                id: bottomIconItem
                objectName: "tileBottomIcon"
                visible: name !== ""
                name: tile.bottomIcon
                color: tile.bottomIconColor
                width: Theme.dp(16)
                height: width
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: bottomValueItem
                visible: text !== ""
                width: Math.min(implicitWidth, bottomSlot.width
                                - (tile.bottomIcon !== "" ? bottomIconItem.width + bottomValueLine.spacing : 0))
                elide: Text.ElideRight
                text: tile.bottomValue
                role: tile.bottomValueRole
                color: tile.bottomValueColor
                maximumLineCount: 1
            }
        }
    }

    // Wear OS's edge button: hugs the round edge under the content (not on an expressive tile)
    EdgeButton {
        id: chip
        objectName: "tileChip"
        visible: !tile.expressive && (tile.chipText !== "" || tile.chipIcon !== "")
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

    // the expressive tiles' compact pill (S13 'New', S14-c 'Refresh'): the 64 px container 24 px above the
    // bottom, centred, its 96 px touch area round it
    CompactButton {
        id: pillButton
        objectName: "tilePill"
        visible: tile.hasPill
        anchors.horizontalCenter: parent.horizontalCenter
        y: tile.height - tile.pillBottom - tile.pillHeight - (height - tile.pillHeight) / 2
        text: tile.pillText
        labelRole: "labelSmall"
        containerColor: tile.pillColor
        contentColor: tile.pillContentColor
        onClicked: tile.pillClicked()
    }
}
