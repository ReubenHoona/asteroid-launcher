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
 * Full screen view of an alarm or timer ringing on the phone: a notification
 * from the phone (asteroid-btsyncd, protocol version 4) of category alarm
 * that rings with the alarm pattern. Its buttons are the phone app's own
 * actions (Snooze, Dismiss, Stop...), run on the phone; the notification
 * (and its vibration) goes when the phone removes it or the user acts on it.
 * The view keeps the display on while it rings, at most ten minutes.
 */
Item {
    id: phoneAlarm
    anchors.fill: parent

    property QtObject alarm: null
    // Alarms the user acted on or that timed out: not shown again
    property var handled: ({})
    readonly property var labels: alarm ? appActions(alarm) : []
    property string time: ""

    visible: alarm !== null

    function appActions(n) {
        var a = n.hints["x-asteroid-app-actions"]
        return a ? String(a).split("\n") : []
    }

    // A ringing phone alarm that arrived in the last ten minutes: lipstick
    // restores notifications at start, and an old one must not ring again
    function isRinging(n) {
        if (n === null || n === undefined || handled[n.replacesId])
            return false
        if (n.hints["x-asteroid-category"] !== "alarm" || n.hints["x-nemo-feedback"] !== "alarm")
            return false
        return new Date().getTime() - n.timestamp.getTime() < 600000
    }

    function newest(except) {
        for (var i = 0; i < alarmModel.itemCount; i++) {
            var n = alarmModel.get(i)
            if (n !== except && isRinging(n))
                return n
        }
        return null
    }

    function show(n) {
        alarm = n
        updateTime()
        displayOn()
        giveUp.restart()
    }

    function next(done) {
        if (done !== null)
            handled[done.replacesId] = true
        var n = newest(done)
        alarm = null
        if (n !== null)
            show(n)
    }

    function act(index) {
        var n = alarm
        next(n)
        // Lipstick reports it to asteroid-btsyncd, which runs the action on
        // the phone; the notification then closes
        n.actionInvoked("app-" + index)
    }

    function dismiss() {
        var n = alarm
        next(n)
        n.removeRequested()
    }

    function updateTime() {
        time = Qt.formatTime(new Date(), Locale.ShortFormat)
    }

    onAlarmChanged: if (alarm === null) displayRelease()

    // mce keeps the display on for at most 30 s per request: renewed
    function displayOn() {
        mce.typedCall("notification_begin_req",
                      [{ "type": "s", "value": "asteroid-phone-alarm" },
                       { "type": "i", "value": 30000 },
                       { "type": "i", "value": 5000 }],
                      function () {},
                      function (error, message) { console.log("PhoneAlarm: display on:", error, message) })
    }

    function displayRelease() {
        mce.typedCall("notification_end_req",
                      [{ "type": "s", "value": "asteroid-phone-alarm" },
                       { "type": "i", "value": 1000 }])
    }

    NotificationListModel {
        id: alarmModel
        onItemAdded: function (item) {
            if (isRinging(item))
                show(item)
        }
        onItemRemoved: function (item) {
            if (item === alarm)
                next(alarm)
        }
        onPopulatedChanged: {
            var n = newest(null)
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

    Timer {
        interval: 25000
        repeat: true
        running: phoneAlarm.visible
        onTriggered: { displayOn(); updateTime() }
    }

    // A phone that never removes the alarm must not keep the display on
    Timer {
        id: giveUp
        interval: 600000
        onTriggered: next(alarm)
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    // Nothing underneath reacts while the alarm is shown
    MouseArea {
        anchors.fill: parent
    }

    Icon {
        id: alarmIcon
        name: "ios-alarm"
        color: "#FFFFFF"
        width: Dims.w(11)
        height: width
        y: Dims.h(8)
        anchors.horizontalCenter: parent.horizontalCenter

        SequentialAnimation on opacity {
            running: phoneAlarm.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 600 }
            NumberAnimation { to: 1.0; duration: 600 }
        }
    }

    Label {
        id: clock
        text: phoneAlarm.time
        y: Dims.h(20)
        anchors.horizontalCenter: parent.horizontalCenter
        font.pixelSize: Dims.l(14)
    }

    Label {
        id: title
        text: alarm ? alarm.summary : ""
        width: Dims.w(76)
        anchors.top: clock.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: Dims.l(7)
    }

    Label {
        text: alarm && alarm.body !== alarm.summary ? alarm.body : ""
        width: Dims.w(70)
        anchors.top: title.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: Dims.l(5)
        opacity: 0.7
    }

    // The phone app's actions (Snooze, Dismiss...); without any, the
    // watch's dismiss
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Dims.h(10)
        spacing: Dims.h(2)

        Repeater {
            model: phoneAlarm.labels.slice(0, 2)
            delegate: NotificationButton {
                text: modelData
                width: Dims.w(56)
                height: Dims.h(13)
                onClicked: phoneAlarm.act(index)
            }
        }

        NotificationButton {
            //% "Dismiss"
            text: qsTrId("id-dismiss") + localeManager.changesObserver
            width: Dims.w(56)
            height: Dims.h(13)
            visible: phoneAlarm.labels.length === 0
            onClicked: phoneAlarm.dismiss()
        }
    }
}
