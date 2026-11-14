/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import Nemo.Configuration
import org.asteroid.controls
import "../desktop.js" as Desktop
import "smartlinks.js" as Links

/* The smart links of an open notification (system-dialogs-misc-04, -05), as stock's
 * SmartLinksMenuActivity: a tap on a phone number opens a dialog with a person icon (24 dp), the
 * number as its title and two chips, "Message" then "Call" (52 dp high). Call asks the phone to
 * dial it (the assistant relay's "dial" action, as the emergency call does), Message opens the
 * full screen keyboard and sends the text from the phone ("sms" with the number). A tap on an
 * address has no menu: the phone opens it in its map ("nav", as the assistant's directions).
 * Without the phone link the shared "Phone away" dialog says so; the dry-run keys of the
 * assistant keep a test from dialling or sending. No number or address is written to the log.
 * Opened through Desktop.smartLinks.open(kind, value); it listens to D-Bus only while an action
 * waits for its answer. */
Item {
    id: links
    objectName: "smartLinks"
    anchors.fill: parent

    readonly property bool shown: menu.shown || composer.active
    readonly property alias menu: menu
    readonly property alias composer: composer
    // the number or address now on the menu
    property string value: ""
    property string kind: ""
    readonly property alias relay: relay
    property var _waits: ({})
    property int _seq: 0
    // the answers being waited for: the relay listens only while there is one (no standing listener)
    property int waiting: 0

    // stock: wear_chip_button_default_min_height 52 dp, wear_alertdialog_icon_size 24 dp
    readonly property real chipHeight: Theme.dp(52)
    readonly property real iconSize: Theme.dp(24)

    ConfigurationValue { id: callDryRun; key: "/org/asteroidos/assistant/call-dry-run"; defaultValue: false }
    ConfigurationValue { id: smsDryRun; key: "/org/asteroidos/assistant/sms-dry-run"; defaultValue: false }

    Component.onCompleted: Desktop.smartLinks = links
    Component.onDestruction: if (Desktop.smartLinks === links) Desktop.smartLinks = null

    function open(k, v) {
        kind = k
        value = v
        if (k === "address")
            openAddress(v)
        else if (k === "phone")
            menu.open()
    }
    function close() {
        composer.close()
        menu.close()
    }

    /* ---- the actions ---------------------------------------------------- */

    function phoneAway() {
        if (Desktop.phoneAway)
            Desktop.phoneAway.show()
    }

    function call() {
        var number = value
        menu.close()
        var dry = callDryRun.value === true || callDryRun.value === "true"
        act({ a: "dial", nm: number, dry: dry }, function (r) {
            if (r && r.ok)
                showOpenOnPhone()
            else
                failed(r, false)
        })
    }

    function openAddress(address) {
        act({ a: "nav", q: address }, function (r) {
            if (r && r.ok)
                showOpenOnPhone()
            else
                failed(r, false)
        })
    }

    // the compose keyboard's send
    function send(text) {
        var number = value
        var dry = smsDryRun.value === true || smsDryRun.value === "true"
        act({ a: "sms", num: number, tx: text, dry: dry }, function (r) {
            if (r && r.ok) {
                if (Desktop.confirmation)
                    //% "Message sent"
                    Desktop.confirmation.show(qsTrId("id-smartlink-sent") + localeManager.changesObserver, true)
            } else {
                failed(r, true)
            }
        })
    }

    function showOpenOnPhone() {
        if (Desktop.confirmation)
            Desktop.confirmation.showOpenOnPhone()
    }

    // no link: the "Phone away" dialog; a send that fails otherwise says it was not sent
    function failed(r, sending) {
        var er = r ? r.er : ""
        if (er === "no-phone" || er === "disconnected" || er === "old-app" || er === "timeout") {
            if (sending && Desktop.confirmation)
                //% "To send, reconnect to your phone"
                Desktop.confirmation.show(qsTrId("id-send-reconnect") + localeManager.changesObserver, false)
            else
                phoneAway()
        } else if (Desktop.confirmation) {
            Desktop.confirmation.show(sending
                                      //% "Not sent."
                                      ? qsTrId("id-smartlink-not-sent") + localeManager.changesObserver
                                      //% "Couldn’t open on phone"
                                      : qsTrId("id-smartlink-failed") + localeManager.changesObserver, false)
        }
    }

    // the assistant relay: the actions the phone side offers, then the action, then its result
    function act(json, cb) {
        relay.typedCall("Actions", [], function (list) {
            if (list && list.indexOf(json.a) >= 0) {
                var id = ++_seq
                var w = _waits
                w[id] = cb
                _waits = w
                waiting++
                relay.typedCall("Act", [{ "type": "u", "value": id }, { "type": "s", "value": JSON.stringify(json) }],
                    function (ok) { if (!ok) links.actResult(id, JSON.stringify({ ok: false, er: "no-phone" })) },
                    function () { links.actResult(id, JSON.stringify({ ok: false, er: "no-phone" })) })
                return
            }
            cb({ ok: false, er: "old-app" })
        }, function () { cb({ ok: false, er: "no-phone" }) })
    }
    function actResult(id, json) {
        var cb = _waits[id]
        if (!cb)
            return
        var w = _waits
        delete w[id]
        _waits = w
        waiting--
        var r
        try { r = JSON.parse(json) } catch (e) { r = { ok: false, er: "failed" } }
        cb(r)
    }

    DBusInterface {
        id: relay
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/assistant"
        iface: "org.asteroidos.btsyncd.Assistant"
        signalsEnabled: links.waiting > 0
        function rcActResult(id: int, json: string) { links.actResult(id, json) }
    }

    /* ---- the menu ---------------------------------------------------------- */

    AlertDialog {
        id: menu
        objectName: "smartLinksMenu"
        title: links.kind === "phone" ? Links.titleOf(links.value) : ""
        buttons: "none"
        // the person icon, 24 dp (wear_alertdialog_icon_size), in the dialog's 32 dp icon slot
        icon: Component {
            Icon {
                anchors.centerIn: parent
                width: links.iconSize
                height: width
                name: "ms-person"
                color: Theme.color.onBackground
            }
        }

        Column {
            id: chips
            width: parent ? parent.width : 0
            spacing: Theme.dp(4)

            Button {
                id: messageChip
                objectName: "smartLinkMessage"
                width: parent.width
                height: links.chipHeight
                variant: "tonal"
                horizontalPadding: Theme.dp(14)
                iconSize: links.iconSize
                iconSpacing: Theme.dp(6)
                containerColor: Theme.color.surfaceContainer
                contentColor: Theme.color.onSurface
                iconColor: Theme.color.onSurface
                iconName: "ms-chat"
                //% "Message"
                text: qsTrId("id-smartlink-message") + localeManager.changesObserver
                onClicked: {
                    menu.close()
                    composer.open()
                }
            }
            Button {
                id: callChip
                objectName: "smartLinkCall"
                width: parent.width
                height: links.chipHeight
                variant: "tonal"
                horizontalPadding: Theme.dp(14)
                iconSize: links.iconSize
                iconSpacing: Theme.dp(6)
                containerColor: Theme.color.surfaceContainer
                contentColor: Theme.color.onSurface
                iconColor: Theme.color.onSurface
                iconName: "ms-call"
                //% "Call"
                text: qsTrId("id-smartlink-call") + localeManager.changesObserver
                onClicked: links.call()
            }
        }
    }

    /* ---- Message: the full screen keyboard ---------------------------------- */

    Item {
        id: composer
        objectName: "smartLinksComposer"
        anchors.fill: parent
        z: 2
        visible: active
        property bool active: false

        function open() {
            active = true
            keyboardLoader.active = true
        }
        function close() {
            active = false
            keyboardLoader.active = false
        }

        // swallow touches under the keyboard
        MouseArea { anchors.fill: parent; enabled: composer.active }

        Loader {
            id: keyboardLoader
            anchors.fill: parent
            active: false
            sourceComponent: Component {
                WearKeyboard {
                    id: keyboard
                    actionKey: "send"
                    emojiEnabled: false
                    inputMethodHints: Qt.ImhNone
                    onAccepted: (text) => {
                        var t = String(text).trim()
                        composer.close()
                        if (t.length > 0)
                            links.send(t)
                    }
                    onDismissed: composer.close()
                    Component.onCompleted: {
                        Desktop.keyboard = keyboard
                        forceActiveFocus()
                    }
                    Component.onDestruction: if (Desktop.keyboard === keyboard) Desktop.keyboard = null
                }
            }
        }
    }
}
