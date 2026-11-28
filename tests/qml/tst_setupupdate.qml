/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// C-23: the System update step of setup (stock wizard step 9 system_update; setup AUDIT 2.1 row 9). Stock's status
// step goes there only when an update is pending (StatusController.handleNextAction: SystemUpdateManager status
// other than unknown or idle), then SystemUpdateWrapperActivity forces a check (the CHECKIN broadcast) and starts
// the system update screen (SYSTEM_UPDATE_SETTINGS); when that returns, Setup complete. Here: pending is
// eos-update's state staged or installing (dconf /org/asteroidos/eos-update/state); the step starts
// eos-update-check-request.service (user systemd StartUnit, as Settings' UpdatesPage) and asks for Settings' route
// "updates" (ui/open "updates@<ms>", which the launcher's watcher opens); the setup goes on to Setup complete when
// the home is on top again after Settings, or when Settings did not come up at all.
// MODE=st (the staged tree, the repo mocks: Backend records the bus calls and dconf).
import QtQuick
import QtTest
import org.asteroid.controls
import LauncherTest
import "st/qml/firstrun/setup.js" as Setup

Item {
    id: top
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: firstRun
        property int finished: 0
        function startFirstRun() {}
        function bluetoothName() { return "Watch" }
        function keepScreenOn(on) {}
        function armIdlePowerOff(seconds) {}
        function finishSetup() { finished++ }
        function tutorialPending() { return false }
        function timezoneForPosition(lat, lon) { return "" }
        function localDateTime(tz, seconds) { return null }
    }
    QtObject {
        id: bluetoothAgent
        property int state: 0
        property int passkey: 0
        property string pinCode: ""
        function userAccepts() {}
        function userCancels() {}
    }
    QtObject { id: fakeLink; property bool connected: true }

    Loader { id: ld; anchors.fill: parent }

    TestCase {
        name: "SetupUpdate"
        when: windowShown
        property var cfg: null

        readonly property string stateKey: "/org/asteroidos/eos-update/state"
        readonly property string openKey: "/org/asteroidos/settings/ui/open"

        function start(state) {
            Backend.reset()
            if (state !== undefined)
                Backend.confSet(stateKey, state)
            // the phone set the clock and the zone is known: only the update step and Setup complete are left
            Backend.confSet("/org/asteroidos/time/phone-set", true)
            Backend.clearCalls()
            ld.active = false
            ld.setSource(Qt.resolvedUrl("st/qml/firstrun/FirstRunConfig.qml"),
                         { link: fakeLink, zoneNow: function () { return "Etc/GMT-12" } })
            ld.active = true
            tryCompare(ld, "status", Loader.Ready, 20000)
            cfg = ld.item
            return cfg
        }
        function cleanup() {
            ld.active = false
            cfg = null
        }
        function unitStarts() {
            return Backend.calls.filter(function (c) {
                return c.target === "org.freedesktop.systemd1" && c.method === "org.freedesktop.systemd1.Manager.StartUnit"
            })
        }
        function openWrites() {
            return Backend.calls.filter(function (c) { return c.target === "dconf" && c.method === openKey })
        }

        function test_01_pending() {
            verify(Setup.updatePending("staged"))
            verify(Setup.updatePending("installing"))
            for (var s of ["", "current", "trial", "failed", "broken", undefined, null])
                verify(!Setup.updatePending(s), String(s))
            compare(Setup.pages.update, "update")
        }
        function test_02_pages_after_the_bond() {
            compare(Setup.pagesAfterBond("Etc/GMT-12", true, "current"), ["complete"])
            compare(Setup.pagesAfterBond("Etc/GMT-12", true, "staged"), ["update", "complete"])
            compare(Setup.pagesAfterBond("UTC", false, "installing"), ["place", "time", "date", "update", "complete"])
            compare(Setup.pagesAfterBond("UTC", false), ["place", "time", "date", "complete"])
        }
        function test_03_no_update_no_step() {
            start("current")
            cfg.afterConnecting()
            compare(cfg.page, "complete")
            compare(unitStarts().length, 0)
            compare(openWrites().length, 0)
        }
        function test_04_staged_opens_system_update() {
            start("staged")
            var before = Date.now()
            cfg.afterConnecting()
            compare(cfg.page, "update")
            // stock's forced check, the way Settings' UpdatesPage asks for one
            var u = unitStarts()
            compare(u.length, 1)
            compare(u[0].args[0], "eos-update-check-request.service")
            compare(u[0].args[1], "replace")
            // Settings > System update
            var v = String(Backend.confGet(openKey))
            verify(/^updates@\d+$/.test(v), v)
            verify(Number(v.split("@")[1]) >= before)
            // Settings comes on top; the setup waits
            cfg.homeOnTop = false
            wait(200)
            compare(cfg.page, "update")
            // back from Settings: Setup complete
            cfg.homeOnTop = true
            compare(cfg.page, "complete")
            // once
            compare(unitStarts().length, 1)
        }
        function test_05_installing_too() {
            start("installing")
            cfg.afterConnecting()
            compare(cfg.page, "update")
            cfg.homeOnTop = false
            cfg.homeOnTop = true
            compare(cfg.page, "complete")
        }
        function test_06_settings_never_came() {
            start("staged")
            cfg.updateTimer.interval = 300
            cfg.afterConnecting()
            compare(cfg.page, "update")
            tryCompare(cfg, "page", "complete", 3000)
        }
        function test_07_the_home_was_on_top_all_along() {
            // the home on top without Settings having come: no step forward but by the timer
            start("staged")
            cfg.afterConnecting()
            cfg.homeOnTop = true
            wait(200)
            compare(cfg.page, "update")
            // the screen is black meanwhile (stock's step shows nothing of its own); no swipe back
            verify(!cfg.backEnabled)
        }
        function test_08_finish_after_the_step() {
            start("staged")
            cfg.afterConnecting()
            cfg.homeOnTop = false
            cfg.homeOnTop = true
            compare(cfg.page, "complete")
            cfg.finish()
            compare(firstRun.finished, 1)
        }
    }
}
