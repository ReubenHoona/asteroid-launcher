/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "../desktop.js" as Desktop

/* The "Phone away" dialog (connectivity-system-ux-05), the one stock shows when an action that
 * needs the phone is asked without the link (SettingsLib phone_away_error_dialog_title /
 * _subtitle): the title "Phone away", the text "Phone is not nearby or Bluetooth is off" and one
 * check button. The home screen, the notification actions and Find my phone use it through
 * Desktop.phoneAway.show(). Nothing runs while it is not up. */
Item {
    id: away
    objectName: "phoneAway"
    anchors.fill: parent

    readonly property bool shown: dialog.shown
    readonly property alias dialog: dialog

    function show() { dialog.open() }
    function close() { dialog.close() }

    Component.onCompleted: Desktop.phoneAway = away
    Component.onDestruction: if (Desktop.phoneAway === away) Desktop.phoneAway = null

    AlertDialog {
        id: dialog
        objectName: "phoneAwayDialog"
        //% "Phone away"
        title: qsTrId("id-phone-away-title") + localeManager.changesObserver
        //% "Phone is not nearby or Bluetooth is off"
        text: qsTrId("id-phone-away-text") + localeManager.changesObserver
        buttons: "edge"
    }
}
