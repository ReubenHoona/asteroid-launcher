/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import Nemo.DBus

/*
 * "Hey Assistant": the assistant daemon listens for the phrase while this is armed (asteroid-assistant
 * Hotword(b), HotwordHeard()). Stock "Hey Google" (Settings > Google > Digital assistant): on by default where
 * the watch has it, "Just say "Hey Google" to talk to your Assistant anytime your watch is fully awake"
 * (com.google.android.wearable.assistant qtg.java:69-77, qsv.java:39-47): never with the screen off, dimmed or
 * always-on. Armed exactly while
 *   - the watch has a detector: /org/asteroidos/assistant/hotword-supported, set by the image that ships one
 *     (unset: none, as image 72; then nothing is ever asked of the daemon),
 *   - Settings > Assistant > "Hey Assistant" is on (/org/asteroidos/assistant/hotword; unset: on, as stock's
 *     hotword-setting-key) and the Assistant itself is on (/org/asteroidos/assistant/enabled),
 *   - awake: the display fully on,
 *   - not blocked (KeyRouter: what stops the side button's hold, and the assistant, a call or touch lock up).
 * The daemon is asked on a change only, no timer and no polling; HotwordHeard is taken only while armed.
 * heard(): the phrase was heard and the daemon stopped listening; it is asked again when it is wanted again.
 */
Item {
    id: arm
    visible: false

    property bool awake: false
    property bool blocked: true
    signal heard()

    property QtObject supportedSetting: ConfigurationValue { key: "/org/asteroidos/assistant/hotword-supported"; defaultValue: false }
    property QtObject hotwordSetting: ConfigurationValue { key: "/org/asteroidos/assistant/hotword"; defaultValue: true }
    property QtObject assistantSetting: ConfigurationValue { key: "/org/asteroidos/assistant/enabled"; defaultValue: true }
    function isOn(v) { return v !== false && String(v) !== "false" }
    readonly property bool supported: supportedSetting.value === true || String(supportedSetting.value) === "true"
    readonly property bool wanted: supported && isOn(hotwordSetting.value) && isOn(assistantSetting.value) && awake && !blocked
    // what the daemon was last asked: listen (true) or not
    property bool armed: false

    onWantedChanged: sync()
    Component.onCompleted: sync()
    function sync() {
        if (wanted === armed)
            return
        armed = wanted
        daemon.typedCall("Hotword", [{ "type": "b", "value": armed }], function () {}, function () {})
    }

    property QtObject daemon: DBusInterface {
        bus: DBus.SessionBus
        service: "org.asteroidos.assistant"
        path: "/org/asteroidos/assistant"
        iface: "org.asteroidos.assistant"
        signalsEnabled: arm.armed
        function rcHotwordHeard() {
            if (!arm.armed)
                return
            // the daemon stopped by itself: what the launcher does next decides whether it is asked again
            arm.armed = false
            arm.heard()
            Qt.callLater(arm.sync)
        }
    }
}
