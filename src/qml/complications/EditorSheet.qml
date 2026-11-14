/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "faceeditor.js" as FE

/*
 * A full-screen black list of the face editor: the options of a list setting
 * (fragment_list_options.xml) and the data sources of a complication
 * (ProviderChooserFragment). Stock's list paddings (16.64 % at the top, 36.45 %
 * at the bottom, 5.2 % at the sides, chips 4 dp apart: ScalingList's own),
 * a title header with 7.3 % side padding, the crown scrolls it (RotaryInput),
 * a swipe right or the editor's back goes back to the page below. It opens
 * scrolled to `current`. Rows come from `rowDelegate` (a ListItem with the
 * `index`, `modelData` and `model` properties ScalingList sets).
 */
Item {
    id: sheet

    property string title: ""
    property var model: []
    property Component rowDelegate: null
    // the row the list opens on
    property int current: 0
    property bool shown: false
    readonly property Item list: scaling

    // the sheet went back (swipe right)
    signal backRequested()
    // the list moved (the editor's idle timer restarts)
    signal poked()

    anchors.fill: parent
    visible: shown

    function open(index) {
        current = index === undefined ? 0 : index
        shown = true
        scaling.positionViewAtBeginning()
        if (current > 0)
            scaling.positionViewAtIndex(current, ListView.Center)
    }
    function closeNow() {
        shown = false
    }
    function back() {
        if (!shown)
            return
        closeNow()
        backRequested()
    }

    Rectangle { anchors.fill: parent; color: "#000000" }
    // nothing under the sheet takes a touch
    MouseArea { anchors.fill: parent; enabled: sheet.shown }

    ScalingList {
        id: scaling
        objectName: "eosEditorSheetList"
        anchors.fill: parent
        model: sheet.model
        itemDelegate: sheet.rowDelegate
        interactive: sheet.shown
        onContentYChanged: if (sheet.shown) sheet.poked()
        header: ListHeader {
            objectName: "eosEditorSheetHeader"
            text: sheet.title
            horizontalPadding: Math.round(sheet.width * FE.OPTIONS_TITLE_SIDE)
        }
    }

    // swipe right: back (the stock decision rule of the back swipe)
    DragHandler {
        id: swipe
        target: null
        enabled: sheet.shown
        yAxis.enabled: false
        property real lastDx: 0
        property real dx: 0
        property real v: 0
        onTranslationChanged: {
            lastDx = translation.x - dx
            dx = translation.x
            v = centroid.velocity.x
        }
        onActiveChanged: {
            if (active) {
                dx = 0
                lastDx = 0
                v = 0
            } else if (Motion.backShouldCommit(dx, v, lastDx, sheet.width, Theme.dp(1))) {
                sheet.back()
            }
        }
    }
}
