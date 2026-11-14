/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import org.asteroid.controls
import "desktop.js" as Desktop

/*
 * The page of a long press on a notification, as Wear OS CP3A has it
 * (BlockingNotificationMenuActivity, sysui kxr.java:520-560, kga.java:44):
 * the app's name as the title, the subtitle "Notifications", the text
 * "Notifications from APP won't appear on your watch." and a "Turn off"
 * button with an icon (filled tonal). The button asks "Turn off APP
 * notifications?" / "You can still manage settings in the Gadgetbridge app on
 * your phone" (the shared alert dialog, a cross and a tick); the tick tells the
 * phone to stop sending the app's notifications (asteroid-btsyncd's
 * SetAppNotifications false, feedback mute) and closes the page. An app that
 * cannot be turned off (mutable false) shows "Notifications from APP can't be
 * turned off" and no button. There is no switch back on: that stays in
 * Gadgetbridge. Without a phone nothing changes and the stream's failure dialog
 * ("Can't finish action", "Please check your connection") shows.
 */
Item {
    id: menu

    property QtObject notification
    // the page sits under the TimeText (the stream) or not
    property bool belowTimeText: true

    // what the card was when the menu opened: the menu works on even if the
    // card goes meanwhile
    property int notificationId: 0
    property string appName: ""
    // the phone can stop this app's notifications (the phone-actions hint has mute)
    property bool mutable: true
    property bool pending: false
    // the stream's NotificationRemote: its failure dialog (else the shared confirmation)
    property QtObject remote: null
    // the phone took the app off: the page goes
    signal turnedOff()

    // How far the page is scrolled (the time scrolls away with it)
    readonly property real scrolled: Math.max(0, flick.contentY - flick.originY)

    /*
     * Opened by a long press whose finger is still down (the stream's card):
     * as stock (the menu is another window there, the touch stays with the
     * card), nothing here reacts to that touch, nor to what its lift turns
     * into: the page takes input from the next press on. holding is that
     * touch; once it is up (and a press the page got from it is over) the
     * guard goes armDelayMs later. A guard that never hears of the lift goes
     * after guardMaxMs.
     */
    property bool openedByHold: false
    property bool holding: false
    property bool guardOn: false
    readonly property int armDelayMs: 150
    readonly property int guardMaxMs: 4000
    onHoldingChanged: if (!holding) armSoon()
    function armSoon() {
        if (guardOn)
            armTimer.restart()
    }
    Timer {
        id: armTimer
        interval: menu.armDelayMs
        onTriggered: if (!guard.pressed && !menu.holding) menu.guardOn = false
    }
    Timer {
        running: menu.guardOn
        interval: menu.guardMaxMs
        onTriggered: if (!guard.pressed) menu.guardOn = false
    }

    Component.onCompleted: {
        if (notification) {
            notificationId = notification.replacesId
            appName = notification.appName
        }
        guardOn = openedByHold
        if (guardOn && !holding)
            armSoon()
    }

    function failed() {
        pending = false
        if (remote)
            remote.showFailure()
        //% "Can't finish action. Please check your connection."
        else if (Desktop.confirmation) Desktop.confirmation.show(qsTrId("id-action-error"), false)
    }

    // the tick of the dialog: mute the app
    function turnOff() {
        if (pending || notificationId === 0 || !mutable)
            return
        pending = true
        btsyncd.typedCall("SetAppNotifications",
                          [{ "type": "u", "value": notificationId },
                           { "type": "b", "value": false }],
                          function (done) {
                              if (!done) {
                                  menu.failed()
                                  return
                              }
                              pending = false
                              // the switch is off now (haptics-sounds-03: stock vibrates for a switch)
                              Haptics.toggleOff()
                              menu.turnedOff()
                          },
                          function () { menu.failed() })
    }

    DBusInterface {
        id: btsyncd
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/notifications"
        iface: "org.asteroidos.btsyncd.Notifications"
    }

    // the opening touch's guard: over the whole page, it takes every press
    // while it is on (the back swipe still sees them)
    MouseArea {
        id: guard
        objectName: "blockingGuard"
        anchors.fill: parent
        z: 1000
        enabled: menu.guardOn
        onReleased: menu.armSoon()
        onCanceled: menu.armSoon()
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: Math.max(height + 1, column.y + column.height + Dims.h(22))
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.DragOverBounds

        Column {
            id: column
            objectName: "blockingColumn"
            x: menu.sidePadding
            y: menu.belowTimeText ? Dims.h(16) : Dims.h(12)
            width: parent.width - 2 * menu.sidePadding
            spacing: 0

            // the app's name
            Label {
                id: title
                objectName: "blockingTitle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: menu.appName
                role: "titleMedium"
                color: Theme.color.onSurface
            }

            Label {
                id: subtitle
                objectName: "blockingSubtitle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                //% "Notifications"
                text: qsTrId("id-notifications-menu-title") + localeManager.changesObserver
                role: "labelMedium"
                color: Theme.color.onSurfaceVariant
            }

            Item { width: 1; height: Theme.dp(8) }

            Label {
                id: description
                objectName: "blockingText"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: (menu.mutable
                       //% "Notifications from %1 won’t appear on your watch."
                       ? qsTrId("id-blocking-text").arg(menu.appName)
                       //% "Notifications from %1 can’t be turned off"
                       : qsTrId("id-blocking-immutable").arg(menu.appName)) + localeManager.changesObserver
                role: "bodyMedium"
                color: Theme.color.onSurfaceVariant
            }

            Item { width: 1; height: menu.mutable ? Theme.dp(12) : 0 }

            Button {
                id: turnOffButton
                objectName: "blockingTurnOff"
                visible: menu.mutable
                height: visible ? implicitHeight : 0
                width: parent.width
                variant: "tonal"
                centered: true
                iconName: "ios-notifications-off-outline"
                enabled: !menu.pending
                //% "Turn off"
                text: qsTrId("id-blocking-turn-off") + localeManager.changesObserver
                onClicked: confirmDialog.open()
            }
        }
    }

    // "Turn off APP notifications?" (kxr.java:550-560)
    AlertDialog {
        id: confirmDialog
        objectName: "blockingConfirm"
        //% "Turn off %1 notifications?"
        title: qsTrId("id-blocking-confirm-title").arg(menu.appName) + localeManager.changesObserver
        //% "You can still manage settings in the %1 app on your phone"
        text: qsTrId("id-blocking-confirm-text").arg("Gadgetbridge") + localeManager.changesObserver
        onConfirmed: menu.turnOff()
    }

    readonly property real sidePadding: Math.ceil(0.052 * (width > 0 ? width : 384))
}
