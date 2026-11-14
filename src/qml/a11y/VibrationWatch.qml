/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.utils
import "a11y.js" as A11y

/*
 * Vibration watch (W3-launcher-a11y-security, accessibility-lock-security-21):
 * stock Settings > Accessibility > Vibration watch (ClockworkSystemUI
 * a11y/vibrationwatch). With the screen on, a tap on the watch face with two
 * fingers vibrates the hour, two fingers tapping twice the minute. Digits: a
 * long vibration is 10, a short one 1; Terse: the minutes as one short
 * vibration per quarter-hour. Speed 0 to 4 (default 2): the gap between
 * vibrations 800 / 650 / 500 / 350 / 200 ms, a long one 700 / 450 / 300 / 225
 * / 175 ms, a short one 225 / 150 / 100 / 75 / 50 ms (a11y.js).
 *
 * dconf: /org/asteroidos/a11y/vibration-watch (b, off), -type (s: digits,
 * terse), -speed (i: 0 to 4, 2).
 *
 * The taps come from TouchObserver (two fingers, stock's MultiFingerMultiTap
 * rules); it is not installed while the feature is off. Each vibration is a
 * ngfd event (eos_vw_long_<speed>, eos_vw_short_<speed>: a fixed waveform,
 * drafts/eos-a11y-events.ini) and one single-shot timer steps through them;
 * it runs only while a time is being told (a few seconds, screen on) and
 * stops with the display. The hour is on the watch's 12 or 24 hour clock.
 */
Item {
    id: vw
    objectName: "vibrationWatch"

    property QtObject observer: typeof touchObserver !== "undefined" ? touchObserver : null
    // the display is on
    property bool displayOn: true
    // the watch face is what is on screen (not an app, not a panel)
    property bool onFace: true
    // tests replace these
    property var now: function () { return new Date() }
    property var playEvent: function (name) { Haptics.play(name) }
    property bool use24h: TimeFormat.use24h

    ConfigurationValue {
        id: onSetting
        key: A11y.KEY_VIBRATION_WATCH
        defaultValue: false
    }
    ConfigurationValue {
        id: typeSetting
        key: A11y.KEY_VIBRATION_WATCH_TYPE
        defaultValue: A11y.VW_DIGITS
    }
    ConfigurationValue {
        id: speedSetting
        key: A11y.KEY_VIBRATION_WATCH_SPEED
        defaultValue: A11y.VW_DEFAULT_SPEED
    }

    readonly property bool featureOn: onSetting.value === true || onSetting.value === "true"
    readonly property string type: String(typeSetting.value) === A11y.VW_TERSE ? A11y.VW_TERSE : A11y.VW_DIGITS
    readonly property int speed: A11y.validSpeed(speedSetting.value)
    // a time is being told
    readonly property bool telling: queue.length > 0 || pulseTimer.running
    property var queue: []
    // how many pulses were played (the tests)
    property int played: 0

    function tell(taps) {
        if (!featureOn || !displayOn)
            return false
        var d = now()
        queue = A11y.timePulses(taps, d.getHours(), d.getMinutes(), use24h, type, speed)
        if (queue.length === 0)
            return false
        step()
        return true
    }

    function step() {
        pulseTimer.stop()
        if (queue.length === 0 || !displayOn)
            return
        var p = queue[0]
        var rest = queue.slice(1)
        queue = rest
        playEvent(A11y.pulseEvent(p.ms, speed))
        played++
        if (rest.length > 0) {
            // the next one starts when this one and the gap after it are over
            pulseTimer.interval = p.ms + p.afterMs
            pulseTimer.restart()
        }
    }

    onDisplayOnChanged: {
        if (!displayOn) {
            pulseTimer.stop()
            queue = []
        }
    }

    Timer {
        id: pulseTimer
        repeat: false
        onTriggered: vw.step()
    }
    readonly property alias timer: pulseTimer

    Binding {
        target: vw.observer
        property: "twoFingerTaps"
        value: vw.featureOn
        when: vw.observer !== null
    }
    Connections {
        target: vw.observer
        ignoreUnknownSignals: true
        function onMultiTap(fingers, taps, x, y) {
            if (fingers === 2 && vw.onFace)
                vw.tell(taps)
        }
    }
}
