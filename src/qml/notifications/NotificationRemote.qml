/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import org.asteroid.controls
import "desktop.js" as Desktop

/*
 * What an open notification sends to the phone, and what comes back, as Wear OS
 * CP3A does it (the RPC of RemoteActionRpc.java:62-128, RemoteActionSuccessActivity,
 * fcm.java:36-55, jlk.java:34-44). One of these serves the stream (and the
 * legacy panel's page); the cards only ask it.
 *  - reply(id, text), invoke(n, "app", i), invoke(n, "open"): an action goes to
 *    the phone (asteroid-btsyncd Reply, or lipstick's action app-N / open) and
 *    a 5000 ms wait starts (a single-shot timer for the nearest deadline; no
 *    periodic timer). Nothing shows before the phone answers.
 *  - the answer is btsyncd's ActionResult(id, kind, index, ok|failed|timeout):
 *    ok shows "Success" for 899 ms (the open on phone dialog, already up, just
 *    ends); failed (no phone, or the phone says no) shows the failure dialog
 *    "Can't finish action" / "Please check your connection" and the reject
 *    haptic; no answer in 5 s shows "Slow connection" / "Check back soon" and
 *    the same haptic.
 *  - a second action on the same notification while one is waiting is ignored
 *    (grw.bg() running-intent set, kip.a(onClick, 1000)).
 *  - an action for a notification that is gone: "Action not completed" /
 *    "Notification is no longer active" (NotificationDismissedDialogActivity).
 *  - the keyboard, emoji and voice layers of a reply (WearKeyboard on its
 *    page) are pushed on the stack the caller names; they live here so that a
 *    card that goes (the phone removed it) does not take its layer with it.
 *  - Voice with no recogniser: the toast "Voice input not available".
 * Battery: nothing runs while no action is on its way; the D-Bus signal is
 * listened to only then.
 */
Item {
    id: remote

    // the stream: is notification id still in the list (else the action is "gone")
    property var isActive: function (id) { return true }
    // how long the phone may take before "Slow connection"
    property int slowMs: 5000
    // "Success" stays this long (RemoteActionSuccessActivity, exk.java:43-66)
    readonly property int successMs: 899

    // the actions waiting for the phone: id -> { kind, index, deadline }
    property var inflight: ({})
    property int inflightCount: 0
    // what was shown last, and how many times (for the tests and diagnostics):
    // "success", "open", "slow", "failed", "gone", "voice"
    property string lastOutcome: ""
    property int outcomes: 0
    signal outcome(string what, int id)

    readonly property QtObject failureDialog: failure
    readonly property QtObject toastItem: toast

    function pending(id) { return inflight[id] !== undefined }

    /* ---- the wait ----------------------------------------------------- */

    function begin(id, kind, index) {
        if (inflight[id] !== undefined)
            return false
        inflight[id] = { kind: kind, index: index, deadline: Date.now() + slowMs }
        inflightCount++
        rearm()
        return true
    }
    function finish(id) {
        var e = inflight[id]
        if (e === undefined)
            return null
        delete inflight[id]
        inflightCount--
        rearm()
        return e
    }
    // the timer runs to the nearest deadline
    function rearm() {
        var next = -1
        for (var k in inflight)
            if (next < 0 || inflight[k].deadline < next)
                next = inflight[k].deadline
        if (next < 0) {
            slowTimer.stop()
            return
        }
        slowTimer.interval = Math.max(1, next - Date.now())
        slowTimer.restart()
    }
    Timer {
        id: slowTimer
        repeat: false
        onTriggered: {
            var now = Date.now() + 5
            var due = []
            for (var k in remote.inflight)
                if (remote.inflight[k].deadline <= now)
                    due.push(Number(k))
            for (var i = 0; i < due.length; i++) {
                remote.finish(due[i])
                remote.showSlow(due[i])
            }
            remote.rearm()
        }
    }

    // btsyncd's word on an action. Nemo.DBus calls "rc" + the signal's name; the
    // parameters are typed (Qt 6 cannot pass the signal's values to a QVariant one)
    DBusInterface {
        id: btsyncd
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/notifications"
        iface: "org.asteroidos.btsyncd.Notifications"
        signalsEnabled: remote.inflightCount > 0
        function rcActionResult(id: int, kind: string, index: int, result: string) {
            remote.actionResult(id, kind, index, result)
        }
    }
    // the phone's link, asked only when an action failed: the words of a link that is down
    // (connectivity-system-ux-05)
    DBusInterface {
        id: phoneLink
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/phone"
        iface: "org.asteroidos.btsyncd.Phone"
    }
    DBusInterface {
        id: voice
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/voice"
        iface: "org.asteroidos.btsyncd.Voice"
    }

    function actionResult(id, kind, index, result) {
        var e = inflight[id]
        if (e === undefined || e.kind !== kind || (kind === "app" && e.index !== index))
            return
        finish(id)
        if (result === "ok") {
            if (kind === "open")
                note("open", id)
            else
                showSuccess(id)
        } else if (result === "timeout") {
            showSlow(id)
        } else {
            remote.failOrAway(id, kind)
        }
    }

    // A failure with no phone link says so as stock does: "Phone away" for the actions that open
    // something on the phone, "To send, reconnect to your phone" for a reply; with the link up it
    // is the generic "Can't finish action"
    function failOrAway(id, kind) {
        phoneLink.typedCall("Connected", [],
                            function (connected) {
                                if (connected === false)
                                    remote.showAway(id, kind)
                                else
                                    remote.showFailure(id)
                            },
                            function () { remote.showFailure(id) })
    }

    function showAway(id, kind) {
        if (kind === "open" && Desktop.phoneAway) {
            Desktop.phoneAway.show()
        } else {
            //% "To send, reconnect to your phone"
            showDialog(qsTrId("id-action-failed-title"), qsTrId("id-send-reconnect"))
        }
        note("away", id)
    }

    /* ---- what is shown -------------------------------------------------- */

    function note(what, id) {
        lastOutcome = what
        outcomes++
        outcome(what, id === undefined ? -1 : id)
    }

    function confirm(text, ok, ms) {
        var c = Desktop.confirmation
        if (!c)
            return
        if (ms > 0) {
            c.duration = ms
            var restore = function () {
                c.duration = c.defaultDuration
                c.finished.disconnect(restore)
            }
            c.finished.connect(restore)
        }
        c.show(text, ok)
    }

    function showSuccess(id) {
        //% "Success"
        confirm(qsTrId("id-action-success"), true, successMs)
        note("success", id)
    }
    function showOpenOnPhone() {
        var c = Desktop.confirmation
        if (c)
            c.showOpenOnPhone()
    }

    function showDialog(title, text) {
        failure.title = title
        failure.text = text
        Haptics.reject()
        failure.open()
    }
    function showFailure(id) {
        //% "Can’t finish action"
        showDialog(qsTrId("id-action-failed-title"),
                   //% "Please check your connection"
                   qsTrId("id-action-failed-text"))
        note("failed", id)
    }
    function showSlow(id) {
        //% "Slow connection"
        showDialog(qsTrId("id-action-slow-title"),
                   //% "Check back soon"
                   qsTrId("id-action-slow-text"))
        note("slow", id)
    }
    function showGone(id) {
        //% "Action not completed"
        showDialog(qsTrId("id-action-gone-title"),
                   //% "Notification is no longer active"
                   qsTrId("id-action-gone-text"))
        note("gone", id)
    }

    AlertDialog {
        id: failure
        objectName: "actionResultDialog"
        z: 50
        buttons: "edge"
    }

    Toast {
        id: toast
        objectName: "remoteToast"
        anchors.fill: parent
        z: 60
    }

    /* ---- actions -------------------------------------------------------- */

    function failNow(id) {
        var e = finish(id)
        if (e)
            failOrAway(id, e.kind)
    }

    // a reply (typed, spoken, an emoji or a canned one)
    function reply(id, text) {
        var t = String(text).trim()
        if (t.length === 0)
            return false
        if (!isActive(id)) {
            showGone(id)
            return false
        }
        if (!begin(id, "reply", -1))
            return false
        btsyncd.typedCall("Reply",
                          [{ "type": "u", "value": id }, { "type": "s", "value": t }],
                          function (sent) { if (!sent) remote.failNow(id) },
                          function () { remote.failNow(id) })
        return true
    }

    // one of the app's actions (kind "app", index) or Open on phone (kind "open")
    function invoke(n, kind, index) {
        if (!n)
            return false
        var id = n.replacesId
        if (!isActive(id)) {
            showGone(id)
            return false
        }
        // the guard holds from the tap on, the phone check included
        if (!begin(id, kind, kind === "app" ? index : -1))
            return false
        btsyncd.typedCall("PhoneConnected", [],
                          function (connected) {
                              if (!remote.pending(id))
                                  return
                              if (!connected) {
                                  remote.failNow(id)
                                  return
                              }
                              // "Check your phone" shows at once, then the intent goes
                              if (kind === "open")
                                  remote.showOpenOnPhone()
                              try {
                                  n.actionInvoked(kind === "open" ? "open" : "app-" + index)
                              } catch (e) {
                                  if (remote.finish(id))
                                      remote.showGone(id)
                              }
                          },
                          function () { remote.failNow(id) })
        return true
    }

    // the call and find-my-watch actions are the phone's own: no wait
    function invokeDirect(n, key) {
        if (!n)
            return false
        n.actionInvoked(key)
        return true
    }

    /* ---- the layers of a reply ----------------------------------------- */

    // The keyboard (startPage "": the keys, "emoji": the emoji page, "voice": dictation)
    // on the stack `host`; the reply goes with the action key
    function openKeyboard(host, id, startPage, emojiAllowed) {
        if (!host)
            return null
        return host.push(keyboardLayer, { notificationId: id, startPage: startPage || "",
                                          emojiAllowed: emojiAllowed !== false })
    }

    // Voice: the recogniser's word first (btsyncd Voice.Available); none: the toast
    function openVoice(host, id, emojiAllowed) {
        voice.typedCall("Available", [],
                        function (available) {
                            if (available)
                                remote.openKeyboard(host, id, "voice", emojiAllowed)
                            else
                                remote.showVoiceUnavailable()
                        },
                        function () { remote.showVoiceUnavailable() })
    }
    function showVoiceUnavailable() {
        //% "Voice input not available"
        toast.show(qsTrId("id-voice-unavailable"))
        note("voice", -1)
    }

    Component {
        id: keyboardLayer

        Item {
            id: page
            property var pop
            property int depth
            property int notificationId: 0
            property string startPage: ""
            property bool emojiAllowed: true
            readonly property bool fullScreen: true
            property alias keyboard: replyKeyboard

            // Gboard for Wear OS's full screen keyboard on the page asked for, the reply
            // with the action key; a swipe right, the crown or Back go back to the card
            WearKeyboard {
                id: replyKeyboard
                anchors.fill: parent
                startPage: page.startPage
                actionKey: "send"
                emojiEnabled: page.emojiAllowed
                voiceEngine: "btsyncd"
                voiceNotificationId: page.notificationId
                onAccepted: (text) => {
                    if (remote.reply(page.notificationId, text) || String(text).trim().length > 0)
                        page.pop()
                }
                onDismissed: page.pop()
                Component.onCompleted: {
                    Desktop.keyboard = replyKeyboard
                    forceActiveFocus()
                }
                Component.onDestruction: if (Desktop.keyboard === replyKeyboard) Desktop.keyboard = null
            }
        }
    }
}
