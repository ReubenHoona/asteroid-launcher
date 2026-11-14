/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "../pager.js" as Pager

/*
 * The carousel's page indicator, which is the tile's app icon (stock
 * TilesIndicator, hjw.java:247-440; no page dots): a 24 dp circle, 3 dp
 * from the top, always there on a tile page (tiles are M3_PL) and on the
 * empty page. In a swipe the icons of the two pages slide with them, 18 dp
 * apart; the face has no icon, so between the face and a tile the tile's
 * icon is 78.125 % of the width from the middle and 20 % of the height
 * lower, easing up as the page settles (rules in pager.js, pose()).
 * "position" is the pager's place in the grid's virtual columns
 * (PanelsGrid.ringPosition), "count" the tile pages, "iconFor(page)" the
 * icon name of a page.
 *
 * Nothing runs here: the poses are bindings of the position, which only
 * changes while a finger or the spring moves the pages.
 */
Item {
    id: indicator
    anchors.fill: parent

    property real position: 0
    property int count: 0
    property var iconFor: function (page) { return "" }
    // the page of the empty tile: the plus on white (empty_tile_icon_background)
    property bool emptyPage: false

    readonly property real iconSize: Theme.size.tileAppIcon
    readonly property real gap: Theme.dp(18)
    readonly property var poses: visible && count > 0
        ? Pager.pose(position, count, iconSize, gap, width, height) : []

    Repeater {
        model: 2
        delegate: Rectangle {
            id: bulb
            objectName: "tileIcon" + index
            readonly property var pose: index < indicator.poses.length ? indicator.poses[index] : null
            visible: pose !== null
            width: indicator.iconSize
            height: width
            radius: width / 2
            x: (indicator.width - width) / 2 + (pose ? pose.dx : 0)
            y: Theme.size.tileAppIconTop + (pose ? pose.dy : 0)
            opacity: pose ? pose.alpha : 0
            color: indicator.emptyPage ? "#ffffff" : Theme.color.surfaceContainerHigh

            Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.625)
                height: width
                name: bulb.pose ? indicator.iconFor(bulb.pose.tile) : ""
                color: indicator.emptyPage ? "#000000" : Theme.color.onSurface
            }
        }
    }
}
