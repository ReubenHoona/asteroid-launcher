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

/* The watch face of the home screen (split out of MainScreen.qml): which
 * face (dconf), its options, the clock it needs (seconds or minutes), and
 * `panel`, the centre panel of the grid that loads it (Trays places it).
 * Instantiated once in MainScreen as `faceLayer`; reads MainScreen's
 * shared ids (desktop, nightstandMode, complications, use12H, facePicker,
 * burnInProtectionManager) through the context. Owned by the face
 * packages (face picker, faces, complications). */
Item {
    id: faceLayer

    readonly property var faceSource: watchFaceSource.value
    readonly property var faceShowDateValue: faceShowDate.value
    readonly property var faceAmbientStyleValue: faceAmbientStyle.value
    readonly property var faceComplicationsValue: faceComplications.value
    property bool faceSecondsShown: false

    function chooseFace(face) {
        watchFaceSource.value = face
    }

    function openFacePicker() {
        facePicker.current = watchFaceSource.value
        facePicker.open()
    }

    ConfigurationValue {
        id: watchFaceSource
        key: "/desktop/asteroid/watchface"
        defaultValue: "file:///usr/share/asteroid-launcher/watchfaces/000-default-digital.qml"
        onValueChanged: burnInProtectionManager.resetOffsets()
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
        faceSecondsShown = faceShowSeconds.value
                           && watchfaceReloader.secondsShown(desktop.centreItem.activeFace, desktop.centreItem.activeSource)
    }

    /* The watchface options of the face picker, for every face: date and
     * seconds shown or not (seconds never in always-on mode, as on Wear OS),
     * and how the always-on face looks: "dim" (the face in grey: 55 %) or
     * "outline" (grey letter outlines, and the rest dimmed) */
    ConfigurationValue {
        id: faceShowDate
        key: "/org/asteroidos/watchface/show-date"
        defaultValue: true
        onValueChanged: Qt.callLater(desktop.checkSeconds)
    }
    ConfigurationValue {
        id: faceShowSeconds
        key: "/org/asteroidos/watchface/show-seconds"
        defaultValue: true
        onValueChanged: Qt.callLater(desktop.checkSeconds)
    }
    ConfigurationValue {
        id: faceAmbientStyle
        key: "/org/asteroidos/watchface/ambient-style"
        defaultValue: "dim"
        onValueChanged: Qt.callLater(desktop.checkSeconds)
    }
    function applyFaceOptions() {
        if (!desktop.centreItem || !desktop.centreItem.activeFace)
            return
        watchfaceReloader.applyFaceOptions(desktop.centreItem.activeFace, faceShowDate.value, faceShowSeconds.value,
                                           displayAmbient, faceAmbientStyle.value)
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

    // the complications chosen for the face (the date shows in always-on)
    ConfigurationValue {
        id: faceComplications
        key: complications.configKey(complications.faceName(watchFaceSource.value))
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
            property bool nightstandWatchfaceActive: nightstandMode.active && nightstandMode.useCustomWatchface && nightstandMode.watchfaceSource != watchFaceSource.value
            // always-on: the face in grey, not full white
            opacity: displayAmbient ? 0.55 : 1.0
            // Wear OS: a long press on the watchface opens the face picker
            // (under the face: a face's own buttons keep their presses)
            MouseArea {
                anchors.fill: parent
                z: -1
                enabled: !displayAmbient
                pressAndHoldInterval: 500
                onPressAndHold: {
                    Haptics.longPress()
                    desktop.openFacePicker()
                }
            }
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
                onLoaded: complications.attach(item, source)

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
