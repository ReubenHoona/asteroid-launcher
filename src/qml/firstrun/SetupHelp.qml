/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "setup.js" as Setup

/* "Need help?" (setup-wizard-13): "On your phone" and three tips, as stock's HelpScreen (the title in the
 * title style, the tips in the body style), then where to read more. The app is Gadgetbridge; the page of its
 * project stands where stock names its help address. A swipe right goes back to the instructions. */
Item {
    id: page
    objectName: "setupHelp"

    property string appName: "Gadgetbridge"
    // where to read more (shown as plain text: the watch has no browser)
    property string helpUrl: "gadgetbridge.org"

    readonly property alias list: list
    readonly property var rows: ["title", "tip1", "tip2", "tip3", "more", "url"]

    function rowText(id) {
        switch (id) {
        //% "On your phone"
        case "title": return qsTrId("id-setup-help-title") + localeManager.changesObserver
        //% "1. Go to F-Droid to download the %1 app"
        case "tip1": return qsTrId("id-setup-help-tip-download").arg(page.appName) + localeManager.changesObserver
        //% "2. Open the %1 app and connect to your watch"
        case "tip2": return qsTrId("id-setup-help-tip-open").arg(page.appName) + localeManager.changesObserver
        //% "3. Make sure your phone is connected to the internet and Bluetooth is turned on"
        case "tip3": return qsTrId("id-setup-help-tip-internet") + localeManager.changesObserver
        //% "For more help, go to this URL on your phone:"
        case "more": return qsTrId("id-setup-help-more") + localeManager.changesObserver
        case "url": return page.helpUrl
        }
        return ""
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    ScalingList {
        id: list
        objectName: "setupHelpList"
        anchors.fill: parent
        model: page.rows
        topMargin: Math.round(page.height * Setup.instructions.top)
        bottomMargin: Math.round(page.height * 0.2)
        sideMargin: Math.round(page.width * Setup.instructions.side)
        spacing: Theme.dp(Setup.instructions.downloadGapDp)

        itemDelegate: Label {
            property int index
            property var modelData
            objectName: "setupHelp_" + modelData
            wrapMode: Text.Wrap
            horizontalAlignment: modelData === "title" || modelData === "url" ? Text.AlignHCenter : Text.AlignLeft
            role: modelData === "title" || modelData === "url" ? "titleMedium" : "bodyMedium"
            color: modelData === "url" ? Theme.color.primary : Theme.color.onBackground
            text: page.rowText(modelData)
        }
    }
}
