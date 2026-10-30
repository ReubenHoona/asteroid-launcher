/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import org.asteroid.controls
import "desktop.js" as Desktop

/*
 * The notifications of a phone app on or off, as Wear OS's long press on a
 * notification (ClockworkSysUiGoogle's BlockingNotificationMenuActivity,
 * layout blocking_notification_menu): the title "Notifications", a switch
 * chip with the app's name, and "Get notifications from APP on your watch.
 * Manage settings in the Gadgetbridge app on your phone." under it. A tap
 * on the chip turns them off (the phone stops sending them: asteroid-btsyncd's
 * SetAppNotifications, feedback mute) or on again (unmute); the card stays.
 * Without a phone nothing changes and Wear OS's "Can't finish action. Please
 * check your connection." shows.
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
    property bool appEnabled: true
    property bool pending: false

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

    function toggle() {
        if (pending || notificationId === 0)
            return
        var wanted = !appEnabled
        pending = true
        var failed = function () {
            pending = false
            //% "Can't finish action. Please check your connection."
            if (Desktop.confirmation) Desktop.confirmation.show(qsTrId("id-action-error"), false)
        }
        btsyncd.typedCall("SetAppNotifications",
                          [{ "type": "u", "value": notificationId },
                           { "type": "b", "value": wanted }],
                          function (done) {
                              if (!done) {
                                  failed()
                                  return
                              }
                              pending = false
                              appEnabled = wanted
                              Haptics.click()
                          },
                          failed)
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
            anchors.horizontalCenter: parent.horizontalCenter
            y: menu.belowTimeText ? Dims.h(16) : Dims.h(12)
            width: Dims.w(76)
            spacing: 0

            Label {
                id: title
                objectName: "blockingTitle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                //% "Notifications"
                text: qsTrId("id-notifications-menu-title") + localeManager.changesObserver
                font.pixelSize: Dims.l(7)
                font.styleName: "SemiCondensed Medium"
            }

            Item { width: 1; height: Dims.h(4) }

            // the switch chip (Wear Material: label left, switch right)
            MouseArea {
                id: chip
                objectName: "blockingChip"
                width: parent.width
                height: Math.max(Dims.h(17), appLabel.implicitHeight + Dims.h(6))
                onClicked: menu.toggle()

                Rectangle {
                    anchors.fill: parent
                    radius: Math.min(height / 2, Dims.l(8))
                    color: chip.pressed ? "#3a3a3d" : "#262628"
                }

                Label {
                    id: appLabel
                    objectName: "blockingApp"
                    anchors.left: parent.left
                    anchors.leftMargin: Dims.w(6)
                    anchors.right: track.left
                    anchors.rightMargin: Dims.w(3)
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: menu.appName
                    font.pixelSize: Dims.l(6.6)
                    font.styleName: "SemiCondensed Medium"
                }

                Rectangle {
                    id: track
                    objectName: "blockingSwitch"
                    readonly property bool on: menu.appEnabled
                    anchors.right: parent.right
                    anchors.rightMargin: Dims.w(5)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Dims.l(12)
                    height: Dims.l(7)
                    radius: height / 2
                    color: on ? "#a8c7fa" : "transparent"
                    border.width: on ? 0 : Math.max(1, Dims.l(0.6))
                    border.color: "#8e918f"
                    opacity: menu.pending ? 0.6 : 1

                    Rectangle {
                        width: track.on ? track.height * 0.72 : track.height * 0.5
                        height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: track.on ? track.width - width - (track.height - width) / 2
                                    : (track.height - width) / 2
                        color: track.on ? "#062e6f" : "#8e918f"
                    }
                }
            }

            Item { width: 1; height: Dims.h(2) }

            Label {
                id: subtext
                objectName: "blockingSubtext"
                width: parent.width
                leftPadding: Dims.w(3.5)
                rightPadding: Dims.w(3.5)
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignLeft
                color: "#c4c7c5"
                //% "Get notifications from %1 on your watch. Manage settings in the %2 app on your phone."
                text: qsTrId("id-notifications-menu-subtext").arg(menu.appName).arg("Gadgetbridge") + localeManager.changesObserver
                font.pixelSize: Dims.l(5.4)
            }
        }
    }
}
