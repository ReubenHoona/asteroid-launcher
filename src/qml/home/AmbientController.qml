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
import org.nemomobile.lipstick
import org.asteroid.controls
import org.asteroid.utils
import "../desktop.js" as Desktop
import "ambient.js" as Ambient

/* The always-on screen of the home screen (split out of MainScreen.qml):
 * the display state, the minute redraw, the sensor hub's layout, Ambient Lite
 * over an open application, the 'Always-on when off wrist' rule, and the
 * modes that keep the always-on screen off. The burn-in protection is the
 * stock half-pixel mask (compositor/BurnInMask.qml), not a drift of the face.
 * Instantiated once in MainScreen as `ambientController`; MainScreen
 * forwards `burnInProtectionManager` (the faces use it) and the modes
 * properties. Reads MainScreen's shared ids (desktop, grid, wallClock,
 * use12H, alwaysOnDisplay, displaySettings, nightstandMode, faceLayer,
 * overlays, leftIndicator) through the context. Owned by the ambient
 * package (W2-launcher-ambient); the modes part by W2-launcher-modes. */
Item {
    id: ambientController

    readonly property Item burnInProtectionManager: burnIn

    /* No system pixel shift (stock config_enableBurnInProtection false, offsets
     * 0; ambient-aod-07): the AP-drawn always-on screen has the half-pixel mask
     * of compositor/BurnInMask.qml, the sensor hub its own checkerboard. The
     * object stays for the faces: they set its offsets (setActiveWatchFaceArea,
     * widthOffset ...), which nothing moves any more. */
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

        // the drift is gone
        enabled: false

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

    // The unread dot and the status icons on the always-on face (stock sends the
    // watch-face overlay to the hub again at every ambient transition,
    // WatchFaceOverlayUi#batchedSendOverlayViewWithDelay, kba.java:565-591;
    // ambient-aod-10, -18): the hub's picture has them from the grab, so a change
    // is a change of the layout. statusSlot.ambientIconsKey is the hook of
    // W2-launcher-status for the ongoing-activity and status icons.
    readonly property bool unreadDotShown: typeof statusSlot !== "undefined" && statusSlot.notificationIndicator
                                           ? statusSlot.notificationIndicator.dotWanted === true : false
    readonly property string statusIconsKey: typeof statusSlot !== "undefined" && statusSlot.ambientIconsKey !== undefined
                                             ? String(statusSlot.ambientIconsKey) : ""

    // The sensor hub's always-on layout is the face drawn with these: when
    // one changes, the layout the hub holds shows the old look, so it goes
    // at once, before the display can go off with it (stock clears the
    // offload layout when the watch face changes); the next ambient update
    // builds the new one
    readonly property string hubLayoutInputs: [faceLayer.faceSource, nightstandMode.watchfaceSource,
                                               use12H.value, faceLayer.faceShowDateValue,
                                               faceLayer.faceAmbientStyleValue,
                                               JSON.stringify(faceLayer.faceComplicationsValue),
                                               unreadDotShown ? "dot" : "", statusIconsKey].join("|")
    onHubLayoutInputsChanged: {
        hubOffload.invalidate()
        // In the always-on screen the AP is awake for whatever changed it (a
        // notification came): redraw and send the new layout now, not at midnight
        if (Lipstick.compositor.displayAmbient)
            Qt.callLater(ambientController.refreshAmbient)
    }
    function refreshAmbient() {
        if (Lipstick.compositor.displayAmbient && Lipstick.compositor.offloadAmbientUpdateWanted())
            Lipstick.compositor.setAmbientUpdatesEnabled(true)
    }

    // Whether the face names the time items the sensor hub can draw: the
    // complications then show '--' for data that would go stale there
    readonly property bool hubFace: desktop.centreItem !== null && desktop.centreItem.activeFace
                                    ? hubOffload.eligible(desktop.centreItem.activeFace) : false

    // the charging screen is up (compositor.qml, W2-launcher-charging): the main CPU draws the
    // always-on screen then (stock holds a display control lock), never the sensor hub
    function chargingUp() {
        return Desktop.compositorRoot ? Desktop.compositorRoot.chargingShown === true : false
    }

    // Ambient Lite or the media layout over an open application (compositor.qml)
    function litePart() {
        return Desktop.compositorRoot ? Desktop.compositorRoot.ambientLite : null
    }
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
            // charging screen: on the charger the AP does not sleep anyway (USB keeps it
            // awake), and the screen shows the charge
            if (Lipstick.compositor.displayAmbient) {
                var lite = ambientController.litePart()
                if (!Lipstick.compositor.homeActive) {
                    // an application is open: Ambient Lite or the media layout (the
                    // application's last frame, not the face, is under the time)
                    if (lite && lite.showing)
                        lite.handOver()
                    else
                        hubOffload.clear()
                } else if (desktop.centreItem) {
                    if (desktop.nightstand || ambientController.chargingUp())
                        hubOffload.clear()
                    else
                        hubOffload.update(desktop.centreItem.activeFace, use12H.value,
                                          desktop.centreItem.activeSource, wallClock.time,
                                          ambientController.hubBurnInMoveMinutes)
                }
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
    // The face is no longer moved (the burn-in drift is gone, ambient-aod-07):
    // the hub's layout never expires for a move
    readonly property int hubBurnInMoveMinutes: 0
    Timer {
        id: ambientMinuteTimer
        interval: 1000
        repeat: true
        onTriggered: {
            // the AP is awake (the timer never wakes it): the off-wrist alarm
            // that woke it may be due
            ambientController.offWristApply()
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
        function onDisplayAmbientUpdate() {
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
        displaySettings.lowPowerModeEnabled = !alwaysOnBlocked && !offWristEnded && alwaysOnWanted
    }
    // the user's Always-on screen (the nightstand's own switch while it is active)
    readonly property bool alwaysOnWanted: nightstandMode.active ? nightstandMode.alwaysOnDisplayValue : alwaysOnDisplay.value
    onAlwaysOnBlockedChanged: applyLowPower()
    onOffWristEndedChanged: applyLowPower()
    // ...and the sensor hub draws no always-on screen meanwhile either: the
    // compositor keeps the panel from the offload daemon (2026-11-04: the hub
    // took the panel at every blank in Bedtime, the face stayed on all night)
    Binding {
        target: Lipstick.compositor
        property: "offloadBlocked"
        value: ambientController.alwaysOnBlocked || ambientController.offWristEnded
    }

    /*
     * Settings > Display > 'Always-on when off wrist' (choice-settings-07, wake-
     * sleep-display-18). On (the user's choice, the default): the always-on screen
     * never goes black by itself. Off (stock): with the always-on screen showing,
     * it ends 60 s after the off-body sensor of the sensor hub reports off-body
     * or the charger is connected (CSUI AmbientEarlyExitTimeoutController: one
     * timer for both, ro.ambient.plugged_timeout_min 1), the panel goes black
     * and the hub's offload is released; on-body, unplugged or any wake brings it
     * back. The nightstand, when active, keeps the screen on the charger (ours
     * only). Power: the off-body sensor is on-change only; the 60 s are one timed
     * wake-up (LipstickCompositor::setOffWristWake), never a polling timer; the
     * ambient minute timer (one tick a second, only while the AP is awake)
     * checks it. ambient.js offWristDecide is the rule.
     */
    ConfigurationValue {
        id: offWristSetting
        key: "/org/asteroidos/settings/always-on-off-wrist"
        defaultValue: true
    }
    property bool offWristEnded: false
    // when the running alarm is due, ms since the epoch (0: none)
    property real offWristDeadline: 0
    readonly property bool plugged: typeof mceChargerType !== "undefined" && mceChargerType.type !== MceChargerType.None
    // the hub's off-body sensor: true off the wrist, undefined while unknown
    readonly property var offBodyNow: typeof offBody !== "undefined" && offBody !== null && offBody.known
                                      ? offBody.offBody : undefined
    function offWristApply() {
        var now = Date.now()
        var r = Ambient.offWristDecide({
            rule: offWristSetting.value === false && !alwaysOnBlocked && alwaysOnWanted,
            displayOff: !desktop.displayAwake,
            offBody: offBodyNow,
            plugged: plugged,
            nightstand: nightstandMode.active,
            ended: offWristEnded,
            deadline: offWristDeadline,
            now: now
        })
        if (r.cancel) {
            offWristDeadline = 0
            if (typeof Lipstick.compositor.setOffWristWake === "function")
                Lipstick.compositor.setOffWristWake(0)
        }
        if (r.arm) {
            offWristDeadline = Ambient.offWristDeadline(now)
            if (typeof Lipstick.compositor.setOffWristWake === "function")
                Lipstick.compositor.setOffWristWake(Math.ceil(offWristDeadline / 1000))
        }
        if (r.expire) {
            offWristDeadline = 0
            offWristEnded = true
        }
        if (r.restore)
            offWristEnded = false
    }
    onOffBodyNowChanged: offWristApply()
    onPluggedChanged: offWristApply()
    onAlwaysOnWantedChanged: offWristApply()
    Connections {
        target: offWristSetting
        function onValueChanged() { ambientController.offWristApply() }
    }
    Connections {
        target: desktop
        function onDisplayAwakeChanged() { ambientController.offWristApply() }
    }
    Connections {
        target: nightstandMode
        function onActiveChanged() { ambientController.offWristApply() }
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
