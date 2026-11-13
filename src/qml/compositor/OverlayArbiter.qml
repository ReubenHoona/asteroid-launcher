/*
 * Copyright (C) 2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 *               2013 John Brooks <john.brooks@dereferenced.net>
 *               2013 Jolla Ltd.
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
import QtQuick.Window
import org.nemomobile.lipstick

/* The launcher overlays over applications (split out of compositor.qml),
 * rendered directly in the compositor scene as z-ordered items instead of
 * in-process "windows". Each is fed by a C++ object exposed as a context
 * property; the QML gates its own visibility. Instantiated once in
 * compositor.qml as `arbiter` at z 2.5, over the application layer (2) and
 * under the edge swipe (5) and the corner mask (6). compositor.qml forwards
 * assistantShown, openAssistant() and closeAssistant(). Owned by the
 * packages of the overlays (assistant, heads-up, calls, alarms, power).
 *
 * Who covers whom (W2-launcher-keys-lifecycle; the stock rule is that the
 * newest activity is on top, and calls and firing alarms are on top of
 * everything a user did not just ask for: audit interruptions-09, -15, -16,
 * -18, -20). Lowest first:
 *   assistant 2.5, heads-up card 3, shutdown 3, Bedtime start 3,
 *   Bluetooth pairing 3.3, phone alarm 3.4, the alert window (a firing
 *   alarm or timer of the watch) 3.5, call 3.6, power menu and thermal
 *   dialogs 3.8 (reserved, above the call and alarm views), touch lock 5.5
 *   (reserved, in compositor.qml above everything but the corner mask).
 * The call view is above the alarms: a call ringing or in progress
 * silences and dismisses a firing alarm, as stock (DeskClock hob.java:
 * 68-96). */
Item {
    id: arbiter
    anchors.fill: parent
    z: 2.5

    readonly property var layers: ({
        assistant: 2.5, headsUp: 3, shutdown: 3, mode: 3,
        bluetooth: 3.3, phoneAlarm: 3.4, alert: 3.5, call: 3.6,
        callAssistant: 3.65, powerMenu: 3.8, touchLock: 5.5
    })

    /* The assistant over the home screen and applications (Wear OS: an
     * activity on top), under heads-up notifications, calls and alarms.
     * Above the call view while one is up (it then says it cannot help in
     * a call). */
    Loader {
        id: assistantLoader
        z: arbiter.callShown ? arbiter.layers.callAssistant : arbiter.layers.assistant
        anchors.fill: parent
        source: "../assistant/AssistantOverlay.qml"
    }
    readonly property bool assistantShown: assistantLoader.item ? assistantLoader.item.shown : false
    function openAssistant(text) {
        if (!assistantLoader.item)
            return
        launchSplash.cancel()
        // a call ringing or in progress: no listening, the card says so
        // (interruptions-08); a firing alarm: no assistant (interruptions-09)
        if (alertShown)
            return
        assistantLoader.item.inCall = callShown
        assistantLoader.item.open(text || "")
    }
    function closeAssistant() {
        if (assistantLoader.item)
            assistantLoader.item.close()
    }

    Loader {
        id: previewLoader
        z: arbiter.layers.headsUp
        anchors.fill: parent
        source: "../notifications/NotificationPreview.qml"
    }

    // A call ringing on the phone: full screen, above the preview, the
    // phone alarm and the alert window
    Loader {
        id: callLoader
        z: arbiter.layers.call
        anchors.fill: parent
        source: "../IncomingCall.qml"
    }
    readonly property Item callView: callLoader.item
    readonly property bool callShown: callView ? callView.visible : false
    readonly property bool callOngoing: callShown && callView.ongoing === true
    // ringing and not yet silenced: a key press silences it
    readonly property bool callRinging: callShown && !callOngoing && callView.silenced !== true
    function silenceCall() { if (callView && callView.silence) callView.silence() }
    // leave the call view (the call goes on, its notification stays)
    function hideCall() { if (callView && callView.hide) callView.hide() }

    // An alarm or timer ringing on the phone: full screen, above the
    // preview and under the call
    Loader {
        id: alarmLoader
        z: arbiter.layers.phoneAlarm
        anchors.fill: parent
        source: "../PhoneAlarm.qml"
    }
    readonly property bool phoneAlarmShown: alarmLoader.item ? alarmLoader.item.visible : false

    /* The window of a firing alarm or timer of the watch (the alarm
     * presenter, a client window): above the assistant, the heads-up card
     * and the Bluetooth dialog (AppLifecycle puts its wrapper here). */
    Item {
        id: alertHost
        z: arbiter.layers.alert
        anchors.fill: parent
        property bool ready: false
        visible: arbiter.alertShown
        // Let the client deal with rotation itself, as appLayer
        rotation: Screen.angleBetween(Lipstick.compositor.screenOrientation, Screen.primaryScreen)
    }
    readonly property Item alertLayer: alertHost
    readonly property bool alertShown: typeof comp !== "undefined" && comp ? comp.alertShown : false

    // A surface of the system is up that covers the screen with something
    // that must not be covered by a mode's start screen (interruptions-16)
    readonly property bool interrupting: callShown || phoneAlarmShown || alertShown

    // A call or a firing alarm arriving closes the assistant, which stops
    // its microphone (interruptions-08, -09); the alarm also hides the
    // heads-up card (it stays in the stream)
    readonly property bool _takesOver: callShown || alertShown
    on_TakesOverChanged: {
        if (_takesOver && assistantShown)
            closeAssistant()
    }
    onAlertShownChanged: {
        if (alertShown) {
            closeAssistant()
            if (previewLoader.item && previewLoader.item.hide)
                previewLoader.item.hide()
        }
    }

    Loader {
        z: arbiter.layers.shutdown
        anchors.fill: parent
        source: "../system/ShutdownScreen.qml"
    }

    // Bedtime mode coming on: "Starting Bedtime mode…" (modes.h)
    Loader {
        z: arbiter.layers.mode
        anchors.fill: parent
        source: "../system/ModeScreen.qml"
    }

    // The pairing dialog: under the call, the alarms and the alert window
    Loader {
        z: arbiter.layers.bluetooth
        anchors.fill: parent
        source: "../connectivity/BluetoothAgent.qml"
    }
}
