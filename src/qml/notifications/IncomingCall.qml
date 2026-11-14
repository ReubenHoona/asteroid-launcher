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
import Nemo.Configuration
import org.asteroid.controls
import org.nemomobile.lipstick

/*
 * Full screen view of a call on the phone: a notification from the phone
 * (asteroid-btsyncd) that offers answer or reject while it rings, or only
 * `end` once the call is answered. The screen is the stock Phone app's
 * (CP3A, Compose, InCall.qml): ringing and in call are one layout that the
 * Answer button turns into the End call button. Answer, Decline and End are
 * reported to the phone like any notification action.
 *
 * While it rings the view keeps the display on and goes away when the phone
 * removes the notification (answered elsewhere, declined, missed) or the
 * user acts on it. A swipe right closes the view and silences the ringer
 * (the call keeps ringing on the phone and its card stays: calls-03); More
 * options silences it too and offers the quick replies (calls-04), a reply
 * declines the call with that text (btsyncd Reply).
 *
 * Answer keeps the view: it moves into the in-call layout at once (the
 * status line empty) and takes over the phone's call card when it arrives
 * (calls-05). A call in progress neither turns the display on nor keeps it
 * on. A swipe right hides it, the call goes on (calls-08); End shows
 * "Hanging up" until the phone removes the card, then "Call ended" for
 * three seconds (calls-19). The crown changes the call volume with an edge
 * arc (calls-09), More has Volume, and with the call audio on the watch
 * Keypad and the audio route (calls-11); Mute is there then (calls-10).
 * Everything else keeps the usual notification preview.
 *
 * Lipstick restores its notifications at start. A call card older than a
 * few minutes when restored is a call that ended while the watch was down
 * (the phone's removal never arrived: it only comes when the call's state
 * changes) and is no call to show: stock Wear OS never shows a call screen
 * for a call that ended. The card stays in the list as a plain notification
 * until asteroid-btsyncd closes it, once the phone is back without posting
 * the call again (its CallGraceMs).
 *
 * Battery: the timer of the time in call runs only while the display is on;
 * the name's marquee and the answer animation stop with the display. The
 * view never draws in ambient: the watch face stays (calls-29).
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

    // Answer was tapped and the phone's call card has not come yet: the
    // in-call layout with an empty status line (calls-05)
    property bool answering: false
    // End was tapped and the phone has not removed the card yet (calls-07)
    property bool hangingUp: false
    // The phone removed the call: "Call ended" for 3 s (calls-19)
    property bool callEnded: false
    // The caller shown when the card is gone
    property string lastName: ""
    // The user hid the view while the answer was on its way: the call card
    // that follows is not shown again
    property bool hideNextOngoing: false

    readonly property var callActions: call ? phoneActions(call) : []
    // The phone says this call is going on
    readonly property bool liveOngoing: call !== null && isOngoing(call)
    // The in-call layout is shown (not ringing)
    readonly property bool ongoing: answering || hangingUp || callEnded || liveOngoing
    // Time in call, refreshed every second while shown
    property string elapsed: ""
    // The display is off: nothing to refresh
    property bool displayOff: false
    // Bedtime and Theater mode (modes.h): the screen stays off until a
    // button turns it on, as stock; the call shows then, without ringing
    readonly property bool screenStaysOff: typeof modes !== "undefined" && modes !== null
                                           && (modes.bedtime || modes.theater)

    visible: call !== null || answering || callEnded

    // The waits (ms): the phone's call card after Answer, its removal after
    // End, "Call ended" (mig.java:24-26) and the volume arc (gsc.java:148)
    property int answerWaitMs: 15000
    property int hangWaitMs: 10000
    property int endedMs: 3000
    property int arcHideMs: 2500
    // The audio of the call (btsyncd), for the tests and the menus
    readonly property alias audio: callAudio

    // More options, Volume and Keypad are open (each swipes away alone)
    property bool moreOpen: false
    property bool volumeOpen: false
    property bool keypadOpen: false
    readonly property bool menuOpen: moreOpen || volumeOpen || keypadOpen

    // Unknown caller (calls-21): stock remote_end_display_name_unknown
    readonly property string unknownName:
        //% "Unknown"
        qsTrId("id-call-unknown") + localeManager.changesObserver
    readonly property string displayName: call !== null ? nameOf(call) : lastName

    /* What the notification server needs to know (lipstick LipstickSettings
     * callState: 0 none, 1 ringing, 2 in progress): in a call a notification
     * does not vibrate (stock NotificationAttentionHelper.java:1168-1171,
     * 778-800, 843-846: it gates on the call being in progress, not on the
     * call screen being shown; interruptions-07), and a phone alarm's
     * vibration stops while a call rings (interruptions-15).
     * It follows the phone's call notifications in the model, not the view:
     * hiding the call view (the swipe, the crown) leaves the call going, and
     * the state stays 2 until the phone closes the notification or the user
     * ends the call. Recomputed when the model or the view changes, no
     * timer. */
    property int phoneCallState: 0
    // Calls known not to be going on: ended by the user, or a restored card
    // too old to be a call
    property var ended: ({})
    // (End tapped, or the call over: not in progress for it, whatever the screen says)
    readonly property int callStateValue: (call !== null && !ongoing) ? 1
                                          : (ongoing && !hangingUp && !callEnded ? 2 : phoneCallState)
    onCallStateValueChanged: {
        try {
            if (typeof lipstickSettings !== "undefined" && lipstickSettings !== null)
                lipstickSettings.callState = callStateValue
        } catch (e) {
            console.log("IncomingCall: callState:", e)
        }
    }

    // Answering a second call ends the one in progress: asks first (stock
    // dialer bc25_second_incoming_call_confirmation_title / _message;
    // interruptions-17, calls-18)
    property bool confirmingAnswer: false

    // The name shown: the card's summary, else its number, else "Unknown"
    function nameOf(n) {
        var s = n.summary !== undefined && n.summary !== null ? String(n.summary).trim() : ""
        if (s !== "")
            return s
        var b = n.body !== undefined && n.body !== null ? String(n.body).trim() : ""
        return b !== "" ? b : unknownName
    }

    // The monogram's letter; none for a number or no name (a person glyph)
    function monogramOf(s) {
        var t = String(s).trim()
        if (t === "" || t === unknownName)
            return ""
        var c = t.charAt(0)
        if (/[0-9+*#()\-.\s]/.test(c))
            return ""
        return c.toUpperCase()
    }

    function otherOngoing() {
        for (var i = 0; i < notifModel.itemCount; i++) {
            var n = notifModel.get(i)
            if (n !== call && isOngoing(n))
                return true
        }
        return false
    }

    function updateCallState(except) {
        var s = 0
        for (var i = 0; i < notifModel.itemCount; i++) {
            var n = notifModel.get(i)
            if (n === except || n === null || n === undefined)
                continue
            if (isRinging(n)) {
                s = 1
                break
            }
            if (isInProgress(n))
                s = 2
        }
        phoneCallState = s
    }

    function answer() {
        if (call === null || answering)
            return
        if (otherOngoing())
            confirmingAnswer = true
        else
            doAnswer()
    }

    // The call in progress is ended and the new one answered (calls-18)
    function confirmAnswer() {
        confirmingAnswer = false
        for (var i = 0; i < notifModel.itemCount; i++) {
            var n = notifModel.get(i)
            if (n !== call && isOngoing(n)) {
                ended[n.replacesId] = true
                n.actionInvoked("end")
            }
        }
        doAnswer()
    }

    // Answer: the view stays and goes into the in-call layout (calls-05)
    function doAnswer() {
        var n = call
        if (n === null)
            return
        handled[n.replacesId] = true
        silenced = true
        hideNextOngoing = false
        answering = true
        giveUp.stop()
        answerWait.restart()
        if (keepOn)
            displayRelease()
        updateCallState(null)
        // Lipstick reports it to asteroid-btsyncd, which tells the phone;
        // the phone's call card then replaces the ringing one
        n.actionInvoked("answer")
    }

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
        return n !== null && n !== undefined && !handled[n.replacesId] && isInProgress(n)
    }

    // The phone says this call is going on, whether or not its view is
    // shown or was hidden (not once the user ended it)
    function isInProgress(n) {
        if (n === null || n === undefined || ended[n.replacesId])
            return false
        if (new Date().getTime() - n.timestamp.getTime() > 4 * 3600000)
            return false
        var a = phoneActions(n)
        return a.indexOf("end") >= 0 && a.indexOf("answer") < 0 && a.indexOf("reject") < 0
    }

    // A call card lipstick restored at start (before the model is populated)
    // that is older than this is no call to show (see the top of the file)
    readonly property int restoredCallMaxMs: 180000

    // A call from the phone, ringing or in progress
    function isCall(n) {
        var a = phoneActions(n)
        return a.indexOf("end") >= 0 || a.indexOf("answer") >= 0 || a.indexOf("reject") >= 0
    }

    function staleRestored(n) {
        return !notifModel.populated && isCall(n)
               && new Date().getTime() - n.timestamp.getTime() > restoredCallMaxMs
    }

    // Not waiting for anything any more: the three one-shot waits, the
    // answer, the hang-up and the "Call ended" word, and the menus
    function clearEndStates() {
        answering = false
        hangingUp = false
        callEnded = false
        answerWait.stop()
        hangTimer.stop()
        endedTimer.stop()
        moreOpen = false
        volumeOpen = false
        keypadOpen = false
        arcShown = false
    }

    function showOngoing(n) {
        giveUp.stop()
        if (keepOn)
            displayRelease()
        clearEndStates()
        call = n
        silenced = true
        updateElapsed()
    }

    // Seconds in call as the stock DateUtils.formatElapsedTime: "00:42",
    // "1:02:03" (calls-07)
    function formatElapsed(total) {
        var s = Math.max(0, Math.floor(total))
        var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60
        s = s % 60
        var mm = (m < 10 ? "0" : "") + m, ss = (s < 10 ? "0" : "") + s
        return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
    }

    function updateElapsed() {
        if (call === null || !liveOngoing)
            return
        var from = call.timestamp.getTime()
        // an outgoing call counts from the far end answering when oFono
        // says so (calls-20); else from the dial, as before
        if (dialedBefore && activeSince > from)
            from = activeSince
        elapsed = formatElapsed((new Date().getTime() - from) / 1000)
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
            clearEndStates()
            call = n
            silenced = n.hints["x-nemo-feedback-suppressed"] === true
        }
        hideNextOngoing = false
        giveUp.restart()
        if (screenStaysOff)
            return
        keepOn = true
        displayOn()
    }

    // Done with the call shown: the next ringing call, if any, from scratch
    function next(done) {
        if (done !== null)
            handled[done.replacesId] = true
        var n = newestCall(done)
        clearEndStates()
        call = null
        if (n !== null)
            show(n)
        updateCallState(null)
    }

    function hide() {
        // the answer is on its way: the call card that follows stays quiet
        if (answering)
            hideNextOngoing = true
        next(call)
    }

    // A swipe right (calls-03, calls-08): a ringing call is silenced, the
    // view leaves, the call and its card stay
    function swipeAway() {
        if (call !== null && !ongoing)
            silence()
        hide()
    }

    // The phone removed the call that was in progress (the far end hung
    // up) or the one the user ended: "Call ended" for 3 s (calls-19)
    function startEnded(item) {
        lastName = nameOf(item)
        answerWait.stop()
        hangTimer.stop()
        if (displayOff) {
            hide()
            return
        }
        handled[item.replacesId] = true
        clearEndStates()
        call = null
        callEnded = true
        endedTimer.restart()
        updateCallState(item)
    }

    // A tap on the call's card in the notification stream (its content intent is
    // the in-call activity, stock dialer jgv.java:128-130; calls-17): the call
    // view again, its 'handled' mark cleared. False when the card is no call, or
    // a call that is over (an old ringing card, one the user ended): the stream
    // then opens the card in place.
    function reopen(n) {
        if (n === null || n === undefined || !isCall(n))
            return false
        var was = handled[n.replacesId]
        delete handled[n.replacesId]
        if (isInProgress(n)) {
            showOngoing(n)
            updateCallState(null)
            return true
        }
        if (isRinging(n)) {
            show(n)
            return true
        }
        if (was)
            handled[n.replacesId] = true
        return false
    }

    onCallChanged: {
        confirmingAnswer = false
        if (call !== null)
            lastName = nameOf(call)
        sawDialing = false
        dialedBefore = false
        activeSince = 0
        if (call === null)
            displayRelease()
    }

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
        if (key === "end") {
            // "Hanging up" until the phone removes the card
            ended[n.replacesId] = true
            hangingUp = true
            hangTimer.restart()
            giveUp.stop()
            updateCallState(null)
            n.actionInvoked(key)
            return
        }
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

    // A quick reply: the call is declined with this text (calls-04). The
    // phone rejects the call and sends the text (btsyncd Reply -> Gadgetbridge).
    function reply(text) {
        var n = call
        if (n === null || ongoing)
            return
        var id = n.replacesId
        next(n)
        btsyncd.typedCall("Reply", [{ "type": "u", "value": id }, { "type": "s", "value": text }],
                          function (sent) { if (!sent) console.log("IncomingCall: btsyncd did not send the reply") },
                          function (error, message) { console.log("IncomingCall: Reply:", error, message) })
    }

    // More options: opening it silences a ringing call first
    function openMore() {
        if (call === null && !ongoing)
            return
        if (!ongoing)
            silence()
        moreOpen = true
    }

    /* ---- the call volume (calls-09) ---- */

    // The edge arc shows while the volume changes
    property bool arcShown: false
    // The level when the phone does not tell: one step is 1/7 of the range
    property real assumedLevel: 0.5
    readonly property int assumedSteps: 7
    readonly property real volumeLevel: callAudio.level >= 0 ? callAudio.level : assumedLevel
    // Crown counts per step (the crown settings of qml-asteroid's RotaryInput)
    property real crownPending: 0

    function stepVolume(delta) {
        callAudio.adjustVolume(delta)
        if (callAudio.level < 0)
            assumedLevel = Math.max(0, Math.min(1, assumedLevel + delta / assumedSteps))
        arcShown = true
        arcTimer.restart()
    }

    // The crown: one step per detent, forward (clockwise) raises the volume
    function crown(angleDelta) {
        var detent = Math.max(1, Number(crownDetent.value) || 24)
        crownPending += -angleDelta / 120
        var steps = Math.trunc(crownPending / detent)
        if (steps === 0)
            return
        crownPending -= steps * detent
        var dir = steps > 0 ? 1 : -1
        if (crownInvert.value === true)
            dir = -dir
        for (var i = 0; i < Math.abs(steps); i++) {
            stepVolume(dir)
            Haptics.scrollTick()
        }
    }

    /* ---- outgoing calls (calls-20): oFono's call state through btsyncd ---- */
    property bool sawDialing: false
    // the call was dialing or alerting before it became active
    property bool dialedBefore: false
    property real activeSince: 0

    ConfigurationValue {
        id: crownInvert
        key: "/org/asteroidos/ux/rotary-invert"
        defaultValue: false
    }

    ConfigurationValue {
        id: crownDetent
        key: "/org/asteroidos/ux/rotary-counts-per-detent"
        defaultValue: 24
    }

    // The audio of the call (btsyncd), listened to while a call view is up
    CallAudio {
        id: callAudio
        active: incomingCall.visible
        onCallStateChanged: {
            // (the `dialing` binding may not have followed yet)
            if (callState === "dialing" || callState === "alerting")
                incomingCall.sawDialing = true
            else if (callState === "active" && incomingCall.sawDialing) {
                incomingCall.dialedBefore = true
                incomingCall.activeSince = new Date().getTime()
                incomingCall.updateElapsed()
            }
        }
    }

    // What the screen says under the monogram
    readonly property string statusText: hangingUp ?
        //% "Hanging up"
        qsTrId("id-call-hanging-up") + localeManager.changesObserver :
        callEnded ?
        //% "Call ended"
        qsTrId("id-call-ended") + localeManager.changesObserver :
        (liveOngoing && callAudio.dialing) ?
        //% "Calling..."
        qsTrId("id-call-calling") + localeManager.changesObserver :
        liveOngoing ? elapsed : ""

    NotificationListModel {
        id: notifModel
        onItemAdded: function (item) {
            if (staleRestored(item)) {
                // Not now, nor by a later look at the list
                handled[item.replacesId] = true
                ended[item.replacesId] = true
                console.log("IncomingCall: restored call card", item.replacesId, "from", item.timestamp, "is too old to show")
                return
            }
            if (isRinging(item))
                show(item)
            else if (isOngoing(item) && (call === null || incomingCall.ongoing)) {
                if (hideNextOngoing) {
                    hideNextOngoing = false
                    handled[item.replacesId] = true
                } else
                    showOngoing(item)
            }
            updateCallState(null)
        }
        onItemRemoved: function (item) {
            if (item === call) {
                if (answering) {
                    // the phone replaces the ringing card by the call's:
                    // the view stays and waits for it
                    lastName = nameOf(item)
                    call = null
                } else if (hangingUp || liveOngoing) {
                    startEnded(item)
                } else {
                    hide()
                }
            }
            updateCallState(item)
        }
        // The launcher restarted while a call rang
        onPopulatedChanged: {
            var n = newestCall(null)
            if (notifModel.populated && n !== null)
                show(n)
            updateCallState(null)
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

    // The time in call: only while the display is on and the call is
    // really going (not while dialing, answering or hanging up)
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: incomingCall.visible && incomingCall.liveOngoing && !incomingCall.displayOff
                 && !callAudio.dialing
        onTriggered: updateElapsed()
    }

    // A phone that never says the call is over must not leave this up
    Timer {
        id: giveUp
        interval: 180000
        onTriggered: hide()
    }

    // The phone's call card did not follow the answer
    Timer {
        id: answerWait
        interval: incomingCall.answerWaitMs
        onTriggered: hide()
    }

    // The phone did not remove the card after End
    Timer {
        id: hangTimer
        interval: incomingCall.hangWaitMs
        onTriggered: hide()
    }

    // "Call ended" stays three seconds (mig.java:24-26)
    Timer {
        id: endedTimer
        interval: incomingCall.endedMs
        onTriggered: hide()
    }

    // The volume arc goes 2.5 s after the last change, as the system volume
    // indicator (media-controls: gsc.java:140-153)
    Timer {
        id: arcTimer
        interval: incomingCall.arcHideMs
        onTriggered: incomingCall.arcShown = false
    }

    // The user turned the display off (power key) while it rang: silence the
    // call as on a phone, and let the display stay off
    Connections {
        target: Lipstick.compositor
        function onDisplayOff() {
            incomingCall.displayOff = true
            incomingCall.arcShown = false
            if (incomingCall.visible && incomingCall.keepOn) {
                silence()
                displayRelease()
            }
        }
        function onDisplayOn() { incomingCall.displayOff = false }
    }

    // The crown is the call volume while the in-call screen is up, and
    // while the Volume screen is; the menus' lists keep it for scrolling
    WheelHandler {
        id: crownHandler
        objectName: "callCrown"
        enabled: incomingCall.visible && incomingCall.ongoing && callAudio.present && !incomingCall.confirmingAnswer
                 && !incomingCall.keypadOpen && (incomingCall.volumeOpen || !incomingCall.moreOpen)
        onWheel: function (event) {
            incomingCall.crown(event.angleDelta.y)
            event.accepted = true
        }
    }

    BackSwipeArea {
        id: swipe
        objectName: "callSwipe"
        anchors.fill: parent
        swipeEnabled: incomingCall.visible && !incomingCall.menuOpen && !incomingCall.confirmingAnswer
        onFinished: {
            var go = committed
            reset()
            if (go)
                incomingCall.swipeAway()
        }

        Item {
            id: face
            width: parent.width
            height: parent.height
            x: swipe.value

            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }

            // Nothing underneath reacts while the call is shown
            MouseArea {
                anchors.fill: parent
            }

            InCall {
                id: screen
                anchors.fill: parent
                name: incomingCall.displayName
                initial: incomingCall.monogramOf(incomingCall.displayName)
                inCall: incomingCall.ongoing
                animate: !incomingCall.displayOff
                marqueePaused: incomingCall.displayOff
                status: incomingCall.statusText
                buttonsEnabled: !incomingCall.hangingUp && !incomingCall.callEnded
                canDecline: incomingCall.ongoing || incomingCall.hasAction("reject")
                canAnswer: incomingCall.hasAction("answer")
                canEnd: true
                // More: the quick replies need the phone to offer `reply` on
                // the call; in a call it has Volume (btsyncd's call audio)
                canMore: incomingCall.ongoing ? callAudio.present : incomingCall.hasAction("reply")
                canMute: callAudio.available
                muted: callAudio.muted
                // while the answer is on its way End and Decline do nothing
                onDeclineClicked: if (!incomingCall.answering) incomingCall.act("reject")
                onAnswerClicked: incomingCall.answer()
                onEndClicked: if (!incomingCall.answering && incomingCall.liveOngoing) incomingCall.act("end")
                onMoreClicked: incomingCall.openMore()
                onMuteToggled: callAudio.setMuted(!callAudio.muted)
            }

            CallVolumeArc {
                objectName: "crownArc"
                level: incomingCall.volumeLevel
                shown: incomingCall.arcShown && !incomingCall.volumeOpen
            }
        }
    }

    Component {
        id: incomingMoreComponent
        IncomingCallMore {
            onReplyChosen: function (text) { incomingCall.reply(text) }
            onCloseRequested: incomingCall.moreOpen = false
        }
    }

    Component {
        id: inCallMoreComponent
        InCallMore {
            audio: callAudio
            onVolumeRequested: incomingCall.volumeOpen = true
            onKeypadRequested: incomingCall.keypadOpen = true
            onCloseRequested: incomingCall.moreOpen = false
        }
    }

    Loader {
        id: moreLoader
        objectName: "moreLoader"
        anchors.fill: parent
        active: incomingCall.moreOpen && incomingCall.visible
        sourceComponent: incomingCall.ongoing ? inCallMoreComponent : incomingMoreComponent
    }

    Loader {
        id: volumeLoader
        objectName: "volumeLoader"
        anchors.fill: parent
        active: incomingCall.volumeOpen && incomingCall.visible
        sourceComponent: CallVolume {
            level: incomingCall.volumeLevel
            onStep: function (delta) { incomingCall.stepVolume(delta) }
            onCloseRequested: incomingCall.volumeOpen = false
        }
    }

    Loader {
        id: keypadLoader
        objectName: "keypadLoader"
        anchors.fill: parent
        active: incomingCall.keypadOpen && incomingCall.visible
        sourceComponent: InCallKeypad {
            onTone: function (key) { callAudio.sendTones(key) }
            onCloseRequested: incomingCall.keypadOpen = false
        }
    }

    // "End current call?" over the ringing call (a second call, a call in
    // progress): Confirm ends the one in progress and answers, Cancel leaves
    // it ringing (stock AlertDialog, confirm and dismiss buttons)
    AlertDialog {
        id: confirmDialog
        objectName: "confirmAnswer"
        //% "End current call?"
        title: qsTrId("id-call-second-title") + localeManager.changesObserver
        //% "Answering new call will end current call"
        text: qsTrId("id-call-second-message") + localeManager.changesObserver
        onConfirmed: incomingCall.confirmAnswer()
        onDismissed: incomingCall.confirmingAnswer = false
        Component.onCompleted: {
            titleLabel.objectName = "confirmTitle"
            textLabel.objectName = "confirmMessage"
            dismissButton.objectName = "confirmCancel"
            confirmButton.objectName = "confirmAnswerButton"
        }
    }

    onConfirmingAnswerChanged: {
        if (confirmingAnswer)
            confirmDialog.open()
        else
            confirmDialog.close()
    }
}
