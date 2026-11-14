/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import "a11y.js" as A11y

/*
 * The screen reader's skeleton (W3-launcher-a11y-security,
 * accessibility-lock-security-18; DECISIONS.md Q43: build it, it needs a TTS
 * engine). Stock is TalkBack (TalkbackFragment, TalkBack's values-watch):
 * Settings > Accessibility > TalkBack switch with the "full control" dialog,
 * the Button shortcut (triple press of the side button, KeyRouter), the focus
 * ring (#bf39b500, 4 dp, thick 6 dp), the Wear gestures (A11y.swipeAction and
 * tapAction), and, while it is on, Always-on screen, Tilt-to-wake and Raise
 * to talk off ("TalkBack is on").
 *
 * What is here: the on/off state and the shortcut (the names KeyRouter and
 * the SOS countdown already read: shortcutEnabled, toggle(), touchExploring),
 * the dconf keys, the focus ring over a node, traversal (next, previous,
 * activate) over the nodes a provider lists, the gesture map, the spoken text
 * through `speaker` when the image has one, and the always-on screen forced
 * off while it is on (saved and put back).
 *
 * What is not: the nodes of the other applications' windows (a Qt
 * accessibility bridge to the compositor: only items of the launcher with
 * Accessible.* can be listed), the explore-by-touch filter in the compositor,
 * and the TTS engine itself (espeak-ng or piper is not in the image). Until
 * those exist `available` is false and the shortcut stays off: the switch in
 * Settings must not be shown. See pkg/W3-launcher-a11y-security/NOTES.md.
 *
 * dconf: /org/asteroidos/a11y/screen-reader (b), -button-shortcut (b),
 * -speech-rate (i, 60 to 400, 100).
 */
Item {
    id: sr
    objectName: "screenReader"
    anchors.fill: parent

    // a TTS engine and a node provider exist (the image sets these when they do)
    property bool available: false
    // object with say(text, rate) and stop(); null when the image has no engine
    property QtObject speaker: typeof speech !== "undefined" ? speech : null
    // function () -> [{ name, role, x, y, width, height, activate: function, longPress: function }] in reading order
    property var provider: null

    ConfigurationValue {
        id: onSetting
        key: "/org/asteroidos/a11y/screen-reader"
        defaultValue: false
    }
    ConfigurationValue {
        id: shortcutSetting
        key: "/org/asteroidos/a11y/screen-reader-button-shortcut"
        defaultValue: false
    }
    ConfigurationValue {
        id: rateSetting
        key: "/org/asteroidos/a11y/screen-reader-speech-rate"
        defaultValue: A11y.SPEECH_RATE_NORMAL
    }
    // Settings > Display > Always-on screen: put back when the reader goes off
    ConfigurationValue {
        id: aodSetting
        key: "/org/asteroidos/settings/always-on-display"
        defaultValue: true
    }

    readonly property bool running: available && (onSetting.value === true || onSetting.value === "true")
    readonly property bool shortcutEnabled: available && (shortcutSetting.value === true || shortcutSetting.value === "true")
    readonly property bool touchExploring: running
    readonly property int speechRate: Math.max(A11y.SPEECH_RATE_MIN, Math.min(A11y.SPEECH_RATE_MAX, Math.round(Number(rateSetting.value))))
    property bool thick: false

    // the node in focus
    property var nodes: []
    property int focusIndex: -1
    readonly property var focused: focusIndex >= 0 && focusIndex < nodes.length ? nodes[focusIndex] : null
    // what was said last (the tests)
    property string lastSpoken: ""
    // the always-on screen was on when the reader came up
    property var savedAod: undefined

    signal volumeStep(int direction)
    signal scrollRequested(string direction)
    signal mediaRequested()

    function toggle() {
        if (!available)
            return
        onSetting.value = !running
    }

    function say(text) {
        lastSpoken = text
        if (speaker !== null && running)
            speaker.say(text, speechRate)
    }

    function refresh() {
        nodes = provider ? provider() : []
        if (focusIndex >= nodes.length)
            focusIndex = nodes.length - 1
    }

    function focusNode(i) {
        refresh()
        if (i < 0 || i >= nodes.length)
            return
        focusIndex = i
        say(nodes[i].name)
    }

    function next() { focusNode(focusIndex < 0 ? 0 : Math.min(nodes.length - 1, focusIndex + 1)) }
    function previous() { focusNode(focusIndex < 0 ? 0 : Math.max(0, focusIndex - 1)) }

    function activate() {
        if (focused && focused.activate)
            focused.activate()
    }

    /* one finger touching or exploring: the node under it takes the focus */
    function explore(x, y) {
        refresh()
        for (var i = nodes.length - 1; i >= 0; i--) {
            var n = nodes[i]
            if (x >= n.x && x < n.x + n.width && y >= n.y && y < n.y + n.height) {
                if (i !== focusIndex)
                    focusNode(i)
                return true
            }
        }
        return false
    }

    /* the Wear gestures (A11y.swipeAction, tapAction) */
    function swipe(fingers, dir, second) {
        switch (A11y.swipeAction(fingers, dir, second || "")) {
        case "next": next(); break
        case "previous": previous(); break
        case "volumeUp": volumeStep(1); break
        case "volumeDown": volumeStep(-1); break
        case "scrollUp": case "scrollDown": case "scrollLeft": case "scrollRight":
            scrollRequested(A11y.swipeAction(fingers, dir, second || "")); break
        default: break
        }
    }

    function tapGesture(fingers, taps, held) {
        switch (A11y.tapAction(fingers, taps, held === true)) {
        case "activate": activate(); break
        case "longPress": if (focused && focused.longPress) focused.longPress(); break
        case "media": mediaRequested(); break
        default: break
        }
    }

    // on: the always-on screen goes off (TalkBack is on), and comes back as it was
    onRunningChanged: {
        if (running) {
            savedAod = aodSetting.value
            aodSetting.value = false
        } else {
            focusIndex = -1
            if (savedAod !== undefined) {
                aodSetting.value = savedAod
                savedAod = undefined
            }
        }
    }

    // the focus ring: 4 dp (6 dp thick), #bf39b500
    Rectangle {
        id: ring
        objectName: "screenReaderRing"
        visible: sr.running && sr.focused !== null
        x: sr.focused ? sr.focused.x : 0
        y: sr.focused ? sr.focused.y : 0
        width: sr.focused ? sr.focused.width : 0
        height: sr.focused ? sr.focused.height : 0
        color: "transparent"
        radius: Theme.dp(8)
        border.width: Theme.dp(sr.thick ? A11y.FOCUS_THICK_DP : A11y.FOCUS_WIDTH_DP)
        border.color: A11y.FOCUS_COLOR
    }
}
