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
import org.nemomobile.lipstick
import org.asteroid.controls
import org.asteroid.utils

/* The always-on screen of the home screen (split out of MainScreen.qml):
 * the display state, burn-in protection, the minute redraw, the sensor
 * hub's layout, and the modes that keep the always-on screen off.
 * Instantiated once in MainScreen as `ambientController`; MainScreen
 * forwards `burnInProtectionManager` (the faces use it) and the modes
 * properties. Reads MainScreen's shared ids (desktop, grid, wallClock,
 * use12H, alwaysOnDisplay, displaySettings, nightstandMode, faceLayer,
 * overlays, leftIndicator) through the context. Owned by the ambient
 * package (W2-launcher-ambient); the modes part by W2-launcher-modes. */
Item {
    id: ambientController

    readonly property Item burnInProtectionManager: burnIn

    ConfigurationValue {
        id: bipLevel
        key: "/org/asteroidos/settings/burn-in-protection-level"
        defaultValue: DeviceSpecs.needsBurnInProtection ? 1.0 : 0.0
    }

    Item {
        id: burnIn

        // Maximum offset before components from other grid becomes visible.
        property int maximumWidthOffset: Dims.w(27)
        property int maximumHeightOffset: Dims.h(27)

        property int leftOffset: Dims.w(2)
        property int rightOffset: Dims.w(2)
        property int topOffset: Dims.h(2)
        property int bottomOffset: Dims.h(2)

        // The maximum allowed movement in x and y direction.
        property int widthOffset
        property int heightOffset

        // Enable/disable burn in protection.
        enabled: DeviceSpecs.needsBurnInProtection && bipLevel.value > 0.0
        readonly property real bipMultiplier: Math.max(0.0, Math.min(1.0, bipLevel.value))

        /* Wear OS moves the always-on screen by a few pixels at a time. The
         * Settings levels High, Medium and Low (1.0, 0.5, 0.25) give about
         * 8, 5 and 3 px either way from the centre (the old offsets let High
         * wander some 52 px); the face walks there in steps of 1 or 2 px a
         * minute instead of jumping anywhere in the range. The faces'
         * setActiveWatchFaceArea/setCenterWatchFaceArea are kept for them
         * but no longer widen it. */
        readonly property real maxShift: bipMultiplier <= 0 ? 0
            : Math.round((3 + 5 * Math.max(0, bipMultiplier - 0.25) / 0.75) * Dims.w(100) / 384)
        property real shiftX: 0
        property real shiftY: 0
        function walk(v) {
            var s = maxShift
            var d = (Math.random() < 0.5 ? -1 : 1) * (1 + Math.floor(Math.random() * 2))
            var n = v + d
            if (n > s || n < -s)
                n = v - d
            return Math.max(-s, Math.min(s, n))
        }
        function step() {
            shiftX = walk(shiftX)
            shiftY = walk(shiftY)
        }

        onHeightOffsetChanged: {
            topOffset = heightOffset/2
            bottomOffset = topOffset
        }

        onWidthOffsetChanged: {
            leftOffset = widthOffset/2
            rightOffset = leftOffset
        }

        onLeftOffsetChanged: if (leftOffset > maximumWidthOffset/2) leftOffset = maximumWidthOffset/2
        onRightOffsetChanged: if (rightOffset > maximumWidthOffset/2) rightOffset = maximumWidthOffset/2
        onTopOffsetChanged: if (topOffset > maximumHeightOffset/2) topOffset = maximumHeightOffset/2
        onBottomOffsetChanged: if (bottomOffset > maximumHeightOffset/2) bottomOffset = maximumHeightOffset/2

        function setActiveWatchFaceArea(x, y, w, h) {
            leftOffset = Math.min(x, maximumWidthOffset/2)
            topOffset = Math.min(y, maximumHeightOffset/2)
            rightOffset = Math.min(Dims.w(100)-w-x, maximumWidthOffset/2)
            bottomOffset = Math.min(Dims.h(100)-h-y, maximumHeightOffset/2)
        }
        function setCenterWatchFaceArea(w, h) {
            widthOffset = Dims.w(100)-w
            heightOffset = Dims.h(100)-h
        }
        function resetOffsets() {
            leftOffset = Dims.w(2)
            rightOffset = Dims.w(2)
            topOffset = Dims.h(2)
            bottomOffset = Dims.h(2)
        }
    }

    // The sensor hub's always-on layout is the face drawn with these: when
    // one changes, the layout the hub holds shows the old look, so it goes
    // at once, before the display can go off with it (stock clears the
    // offload layout when the watch face changes); the next ambient update
    // builds the new one
    readonly property string hubLayoutInputs: [faceLayer.faceSource, nightstandMode.watchfaceSource,
                                               use12H.value, faceLayer.faceShowDateValue,
                                               faceLayer.faceAmbientStyleValue,
                                               JSON.stringify(faceLayer.faceComplicationsValue)].join("|")
    onHubLayoutInputsChanged: hubOffload.invalidate()
    Connections {
        target: desktop
        function onWatchfaceReloadRequested() { hubOffload.invalidate() }
    }

    // The face fades to its always-on look in 500 ms when the display enters
    // the always-on screen (FaceLayer, ambient-aod-19); the layout goes to the
    // hub, and the AP back to sleep, after that, inside mce's LPM_ON window.
    // Later updates (the minute) wait 200 ms as before.
    property bool entryPending: false
    // how long the hub's layout waits after an update (for the tests)
    readonly property int hubDelayMs: wallClockAmbientTimeout.interval
    readonly property int entryHoldMs: Motion.animationScale > 0 ? 500 : 0
    Timer {
        id: wallClockAmbientTimeout
        interval: 200 + (ambientController.entryPending ? ambientController.entryHoldMs : 0)
        repeat: false
        onTriggered: {
            ambientController.entryPending = false
            // The face has drawn this minute in its ambient style: give its
            // layout to the sensor hub, which then draws the time while the
            // AP sleeps (stock display offload; kept while unchanged). Not in
            // nightstand: on the charger the AP does not sleep anyway, and
            // the face shows the charge
            if (Lipstick.compositor.displayAmbient && desktop.centreItem) {
                if (desktop.nightstand)
                    hubOffload.clear()
                else
                    hubOffload.update(desktop.centreItem.activeFace, use12H.value,
                                      desktop.centreItem.activeSource, wallClock.time,
                                      burnIn.enabled ? ambientController.hubBurnInMoveMinutes : 0)
            }
            Lipstick.compositor.setAmbientUpdatesEnabled(false)
        }
    }

    // The ambient face is only redrawn on request (the wall clock is off):
    // once in every minute while it shows. Qt timers stop while the system
    // is suspended (CLOCK_MONOTONIC), so a one-shot timer to the next minute
    // fired long after the RTC wakeup at the minute (lipstick's timed
    // event), when the AP was asleep again, and the face stayed stale. So
    // check the wall clock each second while the AP is awake: the first
    // check after the wakeup redraws. The timer never wakes the AP itself.
    // Not while the sensor hub draws the always-on display
    // (displayOffloaded): it draws the time itself, as stock Wear OS; but
    // once its layout has expired (the date at midnight, AM/PM), at the AP
    // wakeup lipstick schedules for that, the redraw sends the new one
    // (stock: an AP update at the layout's minutes_valid).
    property real ambientMinuteShown: 0
    // With the hub drawing, the burn-in protection moves the face at most
    // this often, at a display off (one layout send then), instead of at
    // every display off as the AP-drawn always-on screen does
    readonly property int hubBurnInMoveMinutes: 60
    Timer {
        id: ambientMinuteTimer
        interval: 1000
        repeat: true
        onTriggered: {
            var minute = Math.floor(Date.now() / 60000)
            if (minute === ambientController.ambientMinuteShown || !Lipstick.compositor.offloadAmbientUpdateWanted())
                return
            ambientController.ambientMinuteShown = minute
            Lipstick.compositor.setAmbientUpdatesEnabled(true)
        }
    }

    function scheduleAmbientMinute() {
        ambientMinuteShown = Math.floor(Date.now() / 60000)
        ambientMinuteTimer.restart()
    }

    Connections {
        target: Lipstick.compositor
        function onDisplayAboutToBeOn() {
            wallClockAmbientTimeout.stop()
            desktop.displayAwake = true
        }
        function onDisplayAboutToBeOff() { desktop.displayAwake = false }
        function onDisplayOn() {
            ambientMinuteTimer.stop()
            overlays.prewarmIfPending()
            grid.animateIndicators()
            desktop.setAmbientDarken(0)
            if (Lipstick.compositor.ambientEnabled) grid.moveTo(0, 0)
        }
        function onDisplayAmbientEntered() {
            ambientController.scheduleAmbientMinute()
            // the face takes 500 ms to change over (FaceLayer): the layout goes to the hub after it
            ambientController.entryPending = true
            desktop.setAmbientDarken(1)
            grid.hideOffscreen();
        }
        function onDisplayAmbientLeft() {
            if (burnIn.enabled) leftIndicator.anchors.verticalCenterOffset = 0
        }
        function onDisplayAmbientUpdate() {
            // Perform burn in protection
            if (burnIn.enabled) {
                burnIn.step()
                grid.contentX = burnIn.shiftX
                grid.contentY = burnIn.shiftY
                leftIndicator.anchors.horizontalCenterOffset = burnIn.shiftX
                leftIndicator.anchors.verticalCenterOffset = burnIn.shiftY
            }
            // Give watchface some time to update, then go back to deep sleep.
            wallClockAmbientTimeout.start();
        }
    }

    /*
     * The modes (modes.h): Bedtime, Theater and Battery saver keep the
     * always-on screen off, Bedtime and Extra dim hold the brightness. mce's
     * low power mode is the user's always-on choice (or the nightstand's)
     * unless a mode blocks it; the nightstand leaves a held brightness
     * alone, and what it would put back goes to the engine instead.
     */
    readonly property bool modesReady: typeof modes !== "undefined" && modes !== null
    readonly property bool alwaysOnBlocked: modesReady && modes.alwaysOnBlocked
    readonly property bool brightnessHeld: modesReady && modes.brightnessHolder !== ""
    function applyLowPower() {
        displaySettings.lowPowerModeEnabled = !alwaysOnBlocked
                && (nightstandMode.active ? nightstandMode.alwaysOnDisplayValue : alwaysOnDisplay.value)
    }
    onAlwaysOnBlockedChanged: applyLowPower()
    // ...and the sensor hub draws no always-on screen meanwhile either: the
    // compositor keeps the panel from the offload daemon (2026-11-04: the hub
    // took the panel at every blank in Bedtime, the face stayed on all night)
    Binding {
        target: Lipstick.compositor
        property: "offloadBlocked"
        value: ambientController.alwaysOnBlocked
    }
    // a mode that ended while the launcher was not running left it off
    Timer {
        interval: 3000
        running: true
        onTriggered: if (!ambientController.alwaysOnBlocked) ambientController.applyLowPower()
    }

    // the display off: back to the watch face, the overlays closed
    Timer {
        id: lockscreenDelay
        interval: 150
        repeat: false
        onTriggered: grid.moveTo(0, 0)
    }

    Connections {
        target: Lipstick.compositor
        function onDisplayOff() {
            // The Wear layout stays where it is: a tray (the stream, quick settings) or a
            // tile stays out across the screen off, as stock, and the face comes back with
            // Settings > Display > Go to watch face (AppLifecycle.goToFace; stock
            // ihh.java:97-110 retracts the tray without animation on the auto-resume).
            // No timer here: the time off is judged at the wake (notif-stream-16)
            if (!grid.trayMode)
                lockscreenDelay.start()
            // the overlays (app list, face picker, tiles editor) stay until
            // Settings > Display > Go to watch face has passed; the wake
            // closes them then (AppLifecycle.goToFace, interruptions-14)
        }
    }
}
