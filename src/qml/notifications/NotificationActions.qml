/*
 * Copyright (C) 2017 Florent Revest <revestflo@gmail.com>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import QtQuick
import Nemo.Configuration
import Nemo.DBus
import QtQuick.VirtualKeyboard
import org.asteroid.controls
import org.asteroid.launcher

Item {
    id: actions

    property QtObject panelsGrid
    property QtObject notification
    property QtObject notificationModel

    property bool forbidLeft:  true
    property bool forbidRight: true
    property bool forbidBottom: false

    property string timestampStr: ""

    // Actions the phone offers for a notification it sent (asteroid-btsyncd
    // puts them in this hint): reply, open, mute, answer, reject
    readonly property var phoneActions: {
        if (notification === undefined || notification === null)
            return []
        var a = notification.hints["x-asteroid-phone-actions"]
        return a ? String(a).split(",") : []
    }
    readonly property bool fromPhone: phoneActions.length > 0

    function hasPhoneAction(key) {
        return phoneActions.indexOf(key) >= 0
    }

    // Lipstick reports the press to asteroid-btsyncd, which tells the phone;
    // the notification then closes
    function invokePhoneAction(key) {
        notification.actionInvoked(key)
    }

    function sendReply(text) {
        if (text.trim().length === 0)
            return
        btsyncd.typedCall("Reply",
                          [{ "type": "u", "value": notification.replacesId },
                           { "type": "s", "value": text.trim() }],
                          function (sent) { if (!sent) replyFailed.visible = true },
                          function () { replyFailed.visible = true })
    }

    DBusInterface {
        id: btsyncd
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/notifications"
        iface: "org.asteroidos.btsyncd.Notifications"
    }

    ConfigurationValue {
        id: cannedReplies
        key: "/org/asteroidos/notifications/canned-replies"
        //% "OK"
        defaultValue: [qsTrId("id-reply-ok"),
                       //% "Yes"
                       qsTrId("id-reply-yes"),
                       //% "No"
                       qsTrId("id-reply-no"),
                       //% "On my way"
                       qsTrId("id-reply-on-my-way"),
                       //% "Can't talk now"
                       qsTrId("id-reply-cant-talk"),
                       //% "Thanks!"
                       qsTrId("id-reply-thanks")]
    }

    onNotificationChanged: {
        if(notification !== undefined && notification !== null)
            updateTimestamp()
    }

    function updateTimestamp() {
        var currentTime = new Date
        var delta = (currentTime.getTime() - notification.timestamp.getTime())

        if(delta < 60*1000)
            //% "Now"
            timestampStr = qsTrId("id-now") + localeManager.changesObserver
        else {
            delta = parseInt(delta/(1000*60))
            if(delta < 60) {
                //% "m"
                timestampStr = delta + qsTrId("id-minute-abbrev") + localeManager.changesObserver
            } else {
                delta = parseInt(delta/60)
                if(delta < 60) {
                    //% "h"
                    timestampStr = delta + qsTrId("id-hour-abbrev") + localeManager.changesObserver
                } else {
                    delta = parseInt(delta/24)
                    //% "d"
                    timestampStr = delta + qsTrId("id-day-abbrev") + localeManager.changesObserver
                }
            }
        }
    }

    Connections {
        target: panelsGrid
        function onCurrentHorizontalPosChanged() {
            // Not when the panels were only renumbered around this one
            if(forbidBottom && !panelsGrid.following)
                layerStack.pop(layerStack.currentLayer)
            updateTimestamp()
        }
    }

    NotificationSnoozer { id: snoozer }

    LayerStack {
        id: layerStack
        win: null
        firstPage: actionsComponent
        onLayersChanged: {
            actions.forbidBottom = layers.length > 0
            leftIndicator.visible = layers.length > 0
            leftIndicator.animateFar()
            if(panelsGrid !== null)
                panelsGrid.changeAllowedDirections()
        }
    }

    Component {
        id: actionsComponent

        Item {
            Column {
                id: column

                anchors.centerIn: parent
                width: Dims.w(55)
                spacing: Dims.h(8)

                // A call from the phone: answer or decline it there
                property bool isCall: actions.hasPhoneAction("answer") || actions.hasPhoneAction("reject")

                NotificationButton {
                    //% "Answer"
                    text: qsTrId("id-call-answer") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: actions.hasPhoneAction("answer")
                    onClicked: actions.invokePhoneAction("answer")
                }

                NotificationButton {
                    //% "Decline"
                    text: qsTrId("id-call-decline") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: actions.hasPhoneAction("reject")
                    onClicked: actions.invokePhoneAction("reject")
                }

                NotificationButton {
                    //% "Reply"
                    text: qsTrId("id-reply") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: actions.hasPhoneAction("reply") && !column.isCall
                    onClicked: layerStack.push(replyLayer)
                }

                NotificationButton {
                    //% "Open on phone"
                    text: qsTrId("id-open-on-phone") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: actions.hasPhoneAction("open") && !actions.hasPhoneAction("reply") && !column.isCall
                    onClicked: actions.invokePhoneAction("open")
                }

                NotificationButton {
                    //% "Snooze"
                    text: qsTrId("id-snooze") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: !actions.fromPhone
                    onClicked: layerStack.push(snoozeLayer)
                }

                NotificationButton {
                    //% "Dismiss all"
                    text: qsTrId("id-dismiss-all") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: !actions.fromPhone
                    onClicked: actions.dismissAll()
                }

                NotificationButton {
                    //% "Dismiss"
                    text: qsTrId("id-dismiss") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: !column.isCall
                    onClicked: if (notification.userRemovable) notification.removeRequested()
                }

                NotificationButton {
                    //% "More"
                    text: qsTrId("id-more") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: actions.fromPhone
                    onClicked: layerStack.push(moreLayer)
                }
            }
        }
    }

    function dismissAll() {
        for(var i = 0 ; i < notificationModel.itemCount ; i++) {
            var notifI = notificationModel.get(i)
            if (notifI.userRemovable) {
                notifI.removeRequested()
            }
        }
    }

    // The rest for a notification from the phone
    Component {
        id: moreLayer

        Item {
            property var pop
            property int depth

            Column {
                anchors.centerIn: parent
                width: Dims.w(55)
                spacing: Dims.h(5)

                NotificationButton {
                    //% "Open on phone"
                    text: qsTrId("id-open-on-phone") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(17)
                    visible: actions.hasPhoneAction("open") && actions.hasPhoneAction("reply")
                    onClicked: actions.invokePhoneAction("open")
                }

                NotificationButton {
                    //% "Snooze"
                    text: qsTrId("id-snooze") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(17)
                    onClicked: layerStack.push(snoozeLayer)
                }

                NotificationButton {
                    //% "Mute app"
                    text: qsTrId("id-mute-app") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(17)
                    visible: actions.hasPhoneAction("mute")
                    onClicked: actions.invokePhoneAction("mute")
                }

                NotificationButton {
                    //% "Dismiss all"
                    text: qsTrId("id-dismiss-all") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(17)
                    onClicked: actions.dismissAll()
                }
            }
        }
    }

    // Reply: the canned replies (set on the phone, or these defaults) and
    // writing one
    Component {
        id: replyLayer

        Item {
            property var pop
            property int depth

            PageHeader {
                id: replyTitle
                //% "Reply"
                text: qsTrId("id-reply")
            }

            ListView {
                anchors.fill: parent
                anchors.topMargin: Dims.h(20)
                anchors.bottomMargin: Dims.h(10)
                clip: true
                model: ["\u0001write"].concat(cannedReplies.value)
                delegate: MouseArea {
                    id: replyItem
                    readonly property bool isWrite: modelData === "\u0001write"
                    width: ListView.view.width
                    height: Dims.h(18)
                    onClicked: {
                        if (isWrite)
                            layerStack.push(writeLayer)
                        else
                            actions.sendReply(modelData)
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "#33ffffff"
                        visible: replyItem.pressed
                    }

                    Icon {
                        id: replyIcon
                        name: replyItem.isWrite ? "ios-create-outline" : "ios-text-outline"
                        width: Dims.h(12)
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Dims.w(18)
                    }

                    Label {
                        //% "Write…"
                        text: replyItem.isWrite ? qsTrId("id-reply-write") : modelData
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: replyIcon.right
                        anchors.leftMargin: Dims.w(6)
                        anchors.right: parent.right
                        anchors.rightMargin: Dims.w(12)
                        font.pixelSize: Dims.l(9)
                        font.styleName: "SemiCondensed Light"
                    }
                }
            }
        }
    }

    Component {
        id: writeLayer

        Item {
            property var pop
            property int depth

            // Qt 6 Virtual Keyboard ships no free handwriting engine (the
            // HandWritingKeyboard panel stays empty without one): use its
            // keyboard, narrow enough for the round screen
            InputPanel {
                id: keyboard
                z: 99
                width: Dims.w(82)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Dims.h(40)
                visible: active
            }

            TextField {
                id: replyField
                width: Dims.w(80)
                textWidth: Dims.w(75)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Dims.h(22)
                //% "Your reply"
                previewText: qsTrId("id-reply-preview")
            }

            NotificationButton {
                //% "Send"
                text: qsTrId("id-reply-send") + localeManager.changesObserver
                width: Dims.w(40)
                height: Dims.h(17)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: replyField.bottom
                anchors.topMargin: Dims.h(6)
                visible: replyField.text.trim().length > 0 && !Qt.inputMethod.visible
                onClicked: actions.sendReply(replyField.text)
            }

            // The keyboard's Enter key sends
            Connections {
                target: replyField.editor
                function onAccepted() {
                    if (replyField.text.trim().length > 0)
                        actions.sendReply(replyField.text)
                }
            }

            Component.onCompleted: if (replyField.editor) replyField.editor.forceActiveFocus()
        }
    }

    Label {
        id: replyFailed
        //% "Not sent: phone not connected"
        text: qsTrId("id-reply-failed") + localeManager.changesObserver
        color: "#ff6060"
        font.pixelSize: Dims.l(6)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Dims.h(12)
        visible: false
        z: 100
    }

    Component {
        id: snoozeLayer

        Item {
            id: snoozeLayerContent
            property var pop
            property int depth

            PageHeader {
                id: title
                //% "Snooze"
                text: qsTrId("id-snooze")
            }

            Grid {
                anchors.fill: parent
                columns: 2
                spacing: Dims.l(8)
                anchors.margins: Dims.l(20)

                NotificationButton {
                    //% "m"
                    text: "10" + qsTrId("id-minute-abbrev") + localeManager.changesObserver
                    onClicked: {
                        if(snoozer.snooze(notification, 10))
                            notification.removeRequested()
                    }
                    width: Dims.l(26)
                    height: width
                }

                NotificationButton {
                    //% "m"
                    text: "30" + qsTrId("id-minute-abbrev") + localeManager.changesObserver
                    onClicked: {
                        if(snoozer.snooze(notification, 30))
                            notification.removeRequested()
                    }
                    width: Dims.l(26)
                    height: width
                }

                NotificationButton {
                    //% "h"
                    text: "1" + qsTrId("id-hour-abbrev") + localeManager.changesObserver
                    onClicked: {
                        if(snoozer.snooze(notification, 60))
                            notification.removeRequested()
                    }
                    width: Dims.l(26)
                    height: width
                }

                NotificationButton {
                    //% "h"
                    text: "3" + qsTrId("id-hour-abbrev") + localeManager.changesObserver
                    onClicked: {
                        if(snoozer.snooze(notification, 180))
                            notification.removeRequested()
                    }
                    width: Dims.l(26)
                    height: width
                }
            }
        }
    }

    Row {
        visible: layerStack.layers.length === 0
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Dims.h(3)
        anchors.horizontalCenter: parent.horizontalCenter

        Icon {
            name: {
                if(notification==null)
                    return "";

                function noicon(str) {
                    return str === "" || str === null || str === undefined;
                }
                // icon for asteroid internal, appIcon for notifications from android
                if(noicon(notification.icon) && noicon(notification.appIcon))
                    return "ios-mail-outline";
                if(noicon(notification.icon) && !noicon(notification.appIcon))
                    return notification.appIcon;
                if(!noicon(notification.icon) && noicon(notification.appIcon))
                    return notification.icon;

                // prefer asteroid internal
                return notification.icon;
            }
            height: timestamp.height
            width: height
        }

        Label {
            id: timestamp
            color: "#b0b0b0"
            text: timestampStr
            font.pixelSize: Dims.l(6)
        }
    }

    Indicator { id: leftIndicator; edge: Qt.LeftEdge }
}
