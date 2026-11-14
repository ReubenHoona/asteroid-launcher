/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Mce
import Nemo.DBus
import Connman
import org.asteroid.utils
import org.nemomobile.lipstick
import "status.js" as Status

/* Where the face status icon's states come from (W2-launcher-status; audit
 * status-indicators-03, -22). Every input is a binding on a signal of the
 * thing it reads (modes, mce, connman, btsyncd, the registry's claims): no
 * timer, no polling. The rules are status.js'; `current` is the one type the
 * face shows, `active` the 16 booleans.
 *
 * Not built, no source on this watch yet (the inputs exist, false, for the
 * package that adds each): thermal mode, water lock, safety signal, screen
 * lock (PIN/pattern, W3), LTE disconnected (the modem is off until M7).
 * Touch lock, microphone and location come from the registry's claims
 * (compositor.qml sets the touch lock and the assistant's microphone; an app
 * claims with org.asteroidos.launcher.Ongoing SetInUse). */
Item {
    id: sources
    visible: false
    width: 0
    height: 0

    readonly property bool modesReady: typeof modes !== "undefined" && modes !== null
    readonly property QtObject registry: typeof ongoingRegistry !== "undefined" ? ongoingRegistry : null

    // plugged in: mce's charger type (the home screen's shared id)
    property bool charging: typeof mceChargerType !== "undefined" && mceChargerType !== null
                            && mceChargerType.type !== MceChargerType.None
    property bool batterySaver: modesReady && modes.batterySaver === true
    property bool bedtime: modesReady && modes.bedtime === true
    property bool theater: modesReady && modes.theater === true
    property bool dnd: modesReady && modes.doNotDisturb === true
    // mce's level, -1 until known; the low level follows Settings > Battery > Battery Saver > Turn on at N %
    property int batteryLevel: modesReady ? modes.batteryLevel : -1
    property int lowTrigger: modesReady && modes.autoSaverOn === true ? modes.autoSaverOnLevel : 0
    // connman's offline mode is Airplane mode (QuickPanel)
    property bool airplane: connman.offlineMode === true
    property bool btPowered: btStatus.powered
    property bool wifiConnected: wifi.powered && wifi.connected
    // asteroid-btsyncd's phone link; unknown until it has answered or said
    property bool phoneKnown: false
    property bool phoneConnected: false
    property bool touchLock: registry !== null && registry.touchLocked === true
    property bool mic: registry !== null && registry.micInUse === true
    property bool location: registry !== null && registry.locationInUse === true
    property bool waterLock: false
    property bool thermal: false
    property bool safety: false
    property bool screenLock: false
    property bool lteDisconnected: false

    readonly property var active: Status.evaluate({
        thermal: thermal, touchLock: touchLock, waterLock: waterLock, mic: mic, location: location,
        safety: safety, screenLock: screenLock, charging: charging, airplane: airplane,
        btPowered: btPowered, wifiConnected: wifiConnected, lteDisconnected: lteDisconnected,
        phoneKnown: phoneKnown, phoneConnected: phoneConnected, bedtime: bedtime, theater: theater,
        dnd: dnd, batterySaver: batterySaver, batteryLevel: batteryLevel, lowTrigger: lowTrigger })
    readonly property string current: Status.current(active)
    // which wet kind holds the slot (Touch lock on / Water lock on)
    readonly property string wetKind: waterLock ? "water" : "touch"
    readonly property string slotKey: Status.slotKey(current, wetKind)

    NetworkManager { id: connman }
    NetworkTechnology { id: wifi; path: "/net/connman/technology/wifi" }
    BluetoothStatus { id: btStatus }

    DBusInterface {
        id: phoneBus
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/phone"
        iface: "org.asteroidos.btsyncd.Phone"
        signalsEnabled: true
        function rcConnectedChanged(connected: bool) {
            sources.phoneKnown = true
            sources.phoneConnected = connected
        }
    }
    // Ask once; btsyncd not there yet leaves it unknown (no icon), its signal or the next screen on settles it
    function ask() {
        phoneBus.typedCall("Connected", [], function (c) {
            sources.phoneKnown = true
            sources.phoneConnected = c
        }, function () { })
    }
    Component.onCompleted: ask()
    Connections {
        target: Lipstick.compositor
        function onDisplayOn() {
            if (!sources.phoneKnown)
                sources.ask()
        }
    }
}
