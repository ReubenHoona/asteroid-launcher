/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * NavAutoLaunch (R5 D-02, apps-misc-10): the phone's turn by turn navigation (btsyncd's PhoneEvent
 * "nav", Gadgetbridge's AsteroidOSNavigation) opens the Maps app on its trip screen (/map/open "nav"),
 * once per trip (the first turn after an end, or after 10 minutes without a turn), with the Maps
 * app's Auto-launch on (/map/autoLaunch, on by default), not over a surface that must not be covered
 * or an app that claimed the keys. The component as the qrc lays it out (st/qml), on the repo's mocks:
 * the bus signals are played with Backend.emitSignal, the app starts are AppLauncher's
 * Backend.calls. Invented streets only.
 */

import QtQuick
import QtTest
import LauncherTest

Item {
    id: testRoot
    width: 384
    height: 384

    Loader { id: loader; active: false; source: Qt.resolvedUrl("st/qml/system/NavAutoLaunch.qml") }

    TestCase {
        id: tc
        name: "NavAutoLaunch"
        when: windowShown

        readonly property string svc: "org.asteroidos.btsyncd"
        readonly property string iface: "org.asteroidos.btsyncd.Assistant"
        readonly property string turn: JSON.stringify({ st: "nav", ins: "Turn left onto Elm Way", di: "100 m", act: "left" })
        readonly property string end: JSON.stringify({ st: "end" })

        function start(conf) {
            loader.active = false
            Backend.reset()
            for (var k in (conf || {}))
                Backend.conf[k] = conf[k]
            loader.active = true
            verify(loader.item, "loaded: " + loader.sourceComponent)
            return loader.item
        }
        function launches() {
            return Backend.calls.filter(function (c) { return c.target === "launcher" && c.method === "launchApp" })
        }
        function opens() {
            return Backend.calls.filter(function (c) { return c.target === "dconf" && c.method === "/map/open" })
        }
        function nav(json) { return Backend.emitSignal(svc, iface, "PhoneEvent", ["nav", json]) }
        function cleanup() { loader.active = false }

        function test_a_trip_opens_the_trip_screen_once() {
            var a = start()
            compare(a.autoLaunchOn, true, "on by default")
            compare(nav(turn), 1, "it takes the relay's PhoneEvent")
            compare(launches().length, 1)
            compare(launches()[0].args, ["asteroid-map"])
            compare(opens().length, 1)
            var v = String(opens()[0].args[0])
            compare(v.indexOf("nav@"), 0, "the trip screen: " + v)
            var ms = Number(v.slice(4))
            verify(Math.abs(ms - Date.now()) < 5000, "when: " + v)
            compare(a.active, true)
            // the next turns of the same trip: nothing
            nav(JSON.stringify({ st: "nav", ins: "Keep right", di: "300 m", act: "keep_right" }))
            nav(turn)
            compare(launches().length, 1)
            // the end, then a new trip
            nav(end)
            compare(a.active, false)
            compare(launches().length, 1)
            nav(turn)
            compare(launches().length, 2, "a new trip opens it again")
        }

        function test_ten_minutes_without_a_turn_is_a_new_trip() {
            var a = start()
            a.phoneEvent("nav", turn, 1000000)
            compare(launches().length, 1)
            a.phoneEvent("nav", turn, 1000000 + 9 * 60000)
            compare(launches().length, 1, "9 minutes: the same trip")
            a.phoneEvent("nav", turn, 1000000 + 9 * 60000 + 10 * 60000 + 1)
            compare(launches().length, 2, "more than 10 minutes since the last turn: a new trip")
        }

        function test_auto_launch_off() {
            var a = start({ "/map/autoLaunch": false })
            compare(a.autoLaunchOn, false)
            nav(turn)
            compare(launches().length, 0)
            compare(opens().length, 0)
            compare(a.active, true, "the trip is followed all the same")
            // switched on during the trip: the trip it missed does not open; the next one does
            Backend.confSet("/map/autoLaunch", true)
            nav(turn)
            compare(launches().length, 0)
            nav(end)
            nav(turn)
            compare(launches().length, 1)
        }

        function test_blocked_and_restricted() {
            var a = start()
            a.blocked = true
            nav(turn)
            compare(launches().length, 0, "not over a call, an alarm, the assistant ...")
            nav(end)
            a.blocked = false
            a.restricted = true
            nav(turn)
            compare(launches().length, 0, "not over a workout")
            nav(end)
            a.restricted = false
            nav(turn)
            compare(launches().length, 1)
        }

        function test_other_events_change_nothing() {
            var a = start()
            Backend.emitSignal(svc, iface, "PhoneEvent", ["cam", JSON.stringify({ ev: "shot" })])
            nav("not json")
            nav("[1,2]")
            nav(JSON.stringify({ st: "what" }))
            compare(launches().length, 0)
            compare(a.active, false)
            // an end with no trip: nothing
            nav(end)
            compare(launches().length, 0)
        }

        function test_nothing_runs() {
            var a = start()
            // no timer: the trip's staleness is worked out when a turn comes
            var timers = []
            for (var i = 0; i < a.data.length; i++)
                if (a.data[i].hasOwnProperty("interval") && a.data[i].hasOwnProperty("repeat"))
                    timers.push(a.data[i])
            compare(timers.length, 0)
            compare(Backend.calls.length, 0, "nothing asked at start")
        }
    }
}
