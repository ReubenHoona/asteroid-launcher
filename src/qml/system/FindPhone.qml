/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import org.asteroid.controls
import "../desktop.js" as Desktop

/* Find my phone (apps-misc-04), as stock's RingMyPhoneActivity: the quick settings button and the
 * app list entry open a full screen page: the title "Find my phone", the phone's battery as the
 * status line, one large round check button. The tap rings the phone through asteroid-btsyncd
 * (Gadgetbridge rings it even when it is muted or on vibrate); the page then says "Ringing your
 * phone" with a Stop (cross) button, and goes back to the first state when the phone says it
 * stopped (FindPhoneChanged(false)). Without the phone link the page says "Your watch is not
 * connected to your phone" and has no button.
 * Leaving the page (swipe back, the crown) does not stop the ringing: the quick settings button
 * shows it and stops it on the phone's side. The page registers itself as Desktop.findMyPhone.
 * The D-Bus signals are listened to only while the page is up; nothing is polled. */
Item {
    id: page
    objectName: "findPhone"
    anchors.fill: parent

    readonly property bool shown: dialog.shown
    readonly property alias dialog: dialog
    // "idle": the check button; "ringing": the Stop button; "away": no phone link
    readonly property string mode: !connected && known ? "away" : (ringing ? "ringing" : "idle")
    property bool connected: false
    // the link state has been answered by btsyncd
    property bool known: false
    property bool ringing: false
    // the phone's battery in percent, -1 when it is not known
    property int level: -1

    readonly property alias circle: circle
    // the two buses, for the tests
    readonly property alias phoneBus: phone
    readonly property alias finderBus: finder
    readonly property alias titleLabel: titleLabel
    readonly property alias statusLabel: statusLabel
    readonly property real circleSize: Theme.dp(104)

    function open() {
        if (dialog.shown)
            return
        known = false
        level = -1
        dialog.open()
        refresh()
    }
    function close() { dialog.close() }

    // one ask of each at opening (answers are also kept up by the signals while it is up)
    function refresh() {
        phone.typedCall("Connected", [], function (c) { page.connected = c; page.known = true },
                        function () { page.connected = false; page.known = true })
        phone.typedCall("BatteryLevel", [], function (l) { page.level = (l >= 0 && l <= 100) ? l : -1 },
                        function () { page.level = -1 })
        finder.typedCall("FindingPhone", [], function (r) { page.ringing = r === true },
                         function () { page.ringing = false })
    }

    // the tap: ring, or stop
    function press() {
        if (mode === "away")
            return
        var start = !ringing
        finder.typedCall("FindPhone", [{ "type": "b", "value": start }],
                         function (ok) {
                             if (start && !ok) {
                                 // the link went down meanwhile: the same words as without it
                                 page.connected = false
                                 page.known = true
                                 page.ringing = false
                             } else {
                                 page.ringing = start
                             }
                         },
                         function () {
                             if (start) {
                                 page.connected = false
                                 page.known = true
                             }
                         })
    }

    Component.onCompleted: Desktop.findMyPhone = page
    Component.onDestruction: if (Desktop.findMyPhone === page) Desktop.findMyPhone = null

    DBusInterface {
        id: phone
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/phone"
        iface: "org.asteroidos.btsyncd.Phone"
        signalsEnabled: page.shown

        function rcConnectedChanged(connected: bool) {
            page.connected = connected
            page.known = true
        }
        function rcBatteryLevelChanged(level: int) {
            page.level = (level >= 0 && level <= 100) ? level : -1
        }
    }

    DBusInterface {
        id: finder
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/notifications"
        iface: "org.asteroidos.btsyncd.Notifications"
        signalsEnabled: page.shown

        function rcFindPhoneChanged(ringing: bool) {
            page.ringing = ringing
        }
    }

    Dialog {
        id: dialog

        Item {
            anchors.fill: parent

            // "Find my phone" / "Ringing your phone"
            Label {
                id: titleLabel
                objectName: "findPhoneTitle"
                x: page.width * 0.12
                width: page.width * 0.76
                y: Math.ceil(page.height * 0.10)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                role: "titleMedium"
                color: Theme.color.onBackground
                text: page.mode === "ringing"
                      //% "Ringing your phone"
                      ? qsTrId("id-find-phone-ringing") + localeManager.changesObserver
                      //% "Find my phone"
                      : qsTrId("id-find-phone-title") + localeManager.changesObserver
            }

            // the phone's battery, or why there is no button
            Label {
                id: statusLabel
                objectName: "findPhoneStatus"
                x: page.width * 0.12
                width: page.width * 0.76
                anchors.top: titleLabel.bottom
                anchors.topMargin: Theme.dp(4)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                role: "bodyMedium"
                color: Theme.color.onSurfaceVariant
                text: page.mode === "away"
                      //% "Your watch is not connected to your phone"
                      ? qsTrId("id-sos-no-phone") + localeManager.changesObserver
                      : (page.level >= 0
                         //% "Phone battery %1%"
                         ? qsTrId("id-find-phone-battery").arg(page.level) + localeManager.changesObserver
                         : "")
            }

            // the large round button: a check to ring, a cross to stop
            Rectangle {
                id: circle
                objectName: "findPhoneButton"
                visible: page.mode !== "away"
                width: page.circleSize
                height: width
                radius: width / 2
                x: (parent.width - width) / 2
                y: Math.max(statusLabel.y + statusLabel.height + Theme.dp(8), parent.height * 0.58 - height / 2)
                color: page.mode === "ringing" ? Theme.color.surfaceContainer : Theme.color.primary

                DialogGlyph {
                    anchors.centerIn: parent
                    width: Theme.dp(40)
                    height: width
                    glyph: page.mode === "ringing" ? "close" : "check"
                    color: page.mode === "ringing" ? Theme.color.onSurface : Theme.color.onPrimary
                }
                Ripple {
                    anchors.fill: parent
                    radius: width / 2
                    pressed: tap.pressed
                }
                MouseArea {
                    id: tap
                    anchors.fill: parent
                    onClicked: page.press()
                    Accessible.role: Accessible.Button
                    Accessible.name: page.mode === "ringing"
                                     //% "Stop"
                                     ? qsTrId("id-find-phone-stop")
                                     : titleLabel.text
                    Accessible.onPressAction: page.press()
                }
            }
        }
    }
}
