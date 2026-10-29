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
 *
 * A call in progress (a phone notification offering only `end`, which the
 * phone sends once a call is answered) gets the same view without ringing:
 * caller, time in call, End call and Hide. It neither turns the display on
 * nor keeps it on; Hide leaves the notification in the list.
 * Everything else keeps the usual notification preview.
 *
 * With the watch's hands-free link to the phone up (asteroid-btsyncd Calls,
 * oFono), the call is also the phone's Bluetooth call, as on stock Wear OS:
 * Answer answers it on the watch and the call audio comes to the watch;
 * Decline and End call hang up over the link. In call: Mute (the watch's
 * microphone), To phone / To watch (where the call audio plays), the call
 * volume (- and +, and the crown). A call on the link with the audio on the
 * watch gets the in-call view even without the phone's notification.
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
    // The call shown is in progress (not ringing)
    readonly property bool ongoing: (call !== null && isOngoing(call)) || hfpOnly
    // Time in call, refreshed every second while shown
    property string elapsed: ""
    // The display is off: nothing to refresh
    property bool displayOff: false

    // The phone's call on the watch's hands-free link (asteroid-btsyncd
    // CallAudio, see GetCall): answered here, its audio comes to the watch
    property var hfp: ({})
    readonly property bool hfpRinging: hfp.available === true && (hfp.state === "incoming" || hfp.state === "waiting")
    readonly property bool hfpInCall: hfp.available === true && ["active", "held", "dialing", "alerting"].indexOf(hfp.state) >= 0
    readonly property bool audioOnWatch: hfpInCall && hfp.audioOnWatch === true
    // A call on the link whose audio came to the watch, but no phone
    // notification (yet): the in-call view all the same (also once the audio
    // went to the phone, to bring it back), until hidden
    property bool hfpHidden: false
    property bool hfpShown: false
    readonly property bool hfpOnly: call === null && hfpInCall && hfpShown && !hfpHidden

    onAudioOnWatchChanged: if (audioOnWatch) hfpShown = true
    onHfpInCallChanged: if (!hfpInCall) { hfpHidden = false; hfpShown = false }

    visible: call !== null || hfpOnly

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

    // A call in progress from the phone: it offers `end` and is not ringing.
    // Calls last long, so a restored one up to four hours old still counts.
    function isOngoing(n) {
        if (n === null || n === undefined || handled[n.replacesId])
            return false
        if (new Date().getTime() - n.timestamp.getTime() > 4 * 3600000)
            return false
        var a = phoneActions(n)
        return a.indexOf("end") >= 0 && a.indexOf("answer") < 0 && a.indexOf("reject") < 0
    }

    function showOngoing(n) {
        giveUp.stop()
        if (keepOn)
            displayRelease()
        call = n
        silenced = true
        updateElapsed()
    }

    function updateElapsed() {
        if (call === null && !hfpOnly)
            return
        // A call the phone never said was over (the link dropped during
        // the call): do not keep it up, ticking, for ever
        if (call !== null && ongoing && !isOngoing(call)) {
            hide()
            return
        }
        var since = hfpInCall && hfp.activeSince > 0 ? hfp.activeSince : (call !== null ? call.timestamp.getTime() : new Date().getTime())
        var s = Math.max(0, Math.floor((new Date().getTime() - since) / 1000))
        var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60
        s = s % 60
        elapsed = (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s
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
        if (hfpInCall)
            hfpHidden = true
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
        // Over the hands-free link, as stock: answered here, the call audio
        // comes to the watch. The phone's notification action if the link
        // cannot (no call there)
        var method = key === "answer" && hfpRinging ? "Answer" :
                     (key === "reject" && hfpRinging) || (key === "end" && hfpInCall) ? "Hangup" : ""
        if (method !== "") {
            calls.typedCall(method, [],
                            function (done) { if (!done && n !== null) n.actionInvoked(key) },
                            function (error, message) {
                                console.log("IncomingCall:", method, error, message)
                                if (n !== null)
                                    n.actionInvoked(key)
                            })
            return
        }
        // Lipstick reports it to asteroid-btsyncd, which tells the phone;
        // the notification then closes
        if (n !== null)
            n.actionInvoked(key)
    }

    function setMuted(muted) {
        calls.typedCall("SetMuted", [{ "type": "b", "value": muted }])
    }

    function setVolume(volume) {
        volume = Math.max(0, Math.min(100, volume))
        calls.typedCall("SetVolume", [{ "type": "i", "value": volume }])
    }

    function setAudioOnWatch(onWatch) {
        calls.typedCall("SetAudioOnWatch", [{ "type": "b", "value": onWatch }])
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
            else if (isOngoing(item) && (call === null || incomingCall.ongoing))
                showOngoing(item)
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

    DBusInterface {
        id: calls
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/calls"
        iface: "org.asteroidos.btsyncd.Calls"
        signalsEnabled: true

        function rcCallChanged(c) {
            incomingCall.hfp = c
        }

        Component.onCompleted: typedCall("GetCall", [], function (c) { incomingCall.hfp = c })
    }

    Timer {
        interval: 25000
        repeat: true
        running: incomingCall.visible && incomingCall.keepOn
        onTriggered: displayOn()
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: incomingCall.visible && incomingCall.ongoing && !incomingCall.displayOff
        onTriggered: updateElapsed()
    }

    // The crown sets the call volume while the call audio is on the watch
    WheelHandler {
        target: null
        enabled: incomingCall.visible && incomingCall.audioOnWatch
        onWheel: function (event) {
            incomingCall.setVolume(incomingCall.hfp.volume + (event.angleDelta.y > 0 ? 5 : -5))
        }
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
            incomingCall.displayOff = true
            if (incomingCall.visible && incomingCall.keepOn) {
                silence()
                displayRelease()
            }
        }
        function onDisplayOn() { incomingCall.displayOff = false }
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
        text: call ? call.summary : (hfp.name ? hfp.name : (hfp.number ? hfp.number : ""))
        width: Dims.w(76)
        y: Dims.h(21)
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: Dims.l(9)
    }

    Label {
        id: number
        text: call ? (call.body !== call.summary ? call.body : "") : (hfp.name && hfp.number ? hfp.number : "")
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
        text: (ongoing && hfpInCall && !audioOnWatch ?
               //% "Call on phone %1"
               //: %1 is the time in call, e.g. 1:23; the call audio is on the phone
               qsTrId("id-call-on-phone").arg(elapsed) :
               ongoing ?
               //% "In call %1"
               //: %1 is the time in call, e.g. 1:23
               qsTrId("id-call-in-progress").arg(elapsed) :
               silenced ?
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
        height: width + (buttonLabel.text !== "" ? buttonLabel.height + Dims.h(1) : 0)

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
        // three buttons in a call on the hands-free link (Mute, End call,
        // the audio's place), higher, the volume under them
        y: incomingCall.ongoing && incomingCall.hfpInCall ? Dims.h(45) : Dims.h(50)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: incomingCall.ongoing && incomingCall.hfpInCall ? Dims.w(4) : Dims.w(14)

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

        CallButton {
            iconName: incomingCall.hfp.muted ? "ios-mic-off" : "ios-mic"
            fill: incomingCall.hfp.muted ? "#1565C0" : "#444444"
            width: Dims.w(22)
            text: (incomingCall.hfp.muted ?
                   //% "Unmute"
                   qsTrId("id-call-unmute") :
                   //% "Mute"
                   qsTrId("id-call-mute")) + localeManager.changesObserver
            visible: incomingCall.ongoing && incomingCall.audioOnWatch
            onClicked: incomingCall.setMuted(!incomingCall.hfp.muted)
        }

        CallButton {
            iconName: "ios-call"
            fill: "#C62828"
            //% "End call"
            text: qsTrId("id-call-end") + localeManager.changesObserver
            width: incomingCall.ongoing && incomingCall.hfpInCall ? Dims.w(22) : Dims.w(25)
            visible: incomingCall.ongoing && (incomingCall.hasAction("end") || incomingCall.hfpInCall)
            onClicked: incomingCall.act("end")
        }

        CallButton {
            iconName: incomingCall.audioOnWatch ? "ios-phone-portrait" : "ios-watch"
            width: Dims.w(22)
            text: (incomingCall.audioOnWatch ?
                   //% "To phone"
                   //: Moves the call audio from the watch to the phone
                   qsTrId("id-call-to-phone") :
                   //% "To watch"
                   //: Brings the call audio from the phone to the watch
                   qsTrId("id-call-to-watch")) + localeManager.changesObserver
            visible: incomingCall.ongoing && incomingCall.hfpInCall
            onClicked: incomingCall.setAudioOnWatch(!incomingCall.audioOnWatch)
        }
    }

    // The call volume, while the call audio is on the watch
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Dims.h(74)
        spacing: Dims.w(4)
        visible: incomingCall.ongoing && incomingCall.audioOnWatch

        CallButton {
            iconName: "ios-volume-down"
            width: Dims.w(11)
            onClicked: incomingCall.setVolume(incomingCall.hfp.volume - 10)
        }

        Label {
            //% "Volume %1"
            //: %1 is the call volume, 0 to 100
            text: qsTrId("id-call-volume").arg(incomingCall.hfp.volume !== undefined ? incomingCall.hfp.volume : 0) + localeManager.changesObserver
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Dims.l(5)
        }

        CallButton {
            iconName: "ios-volume-up"
            width: Dims.w(11)
            onClicked: incomingCall.setVolume(incomingCall.hfp.volume + 10)
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

    NotificationButton {
        //% "Hide"
        text: qsTrId("id-call-hide") + localeManager.changesObserver
        width: Dims.w(40)
        // under the volume while the call audio is on the watch
        height: incomingCall.audioOnWatch ? Dims.h(10) : Dims.h(12)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: incomingCall.audioOnWatch ? Dims.h(2) : Dims.h(6)
        visible: incomingCall.ongoing
        onClicked: incomingCall.hide()
    }
}
