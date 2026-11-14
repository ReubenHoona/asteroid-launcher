/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The stock quick settings' question before a mode comes on (SysUI's
 * Do Not Disturb, Bedtime, Theater, Battery Saver, Airplane mode and Mobile
 * dialogs) and its info dialogs (Flashlight, Find My Phone), on the shared
 * M3 AlertDialog (SysUI lgi.java:442-488, krm.java:83-90, esw.java:177-194):
 * the tile's icon on top, the title, the text, a "Don't show again" check box
 * row where the setting has one, then Dismiss (the 60 dp tonal rounded
 * square) and Confirm (the 63 x 54 dp primary pill); an info dialog has one
 * check button.
 *
 *   modeDialog.ask(title, message, function (dontShowAgain) { ... }, iconName, showDontAsk)
 *   modeDialog.info(title, message, iconName)
 *
 * Asking again replaces the question: there is one pending answer, never a
 * handler per ask (dialogs-pickers-feedback-20).
 */
Item {
    id: dialog

    property string title: ""
    property string message: ""
    property string iconName: ""
    property bool dontShowAgain: false
    /*! The "Don't show again" row is there. */
    property bool showDontAsk: true
    /*! An info dialog: one button, no question. */
    property bool infoOnly: false
    property var _accept: null
    readonly property bool shown: alert.shown
    readonly property alias alert: alert

    anchors.fill: parent
    visible: alert.active
    z: 900

    function _open() {
        dontShowAgain = false
        alert.open()
    }
    function ask(title, message, onAccept, iconName, showDont) {
        dialog.title = title || ""
        dialog.message = message || ""
        dialog.iconName = iconName || ""
        dialog.showDontAsk = showDont === undefined ? true : showDont
        dialog.infoOnly = false
        _accept = onAccept || null
        _open()
    }
    function info(title, message, iconName) {
        dialog.title = title || ""
        dialog.message = message || ""
        dialog.iconName = iconName || ""
        dialog.showDontAsk = false
        dialog.infoOnly = true
        _accept = null
        _open()
    }
    /*! Answer yes, as the confirm button does. */
    function accept() { alert._confirm() }
    function close() {
        _accept = null
        alert.close()
    }

    AlertDialog {
        id: alert
        objectName: "modeAlert"
        title: dialog.title
        text: dialog.message
        iconName: dialog.iconName
        buttons: dialog.infoOnly ? "edge" : "confirmDismiss"
        // nothing here holds the screen on (alert dialogs never do)
        onConfirmed: {
            var f = dialog._accept
            var dont = dialog.dontShowAgain
            dialog._accept = null
            if (f)
                f(dont)
        }
        onDismissed: dialog._accept = null

        // The wrapper keeps its own visibility and only changes its height: a Column does
        // not hear about a child that turns visible under an invisible parent (AlertDialog
        // hides a row of no height), so a check box that came and went by `visible` would
        // not come back after an info dialog.
        Item {
            width: parent.width
            height: dialog.showDontAsk && !dialog.infoOnly ? dontBox.height : 0
            CheckboxButton {
                id: dontBox
                objectName: "modeDialogDontShow"
                visible: dialog.showDontAsk && !dialog.infoOnly
                width: parent.width
                //% "Don't show again"
                text: qsTrId("id-dont-show-again")
                // a tap sets checked itself, which ends a binding: follow the dialog by hand
                onToggled: (c) => dialog.dontShowAgain = c
                Connections {
                    target: dialog
                    function onDontShowAgainChanged() { dontBox.checked = dialog.dontShowAgain }
                }
            }
        }
    }
}
