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
import Nemo.Configuration
import Nemo.Mce

/* The home screen on the charger (split out of MainScreen.qml): the
 * nightstand mode, its brightness and its own watch face. Instantiated
 * once in MainScreen as `nightstandMode` (the faces read
 * nightstandMode.active). Reads MainScreen's shared ids (desktop,
 * mceChargerType, displaySettings) through the context. Owned by the
 * charging package (W2-launcher-charging).
 *
 * The nightstand property is for use by watchfaces to signal them to, for
 * example, enable a visual display of battery charge level, as with a ring
 * around the perimeter of the watch that wouldn't normally be displayed. */
Item {
    id: nightstand

    readonly property bool active: ready || nightstandDelayTimer.running
    readonly property bool ready: nightstandEnabled.value && mceChargerType.type != MceChargerType.None
    property int oldBrightness: 100
    // the nightstand set its brightness (and owes the old one back)
    property bool setBrightness: false

    // the nightstand's own face, and its always-on choice
    readonly property var watchfaceSource: watchfaceNightstandSource.value
    readonly property var useCustomWatchface: nightstandUseCustomWatchface.value
    readonly property var alwaysOnDisplayValue: nightstandAlwaysOnDisplay.value

    ConfigurationValue {
        id: watchfaceNightstandSource
        key: "/desktop/asteroid/nightstand/watchface"
        defaultValue: "file:///usr/share/asteroid-launcher/watchfaces/000-default-digital.qml"
    }

    ConfigurationValue {
        id: nightstandBrightness
        key: "/desktop/asteroid/nightstand/brightness"
        defaultValue: 30
    }

    ConfigurationValue {
        id: nightstandDelay
        key: "/desktop/asteroid/nightstand/delay"
        defaultValue: 5
    }

    ConfigurationValue {
        id: nightstandEnabled
        key: "/desktop/asteroid/nightstand/enabled"
        defaultValue: true
    }

    ConfigurationValue {
        id: nightstandAlwaysOnDisplay
        key: "/desktop/asteroid/nightstand/always-on-display"
        defaultValue: true
    }

    ConfigurationValue {
        id: nightstandUseCustomWatchface
        key: "/desktop/asteroid/nightstand/use-custom-watchface"
        defaultValue: false
    }

    function enter() {
        if (!desktop.brightnessHeld && !setBrightness) {
            oldBrightness = displaySettings.brightness
            displaySettings.brightness = nightstandBrightness.value
            setBrightness = true
        }
        desktop.applyLowPower()
    }
    function leave() {
        if (setBrightness) {
            if (desktop.brightnessHeld)
                modes.setRestoreValue("brightness", oldBrightness)
            else
                displaySettings.brightness = oldBrightness
            setBrightness = false
        }
        desktop.applyLowPower()
    }
    onReadyChanged: {
        if (ready) {
            if (nightstandDelayTimer.running) {
                // timer was holding off, so cancel timer
                nightstandDelayTimer.stop()
            } else {
                // enter nightstand mode
                enter()
            }
        } else {
            if (nightstandEnabled.value) {
                // start off-charger timer
                nightstandDelayTimer.restart()
            } else {
                // mode disabled, so
                // exit nightstand mode immediately
                nightstandDelayTimer.stop()
                leave()
            }
        }
    }
    Timer {
        id: nightstandDelayTimer
        interval: nightstandDelay.value * 1000
        repeat: false
        // timer expired, so restore brightness
        onTriggered: nightstand.leave()
    }
    // a mode let go of the brightness on the charger: the nightstand's,
    // once mce has the user's back
    Connections {
        target: desktop
        function onBrightnessHeldChanged() {
            if (!desktop.brightnessHeld && nightstand.ready)
                nightstandHeldEnd.restart()
        }
    }
    Timer {
        id: nightstandHeldEnd
        interval: 1000
        onTriggered: if (nightstand.ready && !desktop.brightnessHeld) nightstand.enter()
    }
}
