/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus

/*
 * The audio of the call, as asteroid-btsyncd reports it and takes commands
 * (calls-09 volume, calls-10 mute, calls-11 route and keypad, calls-20
 * call states). The launcher only asks and shows; where the audio really
 * goes is btsyncd's: with call audio on the watch (HFP, calls-12) the watch
 * is the call volume and mic, otherwise the volume goes to the phone
 * through Gadgetbridge and there is nothing to mute or route.
 *
 * The D-Bus contract (session bus, org.asteroidos.btsyncd,
 * /org/asteroidos/btsyncd/callaudio, org.asteroidos.btsyncd.CallAudio):
 *   State() -> a{sv}        keys: available (b), muted (b), route (s,
 *                           "watch" or "phone"), volume (i), volumeMax (i),
 *                           callState (s: "dialing", "alerting", "active",
 *                           "held", "disconnected")
 *   StateChanged(a{sv})     the same map, when something changes
 *   SetMuted(b)             the watch mic (only while available)
 *   AdjustVolume(i delta)   steps of the call volume, - or +
 *   SendTones(s)            DTMF digits (oFono VoiceCallManager.SendTones)
 *   SetRoute(s)             "watch" or "phone"
 *   PullToWatch()           the audio of a call on the phone to the watch
 * Nothing runs unless `active` (a call view is shown): no signal match, no
 * polling. `present` is true once State() has answered: without the service
 * (a build without call audio support in btsyncd) the launcher shows no Volume,
 * no crown arc and no Mute, rather than controls that do nothing.
 */
QtObject {
    id: audio

    // A call view is up: listen to the state
    property bool active: false
    // btsyncd answered State(): it takes the commands below
    property bool present: false
    // The watch holds the call audio (HFP up for this call)
    property bool available: false
    property bool muted: false
    property string route: "phone"
    // The call volume and its maximum; unknown: -1, 0
    property int volume: -1
    property int volumeMax: 0
    // oFono's state of the call; empty when not known
    property string callState: ""
    // 0..1, or -1 when the volume is not known
    readonly property real level: volumeMax > 0 && volume >= 0 ? Math.min(1, volume / volumeMax) : -1
    // Calling... until the far end answers (calls-20)
    readonly property bool dialing: callState === "dialing" || callState === "alerting"

    function take(state) {
        if (state === null || state === undefined || typeof state !== "object")
            return
        if (state.available !== undefined) available = state.available === true
        if (state.muted !== undefined) muted = state.muted === true
        if (state.route !== undefined) route = String(state.route)
        if (state.volume !== undefined) volume = state.volume
        if (state.volumeMax !== undefined) volumeMax = state.volumeMax
        if (state.callState !== undefined) callState = String(state.callState)
    }

    function refresh() {
        bus.typedCall("State", [], function (s) { audio.present = true; audio.take(s) }, function () { audio.reset() })
    }

    // The service is not there (no call audio on this build): nothing known
    function reset() {
        present = false; available = false; muted = false; route = "phone"; volume = -1; volumeMax = 0; callState = ""
    }

    onActiveChanged: {
        if (active)
            refresh()
        else
            reset()
    }

    function setMuted(on) {
        bus.typedCall("SetMuted", [{ "type": "b", "value": on }], function () {}, function (e, m) { console.log("CallAudio: SetMuted:", e, m) })
    }
    function adjustVolume(delta) {
        bus.typedCall("AdjustVolume", [{ "type": "i", "value": delta }], function () {}, function (e, m) { console.log("CallAudio: AdjustVolume:", e, m) })
    }
    function sendTones(digits) {
        bus.typedCall("SendTones", [{ "type": "s", "value": digits }], function () {}, function (e, m) { console.log("CallAudio: SendTones:", e, m) })
    }
    function setRoute(r) {
        bus.typedCall("SetRoute", [{ "type": "s", "value": r }], function () {}, function (e, m) { console.log("CallAudio: SetRoute:", e, m) })
    }
    function pullToWatch() {
        bus.typedCall("PullToWatch", [], function () {}, function (e, m) { console.log("CallAudio: PullToWatch:", e, m) })
    }

    property QtObject _bus: DBusInterface {
        id: bus
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/callaudio"
        iface: "org.asteroidos.btsyncd.CallAudio"
        signalsEnabled: audio.active
        function stateChanged(state) {
            audio.take(state)
        }
    }
}
