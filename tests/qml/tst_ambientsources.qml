// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause
//
// The face complications in the always-on screen (D60-03): ComplicationSources
// (src/qml/complications/ComplicationSources.qml) and the stale kinds of
// src/qml/home/ambient.js on the repo mocks (MceBatteryLevel and MceBatteryState
// on Backend.batteryPercent / batteryState, btsyncd's phone on Backend.replies).
// Staged as module LauncherQml: complications/ComplicationSources.qml,
// ComplicationView.qml, complications.js, the ClockSource.qml double of
// tests/qml/stage, desktop.js and home/ambient.js as the launcher's qrc lays
// them out.
import QtQuick
import QtTest
import LauncherTest
import LauncherQml
import "LauncherQml/home/ambient.js" as Ambient

Item {
    id: root
    width: 384
    height: 384

    ComplicationSources {
        id: sources
        active: true
        now: new Date(2026, 10, 2, 10, 9, 0)
    }

    // what a ComplicationView registers (refreshDemand reads source and slotItem)
    function slot(id) { return { source: id, slotItem: null } }
    property var shown: []
    function show(id) {
        var v = slot(id)
        shown.push(v)
        sources.register(v)
        return v
    }

    TestCase {
        name: "AmbientSources"
        when: windowShown

        function init() {
            Backend.reset()
            sources.active = true
            sources.ambient = false
            sources.hubDrawn = false
            sources.unread = 0
        }
        function cleanup() {
            for (var i = 0; i < shown.length; i++)
                sources.unregister(shown[i])
            shown = []
            tryVerify(function () { return JSON.stringify(sources.demand) === "{}" }, 1000, "no slot shows anything")
        }
        // the screen off into the always-on screen that the sensor hub draws
        function toHubAlwaysOn() {
            sources.active = false
            sources.ambient = true
            sources.hubDrawn = true
        }

        function test_01_battery_is_not_stale() {
            verify(!Ambient.complicationStale("battery", true))
            verify(!Ambient.complicationStale("phonebattery", true))
            // the live data the hub cannot draw stays '--' there
            var stale = ["timedate", "worldclock", "steps", "heartrate", "notifications", "nextevent", "sun",
                         "timer", "stopwatch", "media", "calories", "floors", "azm"]
            compare(Ambient.STALE_KINDS, stale)
            for (var i = 0; i < stale.length; i++) {
                verify(Ambient.complicationStale(stale[i], true), stale[i])
                verify(!Ambient.complicationStale(stale[i], false), stale[i] + " where the AP draws")
            }
        }

        function test_02_battery_number_in_hub_always_on() {
            show("battery")
            tryVerify(function () { return sources.demand.battery === true })
            var d = sources.info("battery")
            compare(d.text, "57")
            compare(d.icon, "ios-battery-full")
            toHubAlwaysOn()
            d = sources.info("battery")
            compare(d.ambient, true)
            compare(d.text, "57")
            compare(d.short, "57")
            compare(d.long, "Battery: 57")
            compare(d.icon, "ios-battery-full")
            compare(d.known, true)
            compare(d.type, "ranged")
            // a new level while the screen is in always-on is read there
            Backend.batteryPercent = 56
            compare(sources.info("battery").text, "56")
            Backend.batteryPercent = 29
            compare(sources.info("battery").text, "29")
            compare(sources.info("battery").icon, "ios-battery-dead")
            // and with the screen off
            sources.ambient = false
            sources.hubDrawn = false
            Backend.batteryPercent = 28
            compare(sources.info("battery").text, "28")
        }

        function test_03_phone_battery_in_hub_always_on() {
            show("phonebattery")
            tryVerify(function () { return sources.demand.phonebattery === true })
            compare(sources.info("phonebattery").text, "80%")
            toHubAlwaysOn()
            compare(sources.info("phonebattery").text, "80%")
            compare(sources.info("phonebattery").icon, "ios-phone-portrait")
            // the phone's new level comes on the bus in always-on
            compare(Backend.emitSignal("org.asteroidos.btsyncd", "org.asteroidos.btsyncd.Phone", "BatteryChanged", [79, false]), 1)
            compare(sources.info("phonebattery").text, "79%")
        }

        function test_04_no_glyph_by_dashes() {
            show("steps")
            show("notifications")
            show("battery")
            tryVerify(function () { return sources.demand.steps === true && sources.demand.notifications === true })
            sources.unread = 3
            compare(sources.info("notifications").icon, "ios-notifications")
            toHubAlwaysOn()
            var d = sources.info("steps")
            compare(d.text, "--")
            compare(d.icon, "")
            compare(d.type, "short")
            d = sources.info("notifications")
            compare(d.text, "--")
            compare(d.icon, "", "no filled bell by '--'")
            compare(d.type, "short")
            // a battery level not known yet: '--' and no level glyph, awake and in always-on
            Backend.batteryPercent = -1
            d = sources.info("battery")
            compare(d.text, "--")
            compare(d.icon, "")
            compare(d.type, "short")
            sources.active = true
            sources.ambient = false
            sources.hubDrawn = false
            compare(sources.info("battery").text, "--")
            compare(sources.info("battery").icon, "")
        }

        function test_05_hub_values() {
            // nothing shown: nothing for the hub's layout to follow
            compare(sources.hubValues, "/")
            show("battery")
            tryCompare(sources, "hubValues", "57/")
            toHubAlwaysOn()
            compare(sources.hubValues, "57/")
            // every whole percent is a new layout, charging too (the icon changes)
            Backend.batteryPercent = 56
            compare(sources.hubValues, "56/")
            Backend.batteryState = 1
            compare(sources.hubValues, "56+/")
            show("phonebattery")
            tryCompare(sources, "hubValues", "56+/80")
            // the same values across the screen's own changes (the phone asked again at the
            // screen on): the hub's layout is not rebuilt for them
            var seen = []
            var f = function () { seen.push(sources.hubValues) }
            sources.hubValuesChanged.connect(f)
            sources.active = true
            sources.ambient = false
            sources.hubDrawn = false
            toHubAlwaysOn()
            sources.hubValuesChanged.disconnect(f)
            compare(seen, [])
            compare(sources.hubValues, "56+/80")
            Backend.emitSignal("org.asteroidos.btsyncd", "org.asteroidos.btsyncd.Phone", "BatteryChanged", [79, false])
            compare(sources.hubValues, "56+/79")
            Backend.emitSignal("org.asteroidos.btsyncd", "org.asteroidos.btsyncd.Phone", "ConnectedChanged", [false])
            compare(sources.hubValues, "56+/-1")
        }
    }
}
