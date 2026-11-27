/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import Nemo.Configuration
import org.asteroid.launcher

/* Auto-launch of the Maps trip screen (R5 D-02, apps-misc-10; stock Maps' "Auto-launch",
 * auto_launch_watch_title, watch_auto_launch_header "When navigating on your phone, auto-launch the
 * trip on watch"; the user's yes, Q57): when the phone starts a turn by turn navigation (Gadgetbridge's
 * PhoneEvent "nav" through btsyncd's assistant relay, AsteroidOSNavigation) the Maps app opens on its
 * trip screen (dconf /map/open "nav@<ms>", read by asteroid-map at start and on change, as the tiles ask
 * the other apps, contract row CR-36), once per trip: a trip is the turns from
 * the first {"st":"nav"} to {"st":"end"}, or to 10 minutes without a turn (Gadgetbridge's rule). The
 * setting is the Maps app's (Settings in the app, dconf /map/autoLaunch, on by default). Not over the
 * surfaces that must not be covered (a call, a firing alarm, the assistant, setup, the emergency
 * screens, the touch lock), not over an app that claimed the keys (a workout), as MediaAutoLaunch.
 * The display is not turned on: the trip screen is there at the next wake (the app makes no map and
 * reads no sensor for it). The app closes itself when the trip ends.
 * Battery: the events come only while the phone navigates, on the relay's D-Bus signals the launcher
 * already takes (AssistantActions); nothing polls, no timer. */
Item {
    id: auto
    objectName: "navAutoLaunch"
    visible: false

    /* a surface that must not be covered is up */
    property bool blocked: false
    /* the app in front claimed the side button or the crown */
    property bool restricted: false

    readonly property int staleMs: 600000
    readonly property bool autoLaunchOn: setting.value !== false && setting.value !== "false"
    // a trip is on, and when its last turn came (ms since the epoch)
    property bool active: false
    property double lastAt: 0
    // what was opened (the test reads it)
    property int launches: 0
    property string lastLaunched: ""

    ConfigurationValue { id: setting; key: "/map/autoLaunch"; defaultValue: true }
    ConfigurationValue { id: openRequest; key: "/map/open"; defaultValue: "" }
    AppLauncher { id: launcher }

    DBusInterface {
        id: relay
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/assistant"
        iface: "org.asteroidos.btsyncd.Assistant"
        signalsEnabled: true
        function rcPhoneEvent(kind: string, json: string) { auto.phoneEvent(kind, json, Date.now()) }
    }

    function phoneEvent(kind, json, now) {
        if (kind !== "nav")
            return
        var o
        try { o = JSON.parse(json) } catch (e) { return }
        if (!o || typeof o !== "object")
            return
        if (o.st === "end") {
            active = false
            return
        }
        if (o.st !== "nav")
            return
        var fresh = !active || now - lastAt > staleMs
        active = true
        lastAt = now
        if (fresh && autoLaunchOn && !blocked && !restricted)
            open()
    }

    function open() {
        // the app reads the request at start (and while it runs) and clears it
        openRequest.value = "nav@" + Date.now()
        launcher.launchApp("asteroid-map")
        launches++
        lastLaunched = "asteroid-map"
    }
}
