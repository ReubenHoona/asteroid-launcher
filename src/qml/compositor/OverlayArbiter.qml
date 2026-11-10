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

/* The launcher overlays over applications (split out of compositor.qml),
 * rendered directly in the compositor scene as z-ordered items instead of
 * in-process "windows". Each is fed by a C++ object exposed as a context
 * property; the QML gates its own visibility. Instantiated once in
 * compositor.qml as `arbiter` at z 2.5; the loaders keep their z of
 * compositor.qml (2.5, 3, 3, 3, 3, 3, 4), so they stack as before over the
 * application layer (2) and under the edge swipe (5) and the corner mask
 * (6). compositor.qml forwards assistantShown, openAssistant() and
 * closeAssistant(). Owned by the packages of the overlays (assistant,
 * heads-up, calls, alarms, power). */
Item {
    id: arbiter
    anchors.fill: parent
    z: 2.5

    /* The assistant over the home screen and applications (Wear OS: an
     * activity on top), under heads-up notifications, calls and alarms. */
    Loader {
        id: assistantLoader
        z: 2.5
        anchors.fill: parent
        source: "../assistant/AssistantOverlay.qml"
    }
    readonly property bool assistantShown: assistantLoader.item ? assistantLoader.item.shown : false
    function openAssistant(text) {
        if (!assistantLoader.item)
            return
        launchSplash.cancel()
        assistantLoader.item.open(text || "")
    }
    function closeAssistant() {
        assistantLoader.item.close()
    }

    Loader {
        z: 3
        anchors.fill: parent
        source: "../notifications/NotificationPreview.qml"
    }

    // A call ringing on the phone: full screen, above the preview
    Loader {
        z: 3
        anchors.fill: parent
        source: "../IncomingCall.qml"
    }

    // An alarm or timer ringing on the phone: full screen, above the preview
    Loader {
        z: 3
        anchors.fill: parent
        source: "../PhoneAlarm.qml"
    }

    Loader {
        z: 3
        anchors.fill: parent
        source: "../system/ShutdownScreen.qml"
    }

    // Bedtime mode coming on: "Starting Bedtime mode…" (modes.h)
    Loader {
        z: 3
        anchors.fill: parent
        source: "../system/ModeScreen.qml"
    }

    Loader {
        z: 4
        anchors.fill: parent
        source: "../connectivity/BluetoothAgent.qml"
    }
}
