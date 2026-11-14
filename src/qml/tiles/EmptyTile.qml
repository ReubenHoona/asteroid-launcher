/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "../pager.js" as Pager

/*
 * The carousel's one page when there is no tile (stock nax.java:117-127,
 * jmq.java): "Add a widget" (titleMedium, onSurface) over "Long press any
 * widget to edit your carousel" (labelSmall, onSurfaceVariant), centred;
 * padding top 33 dp, sides 3 % of the width + 14 dp, bottom 10 % of the
 * height, 10 dp above and below the text block and 3 dp between its lines
 * (VALUES.tsv sysui empty_tile_*). Its icon (the plus on white,
 * empty_tile_icon_background) is the carousel's indicator at the top
 * (TilesIndicator). A long press opens the editor, which then only offers
 * "Add new".
 */
Item {
    id: empty

    // the editor's entry, as TileBase's long press
    signal editRequested()

    readonly property real padTop: Theme.dp(33)
    readonly property real padSide: width * 0.03 + Theme.dp(14)
    readonly property real padBottom: height * 0.10
    readonly property real titleGap: Theme.dp(3)
    readonly property alias title: titleLabel
    readonly property alias message: messageLabel

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#000000"
    }

    MouseArea {
        anchors.fill: parent
        pressAndHoldInterval: Pager.LONG_PRESS_MS
        onPressAndHold: {
            Haptics.longPress()
            empty.editRequested()
            if (typeof desktop !== "undefined" && desktop.openTilesEditor)
                desktop.openTilesEditor()
        }
    }

    Item {
        id: slot
        anchors {
            fill: parent
            topMargin: empty.padTop
            bottomMargin: empty.padBottom
            leftMargin: empty.padSide
            rightMargin: empty.padSide
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: empty.titleGap

            Label {
                id: titleLabel
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                role: "titleMedium"
                color: Theme.color.onSurface
                wrapMode: Text.Wrap
                //% "Add a widget"
                text: qsTrId("id-tiles-empty-title")
            }
            Label {
                id: messageLabel
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                role: "labelSmall"
                color: Theme.color.onSurfaceVariant
                wrapMode: Text.Wrap
                //% "Long press any widget to edit your carousel"
                text: qsTrId("id-tiles-empty-message")
            }
        }
    }
}
