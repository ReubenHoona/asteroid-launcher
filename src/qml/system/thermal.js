/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* The thermal notices of the launcher (power-boot-warnings-12), as stock's ThermalUiImpl
 * (CSUI modes/thermal): the numbers and the state words. The source of the state is not the launcher's:
 * a thermal monitor (meta-eos64 eos-cool, event driven from the kernel's thermal events) writes the dconf
 * key /org/asteroidos/thermal/state, and /org/asteroidos/thermal/shutdown-notice at the first boot after a
 * thermal shutdown; the launcher only shows what it is told. Pure functions: tests tst_thermal.qml. */

// the keys
var STATE_KEY = "/org/asteroidos/thermal/state"
var SHUTDOWN_KEY = "/org/asteroidos/thermal/shutdown-notice"

// the states the monitor writes
var STATE_NONE = "none"
var STATE_WARNING = "warning"
var STATE_COOLDOWN = "cooldown"

// "Watch will enter cooldown mode in 15 seconds": the monitor moves from warning to cooldown by itself
var WARNING_SECONDS = 15
// the "Cooling down..." screen: 3000 ms (cooldown_dialog), then the touch-blocking overlay
var COOLING_SCREEN_MS = 3000
// a tap on the blocked screen shows the overheated card for this long (our choice: stock's card has no timeout
// in the evidence) and the overlay takes the touches again
var OVERHEATED_CARD_MS = 3000
// the thermostat icon of the "Cooling down" screen: 48 dp, its top at 32 % of the height; of the overheated card:
// at 12 % (thermal layouts)
var COOLING_ICON_DP = 48
var COOLING_ICON_TOP = 0.32
var OVERHEATED_ICON_TOP = 0.12
// the battery above this is a thermal shutdown (tenths of a degree: config_shutdownBatteryTemperature 605)
var SHUTDOWN_BATTERY_TENTHS_C = 605

// the phase of the screens for the state the monitor wrote and what is on now
function phaseFor(state, current) {
    if (state === STATE_WARNING)
        // a warning already dismissed stays dismissed until the state changes
        return current === "warningDismissed" ? "warningDismissed" : "warning"
    if (state === STATE_COOLDOWN)
        return current === "blocked" || current === "overheated" ? current : "cooling"
    return "none"
}

// the screens that cover the face and take every touch
function blocks(phase) { return phase === "cooling" || phase === "blocked" || phase === "overheated" }

// a thermal state that shows something
function shows(phase) { return phase === "warning" || blocks(phase) }
