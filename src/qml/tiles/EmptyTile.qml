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
 * padding top 33 dp, sides 3 % of the width, bottom 10 % of the height
 * (hjw.java:S, the outer box). Inside it stock draws a card, full width, as
 * high as its content, centred, filled surfaceContainer (euv.q) with 50 %
 * corners (awp(50.0f)); the title is padded 14 dp at the sides and 10 dp
 * above, the message 14 dp at the sides and 10 dp below, 3 dp between the
 * lines (VALUES.tsv sysui empty_tile_*). Its icon (the plus on white,
 * empty_tile_icon_background) is the carousel's indicator at the top
 * (TilesIndicator). A long press opens the editor, which then only offers
 * "Add new".
 */
Item {
    id: empty

    // the editor's entry, as TileBase's long press
    signal editRequested()

    readonly property real padTop: Theme.dp(33)
    readonly property real padSide: width * 0.03
    readonly property real contentPadH: Theme.dp(14)     // empty_tile_content_horizontal_padding
    readonly property real contentPadV: Theme.dp(10)     // empty_tile_content_vertical_padding
    readonly property real padBottom: height * 0.10
    readonly property real titleGap: Theme.dp(3)
    readonly property alias title: titleLabel
    readonly property alias message: messageLabel
    readonly property alias card: card

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

        // stock's inner box: surfaceContainer, 50 % corners, as high as its text
        Rectangle {
            id: card
            width: parent.width
            height: textColumn.implicitHeight + 2 * empty.contentPadV
            anchors.verticalCenter: parent.verticalCenter
            radius: Math.min(width, height) * 0.5
            color: Theme.color.surfaceContainer

            Column {
                id: textColumn
                x: empty.contentPadH
                y: empty.contentPadV
                width: parent.width - 2 * empty.contentPadH
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
}
