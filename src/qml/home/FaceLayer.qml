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
import org.asteroid.controls
import org.asteroid.utils
import ".."
import "../facepicker.js" as FP

/* The watch face of the home screen (split out of MainScreen.qml): which
 * face (dconf), its options, the clock it needs (seconds or minutes), and
 * `panel`, the centre panel of the grid that loads it (Trays places it).
 * Instantiated once in MainScreen as `faceLayer`; reads MainScreen's
 * shared ids (desktop, nightstandMode, complications, use12H, facePicker,
 * burnInProtectionManager) through the context. Owned by the face
 * packages (face picker, faces, complications).
 *
 * W2-launcher-face-picker: the favourites (`favs`, FaceFavourites) name the
 * face on the watch by an id; the options (`faceStyle`) and the
 * complications are the favourite's own. A long press in the centre circle
 * of the face opens the picker (a TapHandler over the face, see `panel`). */
Item {
    id: faceLayer

    readonly property var faceSource: watchFaceSource.value
    readonly property var faceShowDateValue: faceStyle.showDate
    readonly property var faceAmbientStyleValue: faceStyle.ambientStyle
    readonly property var faceComplicationsValue: faceComplications.value
    property bool faceSecondsShown: false

    // the favourites of the picker and the one on the watch
    readonly property QtObject favourites: favs
    readonly property string faceId: favs.currentId

    function chooseFace(face) {
        watchFaceSource.value = face
    }

    // Bedtime mode: a long press opens its settings, not the picker (stock ked.java:391-407)
    readonly property bool bedtimeOn: typeof modes !== "undefined" && modes !== null && modes.bedtime === true

    function openFacePicker() {
        if (FP.longPressAction(true, false, bedtimeOn, false) === "bedtime") {
            desktop.openBedtimeSettings()
            return
        }
        facePicker.current = watchFaceSource.value
        facePicker.open()
    }

    ConfigurationValue {
        id: watchFaceSource
        key: "/desktop/asteroid/watchface"
        defaultValue: "file:///usr/share/asteroid-launcher/watchfaces/000-default-digital.qml"
        onValueChanged: burnInProtectionManager.resetOffsets()
    }

    // the favourites: the face on the watch is always one of them
    FaceFavourites {
        id: favs
        file: String(watchFaceSource.value)
        onFileRequested: (f) => faceLayer.chooseFace(f)
        // the same face as another favourite: it loads again, with that favourite's complications
        onReloadRequested: desktop.watchfaceReloadRequested()
        onRemoved: (id) => {
            if (typeof facePreviews !== "undefined" && facePreviews)
                facePreviews.remove(id)
        }
    }

    // the pictures of favourites that are gone (once, when the list is settled)
    Connections {
        target: favs
        function onReadyChanged() {
            if (favs.ready && typeof facePreviews !== "undefined" && facePreviews)
                facePreviews.keepOnly(favs.entries.map(function (e) { return e.id }))
        }
    }

    /* The clock the watchfaces draw. It ticks every second only while the
     * watchface is the page on screen and its seconds are shown (faces hide
     * them in nightstand, ambient or 12 h mode); else every minute, on the
     * minute: under tiles, the notifications or the app list that is the
     * frame their own curved time draws anyway, and the face is right when
     * it comes back, with no text to change in the first frame of the way
     * back. It stops under an application and with the display off.
     * (The WallClock itself stays in MainScreen: the faces use its id.) */
    function checkSeconds() {
        if (!desktop.centreItem)
            return
        applyFaceOptions()
        if (!desktop.faceShown)
            return
        faceSecondsShown = faceStyle.showSeconds
                           && watchfaceReloader.secondsShown(desktop.centreItem.activeFace, desktop.centreItem.activeSource)
    }

    /* The watchface options of the face picker, for every face: date and
     * seconds shown or not (seconds never in always-on mode, as on Wear OS),
     * and how the always-on face looks: "dim" (the face in grey: 55 %) or
     * "outline" (grey letter outlines, and the rest dimmed). They are the
     * favourite's own (FaceStyle: dconf /org/asteroidos/watchface/style/<id>;
     * a favourite without its own values reads the old global keys). */
    FaceStyle {
        id: faceStyle
        faceId: favs.currentId
    }
    Connections {
        target: faceStyle
        function onShowDateChanged() { Qt.callLater(desktop.checkSeconds) }
        function onShowSecondsChanged() { Qt.callLater(desktop.checkSeconds) }
        function onAmbientStyleChanged() { Qt.callLater(desktop.checkSeconds) }
    }
    function applyFaceOptions() {
        if (!desktop.centreItem || !desktop.centreItem.activeFace)
            return
        watchfaceReloader.applyFaceOptions(desktop.centreItem.activeFace, faceStyle.showDate, faceStyle.showSeconds,
                                           displayAmbient, faceStyle.ambientStyle)
    }
    Connections {
        target: desktop
        function onFaceShownChanged() { if (desktop.faceShown) desktop.checkSeconds() }
        function onDisplayAmbientChanged() { Qt.callLater(desktop.checkSeconds) }
    }
    Connections {
        target: nightstandMode
        function onActiveChanged() { Qt.callLater(desktop.checkSeconds) }
    }
    Connections {
        target: use12H
        function onValueChanged() { Qt.callLater(desktop.checkSeconds) }
    }

    // the complications chosen for the favourite (the date shows in always-on)
    ConfigurationValue {
        id: faceComplications
        key: complications.configKey(favs.currentId !== "" ? favs.currentId : complications.faceName(watchFaceSource.value))
        defaultValue: []
    }

    // a language change reloads the face
    Connections {
        target: localeManager
        function onChangesObserverChanged() {
            var watchFaceSourceBackup = watchFaceSource.value
            watchFaceSource.value = ""
            watchFaceSource.value = watchFaceSourceBackup
        }
    }

    // the centre panel of the grid: the face, or the nightstand's own face
    property Component panel: Component {
        Item {
            id: panelRoot
            property bool nightstandWatchfaceActive: nightstandMode.active && nightstandMode.useCustomWatchface && nightstandMode.watchfaceSource != watchFaceSource.value
            /* always-on: the face in grey, not full white. Going to the always-on
             * screen it changes over in 500 ms with the standard easing (the watch
             * face's own ambient transition, WFF runtime_ambient_transition_ms;
             * stock allows up to 1500 ms), before the hub draws the panel; the wake
             * is at once, with no brightness ramp (ambient-aod-19, motion-transitions-32).
             * Nothing runs unless the display changes state. */
            property real ambientOpacity: 1.0
            opacity: ambientOpacity
            // (no binding: a binding would jump with displayAmbient)
            Component.onCompleted: ambientOpacity = displayAmbient ? 0.55 : 1.0
            readonly property bool ambientNow: displayAmbient
            onAmbientNowChanged: {
                ambientFade.stop()
                if (ambientNow && Motion.animationScale > 0)
                    ambientFade.restart()
                else
                    ambientOpacity = ambientNow ? 0.55 : 1.0
            }
            NumberAnimation {
                id: ambientFade
                target: panelRoot
                property: "ambientOpacity"
                to: 0.55
                duration: 500
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.easing.standard
            }
            /* Wear OS: a long press on the watchface opens the face picker. As stock
             * (SysUI's recognizer sees every touch before the face and takes the
             * gesture when it fires, hun.java:33-49): 400 ms (face-interaction-01),
             * only when the finger came down inside the centre circle, 0.6 of the
             * radius, 115 px (-02), and no face can keep the press. A PointHandler
             * sits in a layer above the face: it sees every touch and takes none
             * (a handler in an item under the face's own MouseArea would see
             * nothing of what that takes; a TapHandler above it would take the
             * touch from the face, tested), and a timer of 400 ms runs while the
             * finger is down in the circle and has not moved a drag's distance.
             * When it fires the face's own touch is cancelled, so a full-face
             * MouseArea or a complication gets neither a click nor the release
             * (-03). A complication has no long press of its own. A touch that
             * woke the display is no long press (the display was on when the
             * finger came down). Bedtime: its settings open instead (-04). The
             * timer runs only with a finger down. */
            Item {
                id: longPressLayer
                objectName: "eosFaceLongPressLayer"
                anchors.fill: parent
                z: 1000
                PointHandler {
                    id: longPress
                    objectName: "eosFaceLongPress"
                    acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse
                    // the display state when the finger came down
                    property bool awakeAtDown: false
                    onActiveChanged: {
                        if (active) {
                            awakeAtDown = desktop.displayAwake && !displayAmbient
                            if (FP.longPressInside(point.pressPosition.x, point.pressPosition.y, panelRoot.width, panelRoot.height)
                                    && FP.longPressAction(awakeAtDown, displayAmbient, false, false) !== "")
                                longPressTimer.restart()
                        } else {
                            longPressTimer.stop()
                        }
                    }
                    // a drag (a swipe to the tiles) is no long press
                    onPointChanged: {
                        if (!active || !longPressTimer.running)
                            return
                        var dx = point.position.x - point.pressPosition.x
                        var dy = point.position.y - point.pressPosition.y
                        if (dx * dx + dy * dy > longPressTimer.slop * longPressTimer.slop)
                            longPressTimer.stop()
                    }
                }
                Timer {
                    id: longPressTimer
                    objectName: "eosFaceLongPressTimer"
                    interval: Math.round(FP.LONG_PRESS_S * 1000)
                    // the system's drag distance: a finger that moves more is dragging
                    readonly property real slop: Qt.styleHints.startDragDistance
                    onTriggered: {
                        Haptics.longPress()
                        panelRoot.cancelFaceTouch()
                        desktop.openFacePicker()
                    }
                }
            }
            // the face's own touch ends: what holds a press (a MouseArea, a complication) lets go
            // with a cancel, not a click; the face takes touches again in the next turn
            function cancelFaceTouch() {
                watchfaceLoader.enabled = false
                Qt.callLater(function () { watchfaceLoader.enabled = true })
            }
            // stock's "Edit watch face" accessibility action: the long click that opens the picker
            Accessible.role: Accessible.Pane
            //% "Watch face"
            Accessible.name: qsTrId("id-face-watchface") + localeManager.changesObserver
            //% "Edit watch face"
            Accessible.description: qsTrId("id-face-edit") + localeManager.changesObserver
            Accessible.onPressAction: desktop.openFacePicker()
            // the face on screen and its file, for the clock (checkSeconds)
            readonly property Item activeFace: nightstandWatchfaceActive ? nightstandWatchfaceLoader.item : watchfaceLoader.item
            readonly property url activeSource: nightstandWatchfaceActive ? nightstandMode.watchfaceSource : watchFaceSource.value
            onActiveFaceChanged: Qt.callLater(desktop.checkSeconds)
            Loader {
                id: nightstandWatchfaceLoader
                opacity: nightstandWatchfaceActive ? 1.0 : 0.0
                visible: opacity
                anchors.fill: parent
                source: nightstandMode.watchfaceSource
                onLoaded: complications.attach(item, source)
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InCirc } }
            }
            Loader {
                id: watchfaceLoader
                opacity: !nightstandWatchfaceActive ? 1.0 : 0.0
                visible: opacity
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InCirc} }
                anchors.fill: parent
                source: watchFaceSource.value
                // the complications of the favourite (its id is the key), not of the face's file
                onLoaded: complications.attach(item, favs.currentId !== "" ? favs.currentId : source)

                // Reinstantiate to re-read the source from disk. Toggling the
                // Loader instead of rewriting the dconf-backed watchFaceSource
                // avoids a cross-process write that can clobber a concurrent
                // activation.
                Connections {
                    target: desktop
                    function onWatchfaceReloadRequested() {
                        watchfaceLoader.active = false
                        watchfaceLoader.active = true
                    }
                }
            }
        }
    }
}
