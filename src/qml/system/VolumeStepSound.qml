/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Ngf

/*
 * The launcher's copy of asteroid-settings' VolumeStepSound (CR-56: the same ngfd names). The sample a volume step plays (haptics-sounds-14, stock
 * InlineSliderVolumizer.java:303-316,405-420,455-480 and
 * SliderController$VolumeStream, SAMPLE_CUTOFF 2 s): every change plays
 * volume_step on the stream being changed, volume_step_max when it lands on
 * the maximum, one stream at a time (one feedback object, the previous
 * sample is stopped first); the sample is cut after 2 s; a step that comes
 * while a sample is still playing waits 1 s (and only the newest waits).
 * The ngfd events are named for the stream: volume_step and volume_step_max
 * for media (the main volume), volume_step_<role> and volume_step_max_<role>
 * for ring, notification, alarm and call (meta-eos64 events.d, one pair each,
 * the sample of the stock volume_step.ogg / volume_step_max.ogg role).
 * Nothing runs unless a step was just taken: the two timers are one-shot.
 */
Item {
    id: sound
    visible: false

    readonly property int cutoff: 2000
    readonly property int wait: 1000

    property string pending: ""

    function eventName(role, atMax) {
        return "volume_step" + (atMax ? "_max" : "") + (role === "media" ? "" : "_" + role)
    }

    // a volume of this stream changed (not called for a press that moved nothing)
    function step(role, atMax) {
        pending = eventName(role, atMax)
        if (sample.status === NonGraphicalFeedback.Playing) {
            playTimer.interval = wait
            playTimer.restart()
        } else {
            playTimer.stop()
            play()
        }
    }
    function play() {
        sample.stop()
        sample.event = pending
        sample.play()
        cutTimer.restart()
    }
    function stop() {
        playTimer.stop()
        cutTimer.stop()
        sample.stop()
    }

    NonGraphicalFeedback { id: sample; objectName: "volumeStepFeedback" }
    Timer { id: playTimer; onTriggered: sound.play() }
    Timer { id: cutTimer; interval: sound.cutoff; onTriggered: sample.stop() }
    Component.onDestruction: stop()
}
