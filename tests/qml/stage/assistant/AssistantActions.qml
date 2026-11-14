/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// Test double for the assistant's actions (the real file needs alarms, MPRIS,
// calendar, connman): what the overlay calls is run(), answered with the card
// Backend.replies["actions.run"] names (else a plain one)
import QtQuick
import LauncherTest

Item {
    function run(intent, slots, transcript, done) {
        Backend.record("actions", "run", [intent])
        var c = Backend.replies["actions.run"]
        done(c !== undefined ? c : { icon: "ios-timer-outline", title: "", text: "Timer set", chips: [] })
    }
}
