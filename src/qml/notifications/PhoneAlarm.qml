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
    // the time shown (AlarmFiring: the system's one time format, no leading zero in 12 h; settings-b-28)
    property date now: new Date()
    readonly property var parts: TimeFormat.timeParts(now)

    /* The phone app's actions sorted into the screen's two buttons: the first that says Snooze (or
     * its words) is the pill, the first that says Stop or Dismiss is the edge button, every other
     * action is a pill of its own above the Snooze pill (alarms-timers-stopwatch-35). */
    function kindOf(label) {
        var l = String(label).toLowerCase()
        if (/snooze|postpone|remind|later|repeat/.test(l))
            return "snooze"
        if (/dismiss|stop|turn off|cancel|clear|done|got it|^ok$/.test(l))
            return "stop"
        return "other"
    }
    function firstOf(kind) {
        for (var i = 0; i < labels.length; i++)
            if (kindOf(labels[i]) === kind)
                return i
        return -1
    }
    readonly property int snoozeIndex: firstOf("snooze")
    readonly property int stopIndex: firstOf("stop")
    readonly property var extras: {
        var out = []
        for (var i = 0; i < labels.length; i++)
            if (i !== snoozeIndex && i !== stopIndex)
                out.push({ index: i, label: labels[i] })
        return out.slice(0, 2)
    }

    // the phone's own title of the alarm when it says more than "Alarm"
    function labelOf(n) {
        if (!n)
            return ""
        var s = String(n.summary)
        return /^(alarm|timer|alarm clock)$/i.test(s.trim()) ? "" : s
    }

    // the Stop button: the phone's Dismiss, else this watch dismisses the card
    function stop() {
        if (stopIndex >= 0)
            act(stopIndex)
        else
            dismiss()
    }

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
        // btsyncd's alarm vibration: eos_phone_alarm (no sound on the watch,
        // the phone rings, as Wear OS), "alarm" from a btsyncd before that
        var feedback = n.hints["x-nemo-feedback"]
        if (n.hints["x-asteroid-category"] !== "alarm" || (feedback !== "eos_phone_alarm" && feedback !== "alarm"))
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
        now = new Date()
    }

    // the ten minute give-up timer ends with the alarm too
    onAlarmChanged: if (alarm === null) {
        giveUp.stop()
        displayRelease()
    }

    // Theater mode (modes.h): only a button turns the screen on, as stock
    // (the alarm still vibrates, and shows once the screen is on)
    readonly property bool screenStaysOff: typeof modes !== "undefined" && modes !== null && modes.theater

    // mce keeps the display on for at most 30 s per request: renewed
    function displayOn() {
        if (screenStaysOff)
            return
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
        color: Theme.color.background
    }

    // Nothing underneath reacts while the alarm is shown
    MouseArea {
        anchors.fill: parent
    }

    // The same screen as a firing alarm of the watch (AlarmFiring: stock's Compose firing screen,
    // event ALARM_FIRE_PHONE_COMPOSE): the curved title at the top, the time, the Snooze pill and
    // the Stop edge button. The pill and the edge button run the phone app's own actions
    // (Snooze, Dismiss...); the other actions it offers come as pills above the Snooze pill.
    CurvedTopText {
        id: arcTitle
        objectName: "phoneAlarmTitle"
        anchors.fill: parent
        //% "Alarm"
        text: qsTrId("id-phonealarm-title") + localeManager.changesObserver
        role: "arcMedium"
        pixelSize: Theme.type.arcMedium.pixelSize
        color: Theme.color.primary
        maxSweep: 120
        topMargin: Theme.dp(3)
        shadow: "transparent"
    }

    readonly property real pillWidth: Theme.dp(Theme.screenWidthDp > 225 ? 173 : 163)
    readonly property real pillHeight: Theme.dp(52)
    readonly property real topSpacer: Theme.dp(23)
    readonly property real stopHeight: Theme.dp(59)
    readonly property real markerTop: Theme.dp(20)
    readonly property alias timeLabel: timeText
    readonly property alias markerLabel: markerText
    readonly property alias snoozePill: snoozeButton
    readonly property alias stopButton: stopEdge
    readonly property alias titleArc: arcTitle
    readonly property alias extraColumn: extraColumn

    // the time: centred between the 23 dp spacer and the pills
    Item {
        id: region
        y: phoneAlarm.topSpacer
        width: parent.width
        height: Math.max(0, extraColumn.y - phoneAlarm.topSpacer)

        Row {
            id: timeRow
            anchors.centerIn: parent
            spacing: Theme.dp(2)
            layoutDirection: phoneAlarm.parts.markerFirst ? Qt.RightToLeft : Qt.LeftToRight

            Label {
                id: timeText
                text: phoneAlarm.parts.time
                color: Theme.color.primary
                font.pixelSize: Math.round(Theme.sp(52))
                font.weight: Theme.weight(550)
                font.letterSpacing: 0
                lineHeightMode: Text.FixedHeight
                lineHeight: Math.round(Theme.sp(50))
                height: lineHeight
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideNone
                clip: false
            }
            Item {
                width: markerText.implicitWidth
                height: timeText.height
                visible: phoneAlarm.parts.marker !== ""
                Label {
                    id: markerText
                    y: phoneAlarm.markerTop
                    text: phoneAlarm.parts.marker
                    role: "arcMedium"
                    color: Theme.color.primary
                    elide: Text.ElideNone
                }
            }
        }

        // the phone's label of the alarm (its title), when it is not just the word
        Label {
            id: labelText
            objectName: "phoneAlarmLabel"
            anchors.top: timeRow.bottom
            anchors.topMargin: Theme.dp(2)
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.7
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            role: "bodySmall"
            color: Theme.color.onSurfaceVariant
            text: phoneAlarm.labelOf(alarm)
            visible: text !== ""
        }
    }

    // the actions that are neither Snooze nor Stop, one pill each
    Column {
        id: extraColumn
        objectName: "phoneAlarmExtras"
        x: (parent.width - width) / 2
        y: snoozeButton.y - height - (extras.length > 0 ? Theme.dp(4) : 0)
        spacing: Theme.dp(4)
        Repeater {
            model: phoneAlarm.extras
            delegate: Button {
                width: phoneAlarm.pillWidth
                height: Theme.dp(44)
                centered: true
                variant: "tonal"
                containerColor: Theme.color.surfaceContainer
                contentColor: Theme.color.onSurface
                text: modelData.label
                onClicked: phoneAlarm.act(modelData.index)
            }
        }
    }

    Button {
        id: snoozeButton
        objectName: "phoneAlarmSnooze"
        visible: phoneAlarm.snoozeIndex >= 0
        width: phoneAlarm.pillWidth
        height: phoneAlarm.pillHeight
        x: (parent.width - width) / 2
        y: stopEdge.y - height
        centered: true
        containerColor: Theme.color.tertiaryDim
        contentColor: Theme.color.onTertiary
        //% "Snooze"
        text: qsTrId("id-alarm-snooze") + localeManager.changesObserver
        onClicked: phoneAlarm.act(phoneAlarm.snoozeIndex)
    }

    EdgeButton {
        id: stopEdge
        objectName: "phoneAlarmStop"
        preferredHeight: phoneAlarm.stopHeight
        containerColor: Theme.color.surfaceContainer
        contentColor: Theme.color.onPrimaryContainer
        //% "Stop"
        text: qsTrId("id-alarm-stop") + localeManager.changesObserver
        // the phone's Stop / Dismiss, else the watch dismisses the card
        onClicked: phoneAlarm.stop()
    }
}
