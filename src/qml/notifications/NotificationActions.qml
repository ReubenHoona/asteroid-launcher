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
import org.asteroid.controls
import org.asteroid.launcher

/*
 * What follows the text of an open notification, as Wear OS CP3A lists it
 * (SysUI koi.java:258-390, kpg.java, kov.java:84-104, grw.java:2245-2424,
 * 8310): no Reply button, Clear, More, Snooze, Dismiss all or Mute app.
 * A swipe on the card clears it, a long press turns the app off (the stream).
 * px at 2 px per dp:
 *  - when the notification takes a reply: 16 px, an input row (120 px tall pill,
 *    surfaceContainer, 12 px side padding, 7 px gaps) with Emoji, Voice and
 *    Keyboard buttons (96 px tall, surfaceContainerHigh at tone 34, icons in
 *    primary; Emoji is left out when the app forbids emoji), 16 px, then the
 *    phone's smart replies, or the canned ones, as 104 px buttons (surfaceContainer,
 *    label primary, labelMedium, grouped corners 52 px outside, 16 px inside, 8 px
 *    apart): three, the rest behind "More"; each scales in from the top centre
 *    with a 50 ms stagger;
 *  - the app's actions, all of them in the app's order: 32 px, then full-width
 *    104 px buttons (primaryDim, onPrimary, labelMedium, centred), 8 px apart;
 *  - Open on phone, last: 24 px (32 px after app actions), a 104 px button
 *    (secondaryContainer, secondary) with the open-on-phone icon and the text at
 *    the start;
 *  - a call's actions (Decline, Answer, End call) and the find-my-watch alert's
 *    "Stop sound" are app actions too (same button).
 * Taps on the input row are debounced 1000 ms. The phone round trip, its result
 * dialogs and the keyboard layers belong to the shared NotificationRemote.
 */
Item {
    id: actions

    property QtObject notification
    // the shared transport and result flow (NotificationRemote)
    property QtObject remote
    // the LayerStack that takes the keyboard layers (the stream's)
    property var layerHost: null
    // the reply row is debounced this long (kip.a(onClick, 1000))
    readonly property int debounceMs: 1000

    implicitHeight: content.height
    height: content.height

    // Actions the phone offers for a notification it sent (asteroid-btsyncd puts them
    // in this hint): reply, open, mute, answer, reject, end, found
    readonly property var phoneActions: {
        if (notification === undefined || notification === null)
            return []
        var a = notification.hints["x-asteroid-phone-actions"]
        return a ? String(a).split(",") : []
    }
    function hasPhoneAction(key) {
        return phoneActions.indexOf(key) >= 0
    }
    readonly property bool isCall: hasPhoneAction("answer") || hasPhoneAction("reject") || hasPhoneAction("end")
    readonly property bool isFind: hasPhoneAction("found")
    // the call's and the alert's buttons, in the phone's order: Decline, Answer; End call; Stop sound
    readonly property var callActions: {
        var list = []
        if (hasPhoneAction("reject"))
            list.push({ key: "reject",
                        //% "Decline"
                        label: qsTrId("id-call-decline") })
        if (hasPhoneAction("answer"))
            list.push({ key: "answer",
                        //% "Answer"
                        label: qsTrId("id-call-answer") })
        if (hasPhoneAction("end"))
            list.push({ key: "end",
                        //% "End call"
                        label: qsTrId("id-call-end") })
        if (hasPhoneAction("found"))
            list.push({ key: "found",
                        //% "Stop sound"
                        label: qsTrId("id-stop-sound") })
        return list
    }

    // The phone app's own actions (Archive, Mark as read...), by index: asteroid-btsyncd
    // puts their labels in this hint and offers them as the actions "app-0", "app-1"...
    readonly property var appActions: {
        if (notification === undefined || notification === null)
            return []
        var a = notification.hints["x-asteroid-app-actions"]
        return a ? String(a).split("\n").filter(function (l) { return l.length > 0 }) : []
    }

    // Android's suggested replies for this notification
    readonly property var smartReplies: {
        if (notification === undefined || notification === null)
            return []
        var r = notification.hints["x-asteroid-smart-replies"]
        return r ? String(r).split("\n").filter(function (l) { return l.length > 0 }) : []
    }

    // the app forbids emoji in the reply (x-asteroid-no-emoji): no Emoji button
    readonly property bool noEmoji: {
        if (notification === undefined || notification === null)
            return false
        var h = notification.hints["x-asteroid-no-emoji"]
        return h === true || String(h) === "true"
    }

    readonly property bool takesReply: hasPhoneAction("reply") && !isCall

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
    // the phone's suggestions; none: the canned replies (stock's basic replies)
    readonly property var replyChoices: smartReplies.length > 0 ? smartReplies
                                                                : Array.prototype.slice.call(cannedReplies.value)
    readonly property int repliesShown: 3
    property bool moreReplies: false

    // the colour of the input buttons: surfaceContainerHigh re-toned to tone 34
    // (hca.s(color, 34f), hca.java:3111): the colour's lightness L* set to 34, hue and
    // chroma kept (its linear RGB scaled to the luminance of that tone)
    function toneColor(c, tone) {
        function lin(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
        function enc(v) {
            v = Math.max(0, Math.min(1, v))
            return v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055
        }
        var r = lin(c.r), g = lin(c.g), b = lin(c.b)
        var y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        var t = (tone + 16) / 116
        var target = tone > 8 ? t * t * t : tone / 903.2962963
        var k = y > 0 ? target / y : 1
        return Qt.rgba(enc(r * k), enc(g * k), enc(b * k), 1)
    }
    readonly property color inputContainer: toneColor(Theme.color.surfaceContainerHigh, 34)

    /* ---- stock geometry (px) ---------------------------------------------- */
    readonly property real rowHeight: Theme.dp(60)
    readonly property real rowSide: Theme.dp(6)
    readonly property real rowGap: Theme.dp(3.5)
    readonly property real inputHeight: Theme.dp(48)
    // 8, 16, 24 and 32 px
    readonly property real space8: Theme.dp(4)
    readonly property real space16: Theme.dp(8)
    readonly property real space24: Theme.dp(12)
    readonly property real space32: Theme.dp(16)
    readonly property real outerRadius: Theme.shape.large
    readonly property real innerRadius: Theme.shape.small * 1     // 8 dp: 16 px

    // the debounce of the input row
    property double lastInput: 0
    function inputAllowed() {
        var now = Date.now()
        if (now - lastInput < debounceMs)
            return false
        lastInput = now
        return true
    }
    function emojiPicked() { if (inputAllowed()) openKeyboardPage("emoji") }
    function keyboardPicked() { if (inputAllowed()) openKeyboardPage("") }
    function voicePicked() {
        if (inputAllowed() && remote)
            remote.openVoice(layerHost, notification.replacesId, !noEmoji)
    }
    function openKeyboardPage(page) {
        if (remote)
            remote.openKeyboard(layerHost, notification.replacesId, page, !noEmoji)
    }

    function sendChoice(text) {
        if (remote && notification)
            remote.reply(notification.replacesId, text)
    }

    // the card's contents below the text
    Column {
        id: content
        width: parent.width

        // a call's, or the alert's, buttons
        Column {
            id: callBlock
            objectName: "callBlock"
            width: parent.width
            // (sizes follow the conditions, not `visible`: that is false for the whole
            // card while it is still closed, and the card needs its height to open)
            topPadding: actions.callActions.length > 0 ? actions.space32 : 0
            spacing: actions.space8
            visible: actions.callActions.length > 0
            Repeater {
                model: actions.callActions
                delegate: Button {
                    objectName: "callAction"
                    width: callBlock.width
                    centered: true
                    radius: actions.outerRadius
                    containerColor: Theme.color.primaryDim
                    contentColor: Theme.color.onPrimary
                    text: modelData.label + localeManager.changesObserver
                    onClicked: if (actions.remote) actions.remote.invokeDirect(actions.notification, modelData.key)
                }
            }
        }

        // the input row
        Item {
            id: replyBlock
            objectName: "replyBlock"
            width: parent.width
            visible: actions.takesReply
            height: actions.takesReply ? actions.space16 + replyRow.height : 0

            Rectangle {
                id: replyRow
                objectName: "replyRow"
                y: actions.space16
                width: parent.width
                height: actions.rowHeight
                radius: height / 2
                color: Theme.color.surfaceContainer

                Row {
                    x: actions.rowSide
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: actions.rowGap
                    readonly property int count: actions.noEmoji ? 2 : 3
                    readonly property real buttonWidth: (replyRow.width - 2 * actions.rowSide - (count - 1) * actions.rowGap) / count

                    NotificationInputButton {
                        objectName: "inputEmoji"
                        visible: !actions.noEmoji
                        width: visible ? parent.buttonWidth : 0
                        containerColor: actions.inputContainer
                        icon: "ios-happy-outline"
                        //% "Emoji input"
                        description: qsTrId("id-input-emoji")
                        onTriggered: actions.emojiPicked()
                    }
                    NotificationInputButton {
                        objectName: "inputVoice"
                        width: parent.buttonWidth
                        containerColor: actions.inputContainer
                        icon: "ios-mic-outline"
                        //% "Voice input"
                        description: qsTrId("id-input-voice")
                        onTriggered: actions.voicePicked()
                    }
                    NotificationInputButton {
                        objectName: "inputKeyboard"
                        width: parent.buttonWidth
                        containerColor: actions.inputContainer
                        icon: "ios-keypad-outline"
                        //% "Keyboard input"
                        description: qsTrId("id-input-keyboard")
                        onTriggered: actions.keyboardPicked()
                    }
                }
            }
        }

        // the replies
        Column {
            id: replyList
            objectName: "replyList"
            width: parent.width
            readonly property bool wanted: actions.takesReply && actions.replyChoices.length > 0
            visible: wanted
            topPadding: wanted ? actions.space16 : 0
            spacing: actions.space8

            Repeater {
                id: replyRepeater
                model: actions.moreReplies ? actions.replyChoices.length
                                           : Math.min(actions.repliesShown, actions.replyChoices.length)
                delegate: Button {
                    id: replyButton
                    objectName: "smartReply"
                    readonly property int count: replyRepeater.count
                    readonly property bool first: index === 0
                    readonly property bool last: index === count - 1
                    width: replyList.width
                    centered: true
                    containerColor: Theme.color.surfaceContainer
                    contentColor: Theme.color.primary
                    text: actions.replyChoices[index]
                    Component.onCompleted: {
                        container.topLeftRadius = Qt.binding(function () { return first ? actions.outerRadius : actions.innerRadius })
                        container.topRightRadius = Qt.binding(function () { return first ? actions.outerRadius : actions.innerRadius })
                        container.bottomLeftRadius = Qt.binding(function () { return last ? actions.outerRadius : actions.innerRadius })
                        container.bottomRightRadius = Qt.binding(function () { return last ? actions.outerRadius : actions.innerRadius })
                    }
                    onClicked: actions.sendChoice(actions.replyChoices[index])

                    // scales in from the top centre, 50 ms later for each
                    property real entrance: Motion.reduceMotion ? 1 : 0
                    opacity: Math.max(0, Math.min(1, entrance))
                    transform: Scale {
                        origin.x: replyButton.width / 2
                        origin.y: 0
                        xScale: replyButton.entrance
                        yScale: replyButton.entrance
                    }
                    WearSpring {
                        id: entranceSpring
                        target: replyButton
                        property: "entrance"
                        stiffness: Motion.standard.defaultSpatial.stiffness
                        dampingRatio: Motion.standard.defaultSpatial.dampingRatio
                    }
                    SequentialAnimation {
                        running: !Motion.reduceMotion
                        PauseAnimation { duration: Motion.duration(50 * (actions.moreReplies ? Math.max(0, index - actions.repliesShown) : index)) }
                        ScriptAction { script: entranceSpring.animateTo(1) }
                    }
                }
            }

            // "More": the rest of the replies (labelSmall and a 26 dp chevron)
            MouseArea {
                id: moreButton
                objectName: "smartMore"
                width: replyList.width
                height: Theme.dp(48)
                visible: !actions.moreReplies && actions.replyChoices.length > actions.repliesShown
                onClicked: actions.moreReplies = true
                Ripple {
                    anchors.fill: parent
                    radius: actions.outerRadius
                    color: Theme.color.primary
                    pressed: moreButton.pressed
                    pressX: moreButton.mouseX
                    pressY: moreButton.mouseY
                }
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.dp(2)
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        //% "More"
                        text: qsTrId("id-more") + localeManager.changesObserver
                        role: "labelSmall"
                        color: Theme.color.primary
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.dp(26)
                        height: width
                        name: "ios-arrow-down"
                        color: Theme.color.primary
                    }
                }
            }
        }

        // the app's own actions, all of them
        Column {
            id: appBlock
            objectName: "appBlock"
            width: parent.width
            readonly property bool wanted: actions.appActions.length > 0 && !actions.isCall
            visible: wanted
            topPadding: wanted ? actions.space32 : 0
            spacing: actions.space8
            Repeater {
                model: actions.isCall ? 0 : actions.appActions
                delegate: Button {
                    objectName: "appAction"
                    width: appBlock.width
                    centered: true
                    radius: actions.outerRadius
                    containerColor: Theme.color.primaryDim
                    contentColor: Theme.color.onPrimary
                    text: modelData
                    onClicked: if (actions.remote) actions.remote.invoke(actions.notification, "app", index)
                }
            }
        }

        // Open on phone, last
        Item {
            id: openBlock
            objectName: "openBlock"
            width: parent.width
            visible: actions.hasPhoneAction("open")
            readonly property bool wanted: actions.hasPhoneAction("open")
            readonly property bool afterActions: appBlock.wanted
            readonly property real lead: afterActions ? actions.space32 : actions.space24
            height: wanted ? lead + openButton.height : 0

            MouseArea {
                id: openButton
                objectName: "openOnPhone"
                y: openBlock.lead
                width: parent.width
                height: Theme.size.button
                // a second tap while the first waits for the phone is ignored (the remote's guard too)
                enabled: {
                    var waiting = actions.remote ? actions.remote.inflightCount : 0
                    return !(waiting > 0 && actions.notification && actions.remote.pending(actions.notification.replacesId))
                }
                Accessible.role: Accessible.Button
                Accessible.name: openLabel.text
                onClicked: if (actions.remote) actions.remote.invoke(actions.notification, "open", -1)

                Rectangle {
                    id: openContainer
                    anchors.fill: parent
                    radius: actions.outerRadius
                    color: Theme.color.secondaryContainer
                    Ripple {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Theme.color.secondary
                        pressed: openButton.pressed
                        pressX: openButton.mouseX
                        pressY: openButton.mouseY
                    }
                }
                Row {
                    x: Theme.space.xl
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space.s
                    NotificationPhoneIcon {
                        id: openIcon
                        anchors.verticalCenter: parent.verticalCenter
                        size: Theme.dp(24)
                        color: Theme.color.secondary
                    }
                    Label {
                        id: openLabel
                        anchors.verticalCenter: parent.verticalCenter
                        width: openButton.width - 2 * Theme.space.xl - openIcon.width - Theme.space.s
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        //% "Open on phone"
                        text: qsTrId("id-open-on-phone") + localeManager.changesObserver
                        role: "labelMedium"
                        color: Theme.color.secondary
                    }
                }
            }
        }
    }
}
