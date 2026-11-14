/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *               2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
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
import Nemo.Mce
import Nemo.DBus
import "../charging/charging.js" as Charging

/* The charger (W2-launcher-charging): when the charging screen is up, the wake on plug and
 * unplug, the relaunch at every screen off, the charging quality screen. Replaces the
 * nightstand mode this file held (DECISIONS.md Q34: the stock charging screen only; no
 * nightstand face, brightness, delay or switch; always-on follows Display > Always-on
 * screen). Instantiated once in compositor.qml as `charging`; ChargingScreen.qml,
 * ChargerProblem.qml and the key map read it. The rules are charging.js.
 *
 *  - plug-in (charging-battery-02): the screen is up and the display is asked to come on
 *    (mce req_display_state_on: it then follows the normal screen timeout), except in
 *    Theater and Bedtime (the screen stays dark); the intro plays when the display is on.
 *    mce's own 3 s tklock exception for the charger is set to 0 in 62eos-battery.conf.
 *  - unplug (charging-battery-03): the display is asked to come on the same way; the screen
 *    stays 1000 ms and fades away (the slow effects spring), at once if the display is dark.
 *    The brightness is never touched: there is no nightstand brightness any more.
 *  - screen off while plugged: the screen is up again for the next wake, no intro, no wake.
 *    So it is at the start of the launcher. The crown closes it (dismiss) until the next
 *    screen off.
 *  - charging quality (app-inventory-03): a charger is connected, the battery is not full and
 *    charging has not started for 30 s with the display on: 'Check if charger is aligned and
 *    has power'. It goes with the charger or when charging starts. The moisture and
 *    unsupported-charger states have no source on eos (the PMIC driver reports neither), so
 *    their screens exist (ChargerProblem) but nothing selects them yet.
 *
 * Power (M1): no polling. Two one-shot timers (1 s after an unplug, 30 s of a charger that is
 * not charging), both only with the display on; the display off stops them. */
Item {
    id: charging
    objectName: "eosChargingController"
    width: 0
    height: 0

    // the display is off or in the always-on screen (compositor.qml: comp.displayIsOff)
    property bool displayOff: false
    // the modes that keep the screen dark
    readonly property bool theater: typeof modes !== "undefined" && modes !== null && modes.theater === true
    readonly property bool bedtime: typeof modes !== "undefined" && modes !== null && modes.bedtime === true
    readonly property bool dnd: typeof modes !== "undefined" && modes !== null && modes.doNotDisturb === true

    // the plug-in vibration: compositor.qml plays ngfd's charging_started (Haptics, which keeps the
    // vibration and Using crown switches)
    signal plugFeedback()

    MceChargerType { id: chargerType }
    MceChargerState { id: chargerState }
    MceBatteryStatus { id: batteryStatus }
    MceBatteryLevel { id: batteryLevel }

    readonly property bool plugged: chargerType.valid && chargerType.type !== MceChargerType.None

    // the screen is up; the next show plays the intro; the hide fades; the crown closed it
    property bool shown: false
    property bool intro: false
    property bool fade: false
    property bool dismissed: false
    property bool lingering: false

    // the charging quality screen: "", or the state shown
    property string problem: ""
    property bool problemDismissed: false
    readonly property string problemKind: problemDismissed ? "" : problem
    // anything of the charger covers the screen (the crown, the swipe back)
    readonly property bool up: shown || problemKind !== ""

    function update() {
        shown = Charging.screenUp(plugged, dismissed, lingering)
    }

    // ask mce for the display (the normal dim and blank timers follow)
    property DBusInterface mce: DBusInterface {
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
        bus: DBus.SystemBus
    }
    function wakeDisplay() {
        mce.call("req_display_state_on", undefined)
    }

    // the handlers act on changes after the start only: a charger connected when the launcher
    // starts is a relaunch (no wake, no intro), not a plug-in
    property bool ready: false

    onPluggedChanged: {
        if (!ready)
            return
        var wasUp = !plugged && !dismissed
        var r = Charging.plugChange({ plugged: plugged, was: !plugged, theater: theater, bedtime: bedtime,
                                      dnd: dnd, displayOff: displayOff })
        holdTimer.stop()
        if (r.show) {
            lingering = false
            dismissed = false
            fade = false
            intro = r.intro
        } else {
            // unplugged: the 1 s only if the screen was up
            dismissed = false
            intro = false
            if (r.linger && wasUp) {
                fade = true
                lingering = true
                holdTimer.start()
            } else {
                lingering = false
            }
        }
        update()
        if (r.wake)
            wakeDisplay()
        if (r.feedback)
            plugFeedback()
    }

    // 1000 ms after the unplug the screen finishes (it fades away)
    Timer {
        id: holdTimer
        objectName: "eosChargingHold"
        interval: Charging.UNPLUG_HOLD_MS
        repeat: false
        onTriggered: {
            charging.lingering = false
            charging.update()
        }
    }

    // a screen off while plugged: the screen is up again for the next wake, without the intro
    onDisplayOffChanged: {
        if (ready && displayOff) {
            holdTimer.stop()
            lingering = false
            dismissed = false
            intro = false
            update()
        }
    }

    // the crown: the problem screen first, then the charging screen, until the next screen off
    function dismiss() {
        if (problemKind !== "") {
            problemDismissed = true
            return true
        }
        if (shown) {
            holdTimer.stop()
            lingering = false
            dismissed = true
            update()
            return true
        }
        return false
    }

    // ---- the charging quality screen
    readonly property bool full: batteryStatus.status === MceBatteryStatus.Full || batteryLevel.percent >= 100
    readonly property bool problemArmed: chargerState.valid && !displayOff
        && Charging.misaligned({ plugged: plugged, charging: chargerState.charging, full: full })
    onProblemArmedChanged: {
        if (!ready)
            return
        if (problemArmed) {
            problemTimer.restart()
        } else {
            problemTimer.stop()
            problem = ""
            problemDismissed = false
        }
    }
    Timer {
        id: problemTimer
        objectName: "eosChargingProblemTimer"
        interval: Charging.PROBLEM.misalignedAfterMs
        repeat: false
        onTriggered: charging.problem = "misaligned"
    }

    Component.onCompleted: {
        ready = true
        update()
        // a charger that is already not charging: the 30 s start now
        if (problemArmed)
            problemTimer.restart()
    }
}
