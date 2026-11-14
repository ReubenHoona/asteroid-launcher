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
import org.asteroid.controls
import org.asteroid.launcher
import "desktop.js" as Desktop

Item {
    id: actions

    property QtObject panelsGrid
    property QtObject notification
    property QtObject notificationModel

    property bool forbidLeft:  true
    property bool forbidRight: true
    property bool forbidBottom: false

    property string timestampStr: ""

    // The notification stream's detail page: the whole text above the
    // buttons (NotificationText), scrolling
    property bool showText: false

    // A reply went to the phone
    signal replySent()
    // the page on top covers the whole screen (the keyboard): no time over it
    readonly property bool fullScreenLayer: layerStack.currentLayer ? layerStack.currentLayer.fullScreen === true : false
    // How far the page on top is scrolled (the time scrolls away with it): the
    // notification's page or the long press menu; the reply pages keep a fixed
    // title and clip their lists under it
    readonly property real scrolled: {
        var page = layerStack.currentLayer ? layerStack.currentLayer : layerStack.firstPageItem
        return page && page.scrolled !== undefined ? Math.max(0, page.scrolled) : 0
    }

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

    // The phone app's own actions (Archive, Mark as read, Snooze...), by
    // index: asteroid-btsyncd puts their labels in this hint and offers them
    // as the actions "app-0", "app-1"...
    readonly property var appActions: {
        if (notification === undefined || notification === null)
            return []
        var a = notification.hints["x-asteroid-app-actions"]
        return a ? String(a).split("\n").filter(function (l) { return l.length > 0 }) : []
    }

    // Android's suggested replies for this notification, shown first
    readonly property var smartReplies: {
        if (notification === undefined || notification === null)
            return []
        var r = notification.hints["x-asteroid-smart-replies"]
        return r ? String(r).split("\n").filter(function (l) { return l.length > 0 }) : []
    }

    // The phone's own action N: only with the phone there (lipstick closes the
    // card after an action, and a lost one would be gone for nothing): else
    // Wear OS's "Can't finish action. Please check your connection."
    function invokeAppAction(index) {
        whenPhoneConnected(function () { notification.actionInvoked("app-" + index) })
    }

    // Open on phone: the phone opens the app; Wear OS confirms "Opened on your phone"
    function openOnPhone() {
        whenPhoneConnected(function () {
            notification.actionInvoked("open")
            //% "Opened on your phone"
            if (Desktop.confirmation) Desktop.confirmation.show(qsTrId("id-opened-on-phone"))
        })
    }

    function actionFailed() {
        //% "Can't finish action. Please check your connection."
        if (Desktop.confirmation) Desktop.confirmation.show(qsTrId("id-action-error"), false)
    }

    // run(), once asteroid-btsyncd says a phone is connected; else the failure
    function whenPhoneConnected(run) {
        var n = notification
        btsyncd.typedCall("PhoneConnected", [],
                          function (connected) {
                              if (connected && n === notification)
                                  run()
                              else if (!connected)
                                  actionFailed()
                          },
                          actionFailed)
    }

    // How many of the app's actions the first page shows (the rest are
    // under More): two without a reply button, else one
    readonly property int mainAppActions: Math.min(appActions.length, hasPhoneAction("reply") ? 1 : 2)

    // Lipstick reports the press to asteroid-btsyncd, which tells the phone;
    // the notification then closes
    function invokePhoneAction(key) {
        notification.actionInvoked(key)
    }

    // A ringing call: stop the watch vibrating (and the phone ringing when
    // the phone offers it); the call keeps ringing until answered or declined
    function silenceCall() {
        btsyncd.typedCall("Silence", [{ "type": "u", "value": notification.replacesId }])
    }

    // Wear OS shows "Sent" as soon as a reply is chosen and goes back to the
    // conversation; the phone's updated notification (with the reply) then
    // replaces the card. The confirmation lives in the home screen, so it
    // stays even if the card goes meanwhile (a failure shows over it).
    function sendReply(text) {
        var reply = text.trim()
        if (reply.length === 0)
            return
        replyFailed.visible = false
        while (layerStack.layers.length > 0)
            layerStack.pop(layerStack.currentLayer)
        //% "Sent"
        if (Desktop.confirmation) Desktop.confirmation.show(qsTrId("id-reply-sent"))
        var failed = function () {
            replyFailed.visible = true
            //% "Not sent: phone not connected"
            if (Desktop.confirmation) Desktop.confirmation.show(qsTrId("id-reply-failed"), false)
        }
        btsyncd.typedCall("Reply",
                          [{ "type": "u", "value": notification.replacesId },
                           { "type": "s", "value": reply }],
                          function (sent) {
                              if (!sent)
                                  failed()
                              else
                                  actions.replySent()
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

    // Voice replies: asteroid-btsyncd streams the microphone to the phone,
    // which sends the text back (Partial, Final and Error signals)
    property bool voiceAvailable: false
    property QtObject voicePage: null

    function refreshVoice() {
        voice.typedCall("Available", [], function (available) { actions.voiceAvailable = available },
                        function () { actions.voiceAvailable = false })
    }

    function voiceStart(page) {
        voicePage = page
        page.voiceState = "starting"
        page.voiceText = ""
        page.voiceError = ""
        // "" = btsyncd's configured source: the microphone, or a test WAV
        voice.typedCall("Start",
                        [{ "type": "u", "value": notification.replacesId },
                         { "type": "s", "value": "" }],
                        function (sid) {
                            if (page !== voicePage)
                                return
                            if (sid > 0) {
                                if (page.voiceState === "starting")
                                    page.voiceState = "listening"
                            } else if (page.voiceState !== "error") {
                                // btsyncd says why in an Error signal, which the
                                // page may have missed while connecting to it;
                                // most often no phone is connected
                                voice.typedCall("Available", [], function (available) {
                                    if (page === voicePage && page.voiceState !== "error") {
                                        page.voiceError = available ? "" : "no-phone"
                                        page.voiceState = "error"
                                    }
                                })
                            }
                        },
                        function () {
                            if (page === voicePage) {
                                page.voiceError = "no-phone"
                                page.voiceState = "error"
                            }
                        })
    }

    function voiceStop() {
        if (voicePage !== null && voicePage.voiceState === "listening") {
            voicePage.voiceState = "recognising"
            voice.typedCall("Stop", [])
        }
    }

    function voiceCancel() {
        if (voicePage !== null && voicePage.voiceState !== "done" && voicePage.voiceState !== "error")
            voice.typedCall("Cancel", [])
        voicePage = null
    }

    // Calls only; the voice page listens to the signals itself
    DBusInterface {
        id: voice
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/voice"
        iface: "org.asteroidos.btsyncd.Voice"
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
            readonly property real scrolled: actionsFlick.contentY - actionsFlick.originY
            // In the notification stream the page shows the whole
            // notification above its buttons, and scrolls (showText);
            // otherwise the buttons sit in the middle as before
            Flickable {
                id: actionsFlick
                anchors.fill: parent
                contentHeight: Math.max(height, pageColumn.y + pageColumn.height + (actions.showText ? Dims.h(18) : 0))
                interactive: contentHeight > height + 1
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.DragOverBounds

                Column {
                    id: pageColumn
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: actions.showText ? Dims.h(14) : Math.max(0, (actionsFlick.height - height) / 2)
                    width: actions.showText ? Dims.w(76) : column.width
                    spacing: Dims.h(5)

                    NotificationText {
                        id: fullText
                        visible: actions.showText
                        width: parent.width
                        notification: actions.notification
                        timestamp: actions.timestampStr
                        onPictureTapped: (path, size) => actions.showPicture(path, size)
                    }

                    // A message's picture, whole (Wear OS: full width, its own
                    // aspect, rounded); a tap shows it full screen. Not when a
                    // message's bubble shows it already.
                    NotificationPicture {
                        visible: actions.showText && wanted && (!failed || showError)
                                 && fullText.bubblePictures.indexOf(path) < 0
                        width: parent.width
                        notification: actions.notification
                        showError: true
                        tappable: true
                        onTapped: actions.showPicture("", "")
                    }

            Column {
                id: column

                anchors.horizontalCenter: parent.horizontalCenter
                width: Dims.w(55)
                // Four buttons fit the round screen a little smaller
                readonly property bool compact: actions.mainAppActions > 0 && !isCall
                                                && (actions.hasPhoneAction("reply") || actions.mainAppActions > 1)
                readonly property real buttonHeight: compact ? Dims.h(17) : Dims.h(20)
                spacing: compact ? Dims.h(4) : Dims.h(8)

                // A call from the phone: answer or decline it there
                property bool isCall: actions.hasPhoneAction("answer") || actions.hasPhoneAction("reject")

                NotificationButton {
                    //% "End call"
                    text: qsTrId("id-call-end") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: actions.hasPhoneAction("end")
                    onClicked: actions.invokePhoneAction("end")
                }

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
                    //% "Silence"
                    text: qsTrId("id-call-silence") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: column.isCall
                    onClicked: actions.silenceCall()
                }

                // The find-my-watch alert
                NotificationButton {
                    //% "Found it"
                    text: qsTrId("id-found-it") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(20)
                    visible: actions.hasPhoneAction("found")
                    onClicked: actions.invokePhoneAction("found")
                }

                NotificationButton {
                    //% "Reply"
                    text: qsTrId("id-reply") + localeManager.changesObserver
                    width: parent.width
                    height: column.buttonHeight
                    visible: actions.hasPhoneAction("reply") && !column.isCall
                    onClicked: layerStack.push(replyLayer)
                }

                Repeater {
                    model: column.isCall ? 0 : actions.mainAppActions
                    delegate: NotificationButton {
                        text: actions.appActions[index]
                        width: column.width
                        height: column.buttonHeight
                        onClicked: actions.invokeAppAction(index)
                    }
                }

                NotificationButton {
                    //% "Open on phone"
                    text: qsTrId("id-open-on-phone") + localeManager.changesObserver
                    width: parent.width
                    height: column.buttonHeight
                    visible: actions.hasPhoneAction("open") && !actions.hasPhoneAction("reply") && !column.isCall
                             && actions.mainAppActions === 0
                    onClicked: actions.openOnPhone()
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

                // Wear OS's full view ends with "Clear" (fullview_clear)
                NotificationButton {
                    //% "Clear"
                    text: qsTrId("id-notification-clear") + localeManager.changesObserver
                    width: parent.width
                    height: column.buttonHeight
                    visible: !column.isCall
                    onClicked: if (notification.userRemovable) notification.removeRequested()
                }

                NotificationButton {
                    //% "More"
                    text: qsTrId("id-more") + localeManager.changesObserver
                    width: parent.width
                    height: column.buttonHeight
                    visible: actions.fromPhone && !column.isCall && !actions.hasPhoneAction("end")
                             && !actions.hasPhoneAction("found")
                    onClicked: layerStack.push(moreLayer)
                }
            }
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

            // More than fits with the app's own actions: it scrolls
            Flickable {
                id: moreFlick
                anchors.fill: parent
                contentHeight: Math.max(height, moreColumn.height + Dims.h(30))
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                clip: true

            Column {
                id: moreColumn
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(Dims.h(15), (moreFlick.height - height) / 2)
                width: Dims.w(55)
                spacing: Dims.h(5)

                Repeater {
                    model: Math.max(0, actions.appActions.length - actions.mainAppActions)
                    delegate: NotificationButton {
                        text: actions.appActions[actions.mainAppActions + index]
                        width: moreColumn.width
                        height: Dims.h(17)
                        onClicked: actions.invokeAppAction(actions.mainAppActions + index)
                    }
                }

                NotificationButton {
                    //% "Open on phone"
                    text: qsTrId("id-open-on-phone") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(17)
                    visible: actions.hasPhoneAction("open")
                             && (actions.hasPhoneAction("reply") || actions.mainAppActions > 0)
                    onClicked: actions.openOnPhone()
                }

                NotificationButton {
                    //% "Snooze"
                    text: qsTrId("id-snooze") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(17)
                    onClicked: layerStack.push(snoozeLayer)
                }

                // the app's notifications on or off: Wear OS's long press menu
                NotificationButton {
                    //% "Mute app"
                    text: qsTrId("id-mute-app") + localeManager.changesObserver
                    width: parent.width
                    height: Dims.h(17)
                    visible: actions.hasPhoneAction("mute")
                    onClicked: layerStack.push(blockingLayer)
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
    }

    // The app's notifications on or off (as the stream's long press)
    Component {
        id: blockingLayer

        Item {
            property var pop
            property int depth
            readonly property real scrolled: moreMenu.scrolled

            NotificationBlockingMenu {
                id: moreMenu
                anchors.fill: parent
                notification: actions.notification
                belowTimeText: actions.showText
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
                belowTimeText: actions.showText
                //% "Reply"
                text: qsTrId("id-reply")
            }

            Component.onCompleted: actions.refreshVoice()

            ListView {
                anchors.fill: parent
                anchors.topMargin: actions.showText ? Dims.h(28) : Dims.h(20)
                anchors.bottomMargin: Dims.h(10)
                clip: true
                // Wear OS's full view: the voice, keyboard and emoji inputs in a
                // row (full_view_ime_choice; voice only while a phone that
                // recognises speech is connected), then the phone's suggested
                // replies (marked with \u0002) and the canned replies not
                // suggested already
                header: Item {
                    width: ListView.view.width
                    height: Dims.h(22)
                    Row {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -Dims.h(1.5)
                        spacing: Dims.w(4)
                        Repeater {
                            model: (actions.voiceAvailable ? ["speak"] : []).concat(["write", "emoji"])
                            delegate: MouseArea {
                                id: inputButton
                                objectName: "replyInput"
                                readonly property bool isSpeak: modelData === "speak"
                                readonly property bool isWrite: modelData === "write"
                                readonly property bool isEmoji: modelData === "emoji"
                                width: Dims.l(17)
                                height: width
                                onClicked: {
                                    if (isSpeak)
                                        layerStack.push(voiceLayer)
                                    else if (isWrite)
                                        layerStack.push(writeLayer)
                                    else
                                        layerStack.push(emojiLayer)
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: inputButton.pressed ? Qt.tint(Theme.color.surfaceContainer, Qt.alpha(Theme.color.onSurface, Theme.alpha.pressed)) : Theme.color.surfaceContainer
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.55
                                    height: width
                                    name: inputButton.isSpeak ? "ios-mic-outline"
                                          : inputButton.isWrite ? "ios-create-outline" : "ios-happy-outline"
                                }
                            }
                        }
                    }
                }
                model: actions.smartReplies.map(function (r) { return "\u0002" + r })
                       .concat(Array.prototype.filter.call(cannedReplies.value, function (r) { return actions.smartReplies.indexOf(r) < 0 }))
                delegate: MouseArea {
                    id: replyItem
                    readonly property bool isSmart: modelData.charAt(0) === "\u0002"
                    readonly property string replyText: isSmart ? modelData.substring(1) : modelData
                    width: ListView.view.width
                    height: Dims.h(18)
                    onClicked: actions.sendReply(replyItem.replyText)

                    Rectangle {
                        anchors.fill: parent
                        color: "#33ffffff"
                        visible: replyItem.pressed
                    }

                    Icon {
                        id: replyIcon
                        name: replyItem.isSmart ? "ios-flash-outline" : "ios-text-outline"
                        width: Dims.h(12)
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Dims.w(18)
                    }

                    Label {
                        text: replyItem.replyText
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

    // Write a reply: Gboard for Wear OS's full screen keyboard, the reply at
    // its top, Send next to the space bar; a swipe down, a swipe right from
    // the text or the crown goes back to the replies
    Component {
        id: writeLayer

        Item {
            id: writePage
            property var pop
            property int depth
            readonly property bool fullScreen: true

            WearKeyboard {
                id: replyKeyboard
                anchors.fill: parent
                //% "Your reply"
                placeholderText: qsTrId("id-reply-preview")
                actionKey: "send"
                onAccepted: (text) => { actions.sendReply(text) }
                onDismissed: { writePage.pop() }
                Component.onCompleted: {
                    Desktop.keyboard = replyKeyboard
                    forceActiveFocus()
                }
                Component.onDestruction: if (Desktop.keyboard === replyKeyboard) Desktop.keyboard = null
            }
        }
    }

    // Emoji replies (Wear OS's emoji input in the full view): the ones used
    // last first, then the common ones; a tap sends it as the reply
    readonly property var defaultEmoji: ["\u{1F44D}", "❤️", "\u{1F602}", "\u{1F60A}", "\u{1F60D}", "\u{1F64F}",
                                         "\u{1F622}", "\u{1F62E}", "\u{1F389}", "\u{1F44C}", "\u{1F64C}", "\u{1F618}",
                                         "\u{1F60E}", "\u{1F914}", "\u{1F605}", "\u{1F525}", "\u{1F44F}", "\u{1F4AF}",
                                         "✅", "\u{1F44B}", "\u{1F923}", "\u{1F609}", "\u{1F642}", "\u{1F621}"]
    ConfigurationValue {
        id: recentEmoji
        key: "/org/asteroidos/notifications/recent-emoji"
        defaultValue: []
    }
    readonly property int maxRecentEmoji: 8
    function emojiChoices(recent) {
        var list = []
        var r = recent || []
        for (var i = 0; i < r.length && list.length < maxRecentEmoji; i++)
            if (typeof r[i] === "string" && r[i].length > 0 && list.indexOf(r[i]) < 0)
                list.push(r[i])
        for (var j = 0; j < defaultEmoji.length; j++)
            if (list.indexOf(defaultEmoji[j]) < 0)
                list.push(defaultEmoji[j])
        return list
    }
    function sendEmoji(e) {
        var recent = [e]
        var old = recentEmoji.value || []
        for (var i = 0; i < old.length && recent.length < maxRecentEmoji; i++)
            if (old[i] !== e)
                recent.push(old[i])
        recentEmoji.value = recent
        actions.sendReply(e)
    }

    Component {
        id: emojiLayer

        Item {
            id: emojiPage
            property var pop
            property int depth

            PageHeader {
                belowTimeText: actions.showText
                //% "Emoji"
                text: qsTrId("id-emoji-title")
            }

            GridView {
                id: emojiGrid
                objectName: "emojiGrid"
                readonly property int columns: 4
                anchors.top: parent.top
                anchors.topMargin: actions.showText ? Dims.h(28) : Dims.h(20)
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: cellWidth * columns
                cellWidth: Dims.l(17)
                cellHeight: Dims.l(17)
                bottomMargin: Dims.h(14)
                clip: true
                boundsBehavior: Flickable.DragOverBounds
                model: actions.emojiChoices(recentEmoji.value)
                delegate: MouseArea {
                    id: emojiCell
                    readonly property string emoji: modelData
                    width: emojiGrid.cellWidth
                    height: emojiGrid.cellHeight
                    onClicked: actions.sendEmoji(emojiCell.emoji)

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.9
                        height: width
                        radius: width / 2
                        color: emojiCell.pressed ? Qt.tint(Theme.color.surfaceContainer, Qt.alpha(Theme.color.onSurface, Theme.alpha.pressed)) : Theme.color.surfaceContainer
                    }
                    Label {
                        anchors.centerIn: parent
                        text: emojiCell.emoji
                        font.pixelSize: Dims.l(9)
                    }
                }
            }
        }
    }

    // A picture full screen: the notification's (path ""), or a message's
    property string viewerPath: ""
    property string viewerSize: ""
    function showPicture(path, size) {
        viewerPath = path
        viewerSize = size
        layerStack.push(pictureLayer)
    }

    // A message's picture full screen, as large as the round screen shows all
    // of it; a tap, a swipe right or the crown goes back to the notification
    Component {
        id: pictureLayer

        Item {
            id: pictureViewer
            property var pop
            property int depth
            readonly property bool fullScreen: true

            function close() { pictureViewer.pop() }

            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }

            NotificationPicture {
                id: fullPicture
                // the largest rectangle of the picture's aspect in the circle
                readonly property real diameter: Math.min(pictureViewer.width, pictureViewer.height) * 0.98
                width: Math.round(diameter / Math.sqrt(1 + aspect * aspect))
                maxHeight: width * aspect
                anchors.centerIn: parent
                radius: Dims.l(4)
                notification: actions.notification
                picturePath: actions.viewerPath
                pictureSize: actions.viewerSize
                showError: true
            }

            TapHandler { onTapped: pictureViewer.close() }

            Component.onCompleted: Desktop.pictureViewer = pictureViewer
            Component.onDestruction: if (Desktop.pictureViewer === pictureViewer) Desktop.pictureViewer = null
        }
    }

    // The guiding texts of stock's voice input: "Initializing…", then "Speak now" until the
    // first word, then "Listening…"; "Didn't catch that. Try speaking again" on no match
    function voiceStatus(state, code, heard) {
        if (state === "starting")
            //% "Initializing…"
            return qsTrId("id-voice-starting")
        if (state === "listening" && !heard)
            //% "Speak now"
            return qsTrId("id-voice-speak-now")
        if (state === "listening")
            //% "Listening…"
            return qsTrId("id-voice-listening")
        if (state === "recognising")
            //% "Recognising…"
            return qsTrId("id-voice-recognising")
        if (state === "done")
            //% "Send this reply?"
            return qsTrId("id-voice-done")
        if (code === "no-phone" || code === "disconnected")
            //% "Phone not connected"
            return qsTrId("id-voice-no-phone")
        if (code === "no-recognizer")
            //% "No speech recognition on the phone"
            return qsTrId("id-voice-no-recognizer")
        if (code === "language")
            //% "Speech language not installed on the phone"
            return qsTrId("id-voice-language")
        if (code === "permission")
            //% "Allow the microphone for Gadgetbridge on the phone"
            return qsTrId("id-voice-permission")
        if (code === "no-match")
            //% "Didn't catch that. Try speaking again"
            return qsTrId("id-voice-no-match")
        if (code === "busy")
            //% "The phone is busy, try again"
            return qsTrId("id-voice-busy")
        if (code === "timeout")
            //% "No answer from the phone"
            return qsTrId("id-voice-timeout")
        if (code === "source")
            //% "Microphone not available"
            return qsTrId("id-voice-source")
        //% "Speech recognition failed"
        return qsTrId("id-voice-failed")
    }

    // Speak a reply: live text while the phone recognises it, then send or cancel
    Component {
        id: voiceLayer

        Item {
            id: vpage
            property var pop
            property int depth
            // starting | listening | recognising | done | error
            property string voiceState: "starting"
            property string voiceText: ""
            property string voiceError: ""
            readonly property bool failed: voiceState === "error"

            Component.onCompleted: actions.voiceStart(vpage)
            Component.onDestruction: if (actions.voicePage === vpage) actions.voiceCancel()

            // btsyncd's Partial(s), Final(s) and Error(s), for this page only
            // (one listener, not one per notification). Nemo.DBus calls
            // "rc" + the signal name; the parameters must be typed: Qt 6
            // cannot pass the signal's QString to an untyped (QVariant) one
            DBusInterface {
                bus: DBus.SessionBus
                service: "org.asteroidos.btsyncd"
                path: "/org/asteroidos/btsyncd/voice"
                iface: "org.asteroidos.btsyncd.Voice"
                signalsEnabled: true

                function rcPartial(text: string) {
                    if (actions.voicePage === vpage && (vpage.voiceState === "listening"
                                                            || vpage.voiceState === "recognising"
                                                            || vpage.voiceState === "starting"))
                        vpage.voiceText = text
                }
                function rcFinal(text: string) {
                    if (actions.voicePage === vpage) {
                        vpage.voiceText = text
                        vpage.voiceState = "done"
                    }
                }
                function rcError(code: string) {
                    if (actions.voicePage === vpage && vpage.voiceState !== "done") {
                        vpage.voiceError = code
                        vpage.voiceState = "error"
                    }
                }
            }

            PageHeader {
                belowTimeText: actions.showText
                //% "Speak"
                text: qsTrId("id-voice-title")
            }

            Icon {
                id: micIcon
                name: vpage.failed ? "ios-mic-off-outline" : "ios-mic"
                width: Dims.w(14)
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: actions.showText ? Dims.h(28) : Dims.h(21)
                color: vpage.failed ? Theme.color.error : "#ffffff"

                SequentialAnimation on opacity {
                    running: vpage.voiceState === "listening"
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                }
            }

            Label {
                id: statusLabel
                anchors.top: micIcon.bottom
                anchors.topMargin: Dims.h(2)
                anchors.horizontalCenter: parent.horizontalCenter
                width: Dims.w(70)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: vpage.failed ? Theme.color.error : "#b0b0b0"
                font.pixelSize: Theme.type.bodySmall.pixelSize
                text: actions.voiceStatus(vpage.voiceState, vpage.voiceError, vpage.voiceText) + localeManager.changesObserver
            }

            Label {
                id: voiceTextLabel
                anchors.top: statusLabel.bottom
                anchors.topMargin: Dims.h(3)
                anchors.horizontalCenter: parent.horizontalCenter
                width: Dims.w(76)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                font.pixelSize: Dims.l(8)
                font.styleName: vpage.voiceState === "done" ? "SemiCondensed" : "SemiCondensed Light"
                opacity: vpage.voiceState === "done" ? 1.0 : 0.75
                text: vpage.voiceText
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Dims.h(13)
                spacing: Dims.w(4)

                // Done while listening, Send when the text is in, Retry after an error
                NotificationButton {
                    text: (vpage.voiceState === "done"
                           ? qsTrId("id-reply-send")
                           : vpage.failed
                             //% "Retry"
                             ? qsTrId("id-voice-retry")
                             //% "Done"
                             : qsTrId("id-voice-stop")) + localeManager.changesObserver
                    width: Dims.w(30)
                    height: Dims.h(15)
                    visible: vpage.voiceState === "listening" || vpage.voiceState === "done" || vpage.failed
                    onClicked: {
                        if (vpage.voiceState === "listening")
                            actions.voiceStop()
                        else if (vpage.voiceState === "done")
                            actions.sendReply(vpage.voiceText)
                        else
                            actions.voiceStart(vpage)
                    }
                }

                NotificationButton {
                    //% "Cancel"
                    text: qsTrId("id-voice-cancel") + localeManager.changesObserver
                    width: Dims.w(30)
                    height: Dims.h(15)
                    onClicked: {
                        actions.voiceCancel()
                        layerStack.pop(layerStack.currentLayer)
                    }
                }
            }
        }
    }

    Label {
        id: replyFailed
        //% "Not sent: phone not connected"
        text: qsTrId("id-reply-failed") + localeManager.changesObserver
        color: Theme.color.error
        font.pixelSize: Theme.type.bodySmall.pixelSize
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
                belowTimeText: actions.showText
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
        visible: layerStack.layers.length === 0 && !actions.showText
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
            font.pixelSize: Theme.type.bodySmall.pixelSize
        }
    }

    Indicator { id: leftIndicator; edge: Qt.LeftEdge }
}
