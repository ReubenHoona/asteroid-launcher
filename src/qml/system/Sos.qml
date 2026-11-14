/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import Nemo.Configuration
import org.asteroid.controls
import "system.js" as Sys

/* Emergency SOS (apps-misc-07): five crown presses (KeyRouter counts them
 * with system.js sosPress: each at most 500 ms after the one before, the
 * five over 600 ms, then 3000 ms in which presses do not count) start it.
 * Stock WearEmergencyActionsHelper / the Safety app's emergency_alert_
 * activity: 500 ms of vibration, the quiet modes and touch lock off
 * (KeyRouter does that, `triggered`), a black screen with a ring counting
 * down 5 s (twice that with a touch-exploring screen reader), the caption
 * "Calling" 31 dp from the top, the number 12 dp below it and a round X to
 * cancel 19 dp from the bottom; at zero the phone dials the local
 * emergency number (Gadgetbridge, the assistant's relay: {a: "dial", nm, dry};
 * NEEDS the "dial" action in Gadgetbridge: until its ACTIONS list has it the
 * relay answers old-app and the screen says the phone is not connected) and
 * the screen says "Calling <number>...". With no phone link: "Your watch
 * is not connected to your phone".
 *
 * No timer runs until it is triggered; the ring is one animation and the
 * screen hold is the countdown itself. The dconf key
 * /org/asteroidos/safety/sos-enabled (default true, stock
 * config_defaultEmergencyGestureEnabled) turns the gesture off;
 * /org/asteroidos/safety/emergency-number overrides the number of the
 * region; /org/asteroidos/assistant/call-dry-run asks Gadgetbridge not to
 * dial (every test). Instantiated by OverlayArbiter above the power menu. */
Item {
    id: sos
    objectName: "sos"
    anchors.fill: parent

    /* idle, countdown, calling, failed */
    property string phase: "idle"
    readonly property bool shown: phase !== "idle"
    readonly property bool gestureEnabled: enabledKey.value !== false && enabledKey.value !== "false"
    property bool screenReaderExploring: false
    property string number: ""
    // the text of the failed phase
    property string failure: ""
    property real remaining: 1
    readonly property alias relay: relay
    readonly property alias ring: ringFill
    readonly property alias cancelButton: cancelButton

    // the gesture was recognised: the quiet modes and touch lock go off, the display wakes
    signal triggered()
    // the countdown ended and the call was asked of the phone
    signal dialRequested(string number, bool dry)

    ConfigurationValue { id: enabledKey; key: "/org/asteroidos/safety/sos-enabled"; defaultValue: true }
    ConfigurationValue { id: numberKey; key: "/org/asteroidos/safety/emergency-number"; defaultValue: "" }
    ConfigurationValue { id: dryRun; key: "/org/asteroidos/assistant/call-dry-run"; defaultValue: false }

    /* The gesture was made (the fifth press). */
    function trigger() {
        if (!gestureEnabled || phase !== "idle")
            return
        number = Sys.emergencyNumber(Qt.locale().name, numberKey.value)
        failure = ""
        remaining = 1
        phase = "countdown"
        triggered()
        // the 500 ms vibration (stock config_mashPressPowerButtonVibrateDurationMillis)
        Haptics.play("eos_sos")
        countdown.duration = Sys.sosCountdownMs(screenReaderExploring)
        countdown.restart()
    }

    /* The X: stop the countdown, or hang up a call just placed. */
    function cancel() {
        if (phase === "idle")
            return
        countdown.stop()
        doneTimer.stop()
        waitTimer.stop()
        if (phase === "calling")
            act({ a: "hangup" }, function () {})
        phase = "idle"
        remaining = 1
    }

    NumberAnimation {
        id: countdown
        target: sos
        property: "remaining"
        from: 1
        to: 0
        easing.type: Easing.Linear
        onFinished: if (sos.phase === "countdown") sos.dial()
    }

    // after the call was placed or failed the screen goes by itself
    Timer { id: doneTimer; interval: 3000; onTriggered: sos.phase = "idle" }
    // no answer from the phone for this long is a failure
    Timer { id: waitTimer; interval: 10000; onTriggered: sos.dialResult({ ok: false, er: "timeout" }) }

    /* The countdown ended: the phone dials. */
    function dial() {
        phase = "calling"
        var dry = dryRun.value === true || dryRun.value === "true"
        dialRequested(number, dry)
        waitTimer.restart()
        act({ a: "dial", nm: number, dry: dry }, dialResult)
    }

    function dialResult(r) {
        if (phase !== "calling")
            return
        waitTimer.stop()
        if (r && r.ok) {
            doneTimer.restart()
            return
        }
        var er = r ? r.er : ""
        if (er === "no-phone" || er === "disconnected" || er === "old-app" || er === "timeout")
            //% "Your watch is not connected to your phone"
            failure = qsTrId("id-sos-no-phone") + localeManager.changesObserver
        else
            //% "Couldn't call"
            failure = qsTrId("id-sos-failed") + localeManager.changesObserver
        phase = "failed"
        doneTimer.restart()
    }

    /* The assistant relay of asteroid-btsyncd, as AssistantActions.act(): asks which
     * actions the phone has, then sends one and waits for its result signal. */
    property var _waits: ({})
    property int _seq: 0
    DBusInterface {
        id: relay
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/assistant"
        iface: "org.asteroidos.btsyncd.Assistant"
        signalsEnabled: true
        function rcActResult(id: int, json: string) { sos.actResult(id, json) }
    }
    function act(json, cb) {
        relay.typedCall("Actions", [], function (list) {
            if (list && list.indexOf(json.a) >= 0) {
                var id = ++_seq
                var w = _waits
                w[id] = cb
                _waits = w
                relay.typedCall("Act", [{ "type": "u", "value": id }, { "type": "s", "value": JSON.stringify(json) }],
                    function (ok) { if (!ok) sos.actResult(id, JSON.stringify({ ok: false, er: "no-phone" })) },
                    function () { sos.actResult(id, JSON.stringify({ ok: false, er: "no-phone" })) })
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
        var r
        try { r = JSON.parse(json) } catch (e) { r = { ok: false, er: "failed" } }
        cb(r)
    }

    Rectangle {
        anchors.fill: parent
        visible: sos.shown
        color: "#000000"
        // nothing under the screen takes a touch
        MouseArea { anchors.fill: parent }

        // the ring: 5 dp, #ee675c on #532420, emptying clockwise from the top
        ProgressArc {
            anchors.fill: parent
            visible: sos.phase === "countdown"
            strokeWidth: Sys.SOS_RING_WIDTH
            color: Sys.SOS_COLOR_TRACK
            startAngle: 270
            sweepAngle: 360
        }
        ProgressArc {
            id: ringFill
            objectName: "sosRing"
            anchors.fill: parent
            visible: sos.phase === "countdown"
            strokeWidth: Sys.SOS_RING_WIDTH
            color: Sys.SOS_COLOR_MAIN
            startAngle: 270
            sweepAngle: 360 * sos.remaining
        }

        Label {
            id: caption
            objectName: "sosCaption"
            visible: sos.phase !== "failed"
            width: parent.width - 2 * Math.round(0.1 * parent.width)
            x: (parent.width - width) / 2
            y: Sys.SOS_TITLE_TOP
            horizontalAlignment: Text.AlignHCenter
            role: "titleMedium"
            color: "#ffffff"
            text: sos.phase === "calling"
                  //% "Calling %1..."
                  ? qsTrId("id-sos-calling-number").arg(sos.number)
                  //% "Calling"
                  : qsTrId("id-sos-calling")
        }
        Label {
            id: numberLabel
            objectName: "sosNumber"
            visible: sos.phase === "countdown"
            width: caption.width
            x: caption.x
            y: caption.y + caption.height + Sys.SOS_NUMBER_GAP
            horizontalAlignment: Text.AlignHCenter
            role: "displaySmall"
            color: "#ffffff"
            elide: Text.ElideRight
            maximumLineCount: 1
            text: sos.number
        }
        Label {
            id: failureLabel
            objectName: "sosFailure"
            visible: sos.phase === "failed"
            width: parent.width - 2 * Math.round(0.12 * parent.width)
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            role: "titleMedium"
            color: "#ffffff"
            text: sos.failure
        }

        // the X: a round button, #ee675c with the icon in #303133
        Rectangle {
            id: cancelButton
            objectName: "sosCancel"
            visible: sos.phase === "countdown" || sos.phase === "calling"
            width: Theme.size.iconButton
            height: width
            radius: width / 2
            color: Sys.SOS_COLOR_MAIN
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - Sys.SOS_CANCEL_BOTTOM - height
            Accessible.role: Accessible.Button
            //% "Cancel"
            Accessible.name: qsTrId("id-sos-cancel")
            Icon {
                anchors.centerIn: parent
                width: Theme.size.icon
                height: width
                name: "ios-close"
                color: Sys.SOS_COLOR_ICON
            }
            MouseArea {
                anchors.fill: parent
                onClicked: sos.cancel()
            }
        }
    }
}
