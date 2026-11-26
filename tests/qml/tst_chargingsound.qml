/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// The charger's plug-in feedback (src/qml/home/ChargingController.qml, FP-C1) on the repo mocks: the
// Nemo.Ngf double records every event it plays with its properties (Backend.calls, target "ngfd"),
// Nemo.Mce's charger type is Backend.chargerType, the display request is the mce DBusInterface's call.
// As stock's charging screen (SysUI ChargingComposeActivity, imd.java: customized_charging_started once
// on a plug-in, with Charging sounds on and the screen on), a plug-in plays ngfd's eos_charging_sound
// once, audio only: with Settings > Sound > Charging sounds on, when the plug-in wakes the screen (not
// in Bedtime or Theater), not in Do Not Disturb. No plug-in vibration: stock plays none (Wear Settings'
// BootReceiver turns charging_sounds_enabled off at every boot), so charging_started is never sent.
// MODE=st (the staged tree).
import QtQuick
import QtTest
import LauncherTest
import "st/qml/home" as Home

Item {
    id: top
    width: 384
    height: 384

    // the launcher's modes engine (main.cpp's context property "modes")
    QtObject {
        id: modes
        property bool theater: false
        property bool bedtime: false
        property bool doNotDisturb: false
    }

    Component { id: controllerC; Home.ChargingController { } }

    TestCase {
        name: "ChargingSound"

        readonly property string soundKey: "/org/asteroidos/sound/charging"

        function init() {
            Backend.reset()
            modes.theater = false
            modes.bedtime = false
            modes.doNotDisturb = false
        }
        function make() {
            var c = createTemporaryObject(controllerC, top)
            verify(c !== null)
            verify(c.ready)
            return c
        }
        // the ngfd events played (all, or the ones of this name)
        function played(event) {
            var l = []
            for (var i = 0; i < Backend.calls.length; i++) {
                var k = Backend.calls[i]
                if (k.target === "ngfd" && (event === undefined || k.method === event))
                    l.push(k)
            }
            return l
        }
        // the display requests (mce req_display_state_on)
        function wakes() {
            var n = 0
            for (var i = 0; i < Backend.calls.length; i++)
                if (Backend.calls[i].target === "com.nokia.mce"
                        && Backend.calls[i].method === "com.nokia.mce.request.req_display_state_on")
                    n++
            return n
        }
        function plugIn(type) {
            Backend.batteryState = 1                  // MceBatteryState.Charging
            Backend.chargerType = type === undefined ? 1 : type
        }
        function unplug() {
            Backend.chargerType = 0
            Backend.batteryState = 2                  // MceBatteryState.Discharging
        }
        function readText(path) {
            var x = new XMLHttpRequest()
            x.open("GET", Qt.resolvedUrl(path), false)
            x.send()
            return x.responseText
        }

        function test_01_plug_in_plays_the_sound_once_audio_only() {
            var c = make()
            compare(played().length, 0, "nothing at the start")
            plugIn()
            verify(c.plugged && c.shown)
            var s = played()
            compare(s.length, 1, "one event on a plug-in")
            compare(s[0].method, "eos_charging_sound")
            // audio only: the request names media.audio and nothing else (ngfd's resource plugin then
            // turns the vibration and the LEDs off)
            compare(s[0].args[0]["media.audio"], true)
            compare(Object.keys(s[0].args[0]).length, 1)
            compare(wakes(), 1, "the plug-in wakes the screen")
            // still plugged, another charger type: no new plug-in, nothing plays
            Backend.chargerType = 2
            compare(played().length, 1)
            // the unplug plays nothing
            unplug()
            verify(!c.plugged)
            compare(played().length, 1)
            // the next plug-in plays it again, once
            plugIn(5)
            compare(played("eos_charging_sound").length, 2)
            compare(played().length, 2)
            compare(played("charging_started").length, 0, "no plug-in vibration")
        }

        function test_02_display_off_plug_in_wakes_and_sounds() {
            var c = make()
            c.displayOff = true
            plugIn()
            compare(wakes(), 1)
            compare(played("eos_charging_sound").length, 1)
        }

        function test_03_charging_sounds_off() {
            Backend.confSet(soundKey, false)
            var c = make()
            verify(!c.chargingSoundOn)
            plugIn()
            verify(c.shown, "the screen as usual")
            compare(wakes(), 1, "the wake as usual")
            compare(played().length, 0, "no sound with Charging sounds off")
            unplug()
            // turned on again: the next plug-in sounds
            Backend.confSet(soundKey, true)
            verify(c.chargingSoundOn)
            plugIn()
            compare(played("eos_charging_sound").length, 1)
            unplug()
            // dconf may hand it back as a string
            Backend.confSet(soundKey, "false")
            verify(!c.chargingSoundOn)
            plugIn()
            compare(played().length, 1)
        }

        function test_04_do_not_disturb() {
            modes.doNotDisturb = true
            var c = make()
            plugIn()
            verify(c.shown)
            compare(wakes(), 1, "Do Not Disturb keeps the wake")
            compare(played().length, 0, "no sound in Do Not Disturb")
            // the mode going off later plays nothing: the sound belongs to the plug-in
            modes.doNotDisturb = false
            compare(played().length, 0)
        }

        function test_05_bedtime_and_theater() {
            modes.bedtime = true
            var c = make()
            plugIn()
            verify(c.shown)
            compare(wakes(), 0, "Bedtime: the screen stays dark")
            compare(played().length, 0, "no sound in Bedtime")
            unplug()
            modes.bedtime = false
            modes.theater = true
            plugIn()
            compare(wakes(), 0, "Theater: the screen stays dark")
            compare(played().length, 0, "no sound in Theater")
            unplug()
            modes.theater = false
            plugIn()
            compare(played("eos_charging_sound").length, 1)
        }

        function test_06_a_charger_at_the_start_is_no_plug_in() {
            plugIn()
            var c = make()
            verify(c.plugged && c.shown)
            compare(played().length, 0, "a relaunch on the charger plays nothing")
            compare(wakes(), 0)
            unplug()
            plugIn()
            compare(played("eos_charging_sound").length, 1)
        }

        // nothing sends the plug-in vibration any more (compositor.qml played ngfd's charging_started
        // through Haptics on the controller's plugFeedback)
        function test_07_no_plug_in_vibration() {
            var comp = readText("st/qml/compositor.qml")
            var ctrl = readText("st/qml/home/ChargingController.qml")
            verify(comp.length > 1000 && ctrl.length > 1000, "the staged sources")
            compare(comp.indexOf("\"charging_started\""), -1)
            compare(ctrl.indexOf("\"charging_started\""), -1)
            compare(comp.indexOf("onPlugFeedback"), -1)
            compare(ctrl.indexOf("plugFeedback"), -1)
            verify(ctrl.indexOf("event: \"eos_charging_sound\"") >= 0)
        }
    }
}
