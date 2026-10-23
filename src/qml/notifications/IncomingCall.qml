/*
 * Copyright (C) 2026 Reuben Horner
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
import Nemo.DBus
import org.asteroid.controls
import org.nemomobile.lipstick

/*
 * Full screen view of a call ringing on the phone: a notification from the
 * phone (asteroid-btsyncd) that offers answer or reject. Answer and Decline
 * are reported to the phone like any notification action; Silence stops the
 * watch's vibration and, when the phone offers it, its ringer. The view keeps
 * the display on while the call rings and goes away when the phone removes
 * the notification (answered, declined, missed) or the user acts on it.
 * Everything else keeps the usual notification preview.
 */
Item {
    id: incomingCall
    anchors.fill: parent

    // The call shown, or null
    property QtObject call: null
    property bool silenced: false
    // Display kept on for the call; false once the user turned it off
    property bool keepOn: false
    // Calls the user already acted on or that timed out: not shown again
    property var handled: ({})

    readonly property var callActions: call ? phoneActions(call) : []

    visible: call !== null

    function phoneActions(n) {
        var a = n.hints["x-asteroid-phone-actions"]
        return a ? String(a).split(",") : []
    }

    // A call notification that arrived in the last two minutes: lipstick
    // restores notifications at start, and an old call must not ring again
    function isRinging(n) {
        if (n === null || n === undefined || handled[n.replacesId])
            return false
        if (new Date().getTime() - n.timestamp.getTime() > 120000)
            return false
        var a = phoneActions(n)
        return a.indexOf("answer") >= 0 || a.indexOf("reject") >= 0
    }

    function hasAction(key) {
        return callActions.indexOf(key) >= 0
    }

    // The newest ringing call but `except` (index 0 is the newest)
    function newestCall(except) {
        for (var i = 0; i < notifModel.itemCount; i++) {
            var n = notifModel.get(i)
            if (n !== except && isRinging(n))
                return n
        }
        return null
    }

    function show(n) {
        if (call !== n) {
            call = n
            silenced = n.hints["x-nemo-feedback-suppressed"] === true
        }
        keepOn = true
        displayOn()
        giveUp.restart()
    }

    // Done with the call shown: the next ringing call, if any, from scratch
    function next(done) {
        if (done !== null)
            handled[done.replacesId] = true
        var n = newestCall(done)
        call = null
        if (n !== null)
            show(n)
    }

    function hide() {
        next(call)
    }

    onCallChanged: if (call === null) displayRelease()

    // mce keeps the display on for at most 30 s per request: renew it
    function displayOn() {
        mce.typedCall("notification_begin_req",
                      [{ "type": "s", "value": "asteroid-incoming-call" },
                       { "type": "i", "value": 30000 },
                       { "type": "i", "value": 5000 }],
                      function () {},
                      function (error, message) { console.log("IncomingCall: display on:", error, message) })
    }

    function displayRelease() {
        keepOn = false
        mce.typedCall("notification_end_req",
                      [{ "type": "s", "value": "asteroid-incoming-call" },
                       { "type": "i", "value": 1000 }])
    }

    function act(key) {
        var n = call
        next(n)
        // Lipstick reports it to asteroid-btsyncd, which tells the phone;
        // the notification then closes
        n.actionInvoked(key)
    }

    function silence() {
        if (call === null || silenced)
            return
        silenced = true
        btsyncd.typedCall("Silence", [{ "type": "u", "value": call.replacesId }],
                          function (known) { if (!known) console.log("IncomingCall: btsyncd does not know the call") },
                          function (error, message) { console.log("IncomingCall: Silence:", error, message) })
    }

    NotificationListModel {
        id: notifModel
        onItemAdded: function (item) {
            if (isRinging(item))
                show(item)
        }
        onItemRemoved: function (item) {
            if (item === call)
                hide()
        }
        // The launcher restarted while a call rang
        onPopulatedChanged: {
            var n = newestCall(null)
            if (populated && n !== null)
                show(n)
        }
    }

    DBusInterface {
        id: mce
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
    }

    DBusInterface {
        id: btsyncd
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/notifications"
        iface: "org.asteroidos.btsyncd.Notifications"
    }

    Timer {
        interval: 25000
        repeat: true
        running: incomingCall.visible && incomingCall.keepOn
        onTriggered: displayOn()
    }

    // A phone that never says the call is over must not leave this up
    Timer {
        id: giveUp
        interval: 180000
        onTriggered: hide()
    }

    // The user turned the display off (power key) while it rang: silence the
    // call as on a phone, and let the display stay off
    Connections {
        target: Lipstick.compositor
        function onDisplayOff() {
            if (incomingCall.visible && incomingCall.keepOn) {
                silence()
                displayRelease()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    // Nothing underneath reacts while the call is shown
    MouseArea {
        anchors.fill: parent
    }

    Icon {
        id: callIcon
        name: "ios-call"
        color: "#FFFFFF"
        width: Dims.w(11)
        height: width
        y: Dims.h(8)
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Label {
        id: caller
        text: call ? call.summary : ""
        width: Dims.w(76)
        y: Dims.h(21)
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: Dims.l(9)
    }

    Label {
        id: number
        text: call && call.body !== call.summary ? call.body : ""
        width: Dims.w(70)
        anchors.top: caller.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: Dims.l(6)
        opacity: 0.7
    }

    Label {
        id: callState
        text: (silenced ?
               //% "Silenced"
               qsTrId("id-call-silenced") :
               //% "Incoming call"
               qsTrId("id-call-incoming")) + localeManager.changesObserver
        anchors.top: number.bottom
        anchors.topMargin: Dims.h(1)
        anchors.horizontalCenter: parent.horizontalCenter
        font.pixelSize: Dims.l(6)
        opacity: 0.7
    }

    component CallButton: MouseArea {
        property alias iconName: buttonIcon.name
        property alias text: buttonLabel.text
        property color fill: "#444444"
        width: Dims.w(25)
        height: width + buttonLabel.height + Dims.h(1)

        Rectangle {
            id: circle
            width: parent.width
            height: width
            radius: width / 2
            color: parent.fill
            opacity: parent.pressed ? 0.7 : 1.0
        }

        Icon {
            id: buttonIcon
            anchors.centerIn: circle
            width: circle.width * 0.5
            height: width
            color: "#FFFFFF"
        }

        Label {
            id: buttonLabel
            anchors.top: circle.bottom
            anchors.topMargin: Dims.h(1)
            anchors.horizontalCenter: circle.horizontalCenter
            font.pixelSize: Dims.l(5)
        }
    }

    Row {
        y: Dims.h(50)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Dims.w(14)

        CallButton {
            iconName: "ios-close"
            fill: "#C62828"
            //% "Decline"
            text: qsTrId("id-call-decline") + localeManager.changesObserver
            visible: incomingCall.hasAction("reject")
            onClicked: incomingCall.act("reject")
        }

        CallButton {
            iconName: "ios-call"
            fill: "#2E7D32"
            //% "Answer"
            text: qsTrId("id-call-answer") + localeManager.changesObserver
            visible: incomingCall.hasAction("answer")
            onClicked: incomingCall.act("answer")
        }
    }

    NotificationButton {
        //% "Silence"
        text: qsTrId("id-call-silence") + localeManager.changesObserver
        width: Dims.w(40)
        height: Dims.h(12)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Dims.h(6)
        visible: !incomingCall.silenced
        onClicked: incomingCall.silence()
    }
}
