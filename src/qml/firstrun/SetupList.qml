/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "setup.js" as Setup

/* A setup list: the stock language list's look (setup-wizard-03, -17). A scaling list on black with no visible
 * title, padding 21.8 % of the height above and below and 5.2 % of the width at the sides, and full width tonal
 * pill rows 52 dp tall (surfaceContainer, label 15 sp weight 500 in onSurface, padding 14 / 6 dp, ellipsis).
 * Tapping a row answers at once, there is no next arrow. `entries` is a list of { text, key, sub }; `sub` is an
 * optional second line. The list opens at the top. */
Item {
    id: page
    objectName: "setupList"

    property var entries: []
    // what a screen reader says for the list (the page has no visible title)
    property string accessibleName: ""
    signal chosen(string key)

    readonly property alias list: list

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    ScalingList {
        id: list
        objectName: "setupListView"
        anchors.fill: parent
        model: page.entries
        topMargin: Math.round(page.height * Setup.list.padV)
        bottomMargin: Math.round(page.height * Setup.list.padV)
        sideMargin: Math.round(page.width * Setup.list.padSide)
        Accessible.role: Accessible.List
        Accessible.name: page.accessibleName

        itemDelegate: FilledTonalButton {
            property int index
            property var modelData
            objectName: "setupRow"
            minimumHeight: Theme.dp(Setup.list.rowDp)
            horizontalPadding: Theme.dp(Setup.list.rowPadH)
            verticalPadding: Theme.dp(Setup.list.rowPadV)
            text: modelData ? modelData.text : ""
            secondaryText: modelData && modelData.sub ? modelData.sub : ""
            // one line with an ellipsis (stock language rows)
            maximumLineCount: secondaryText === "" ? 1 : 3
            onClicked: page.chosen(modelData.key)
        }
    }
}
