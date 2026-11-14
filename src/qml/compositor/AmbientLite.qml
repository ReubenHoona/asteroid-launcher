/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Effects
import Amber.Mpris
import org.nemomobile.lipstick
import org.asteroid.controls
import "../home/ambient.js" as Ambient
import "lifecycle.js" as Life

/* The always-on screen over an open application (W2-launcher-ambient,
 * audit ambient-aod-01, media-controls-15). Stock Wear OS keeps the
 * application on top in ambient and, for one that does not draw its own
 * always-on look, shows Ambient Lite (CSUI AmbientLiteOverlay): a black
 * layer, the application's last frame scaled 0.95 and blurred (15 px) and
 * the time in the middle, 'h:mm' without AM/PM or 'HH:mm', 80 px white, letter
 * spacing 0.02 em. It comes in over 200 ms with PathInterpolator(0.4, 0, 0.2,
 * 1): snapshot scale 1.0 -> 0.95, clock scale 1.1 -> 0.95, clock alpha 0 -> 1;
 * leaving is the same backwards. The application is not closed.
 *
 * The media player with a playing or paused session gets its own layout
 * (kind "media"): no artwork, the time at the top, the title and artist,
 * the previous / play / next buttons and the output pill as outlines
 * (1 dp, primaryDim 50 % and onSurface 38 %), nothing animated.
 *
 * The time is two Text items named eosHubHour and eosHubMinute (tabular
 * digits, native rendering, whole size, no scale at rest): HubOffload
 * (updateOverlay) hands this layout to the sensor hub, which then draws the
 * time while the AP sleeps. AmbientController decides when. The snapshot is
 * taken once at the ambient entry (and kept for the minute updates), never per
 * minute.
 *
 * Instantiated once in compositor.qml as `ambientLite`; sourceItem is the
 * application layer. Reads compositor.qml's `comp` (AppLifecycle) through the
 * context, as the other compositor parts do. */
Item {
    id: lite
    objectName: "eosAmbientLite"

    property Item sourceItem
    property bool use12h: false
    property date shown: new Date()
    // the media session: {present, title, artist, state}
    property var media: null
    // "none", "lite" or "media"
    property string kind: "none"
    // another snapshot or media content: the sensor hub's layout is rebuilt
    property int serial: 0
    property real progress: 0
    // the locale's zero digit (HubOffload draws the same digits)
    property string zeroDigit: Ambient.zeroOf(new Date(2000, 0, 1, 0, 0).toLocaleString(Qt.locale(), "mm"))

    // the application in front is the media player (its desktop name)
    property string mediaAppKey: "asteroid-music"
    readonly property Item frontWindow: comp ? comp.topmostWindow : null
    readonly property bool mediaOnTop: comp && comp.appActive && frontWindow !== null && frontWindow.window
                                       && Life.appKey(frontWindow.window.appKey) === mediaAppKey
    // a playing or paused session while the player is in front: the player stays
    // (stock: Media Controls posts an ongoing activity, so it is not sent back to
    // the face) and has its own ambient layout
    readonly property bool mediaHeld: mediaOnTop && Ambient.mediaActive(media)

    // What plays (a D-Bus listener only while the player is in front)
    Loader {
        active: lite.mediaOnTop
        sourceComponent: QtObject {
            property MprisController mpris: MprisController { }
            readonly property var state: ({
                present: mpris.currentService !== "" && mpris.currentService !== undefined
                         && mpris.metaData.title !== undefined && mpris.metaData.title !== "",
                title: mpris.metaData.title || "",
                artist: (mpris.metaData.contributingArtist || []).join(", "),
                state: mpris.playbackStatus === Mpris.Playing ? "Playing"
                       : mpris.playbackStatus === Mpris.Paused ? "Paused" : "Stopped"
            })
            onStateChanged: lite.media = state
            Component.onCompleted: lite.media = state
        }
    }

    /* What draws the always-on screen now (ambient.js mode): the face, Ambient
     * Lite, the media layout, or an application that handles ambient itself. */
    function modeNow() {
        var w = frontWindow
        return Ambient.mode({
            alwaysOn: true,
            appOpen: !!comp && comp.appActive && w !== null,
            handlesAmbient: !!w && !!w.window && w.window.handlesAmbient === true,
            mediaApp: mediaOnTop,
            media: media
        })
    }

    Connections {
        target: Lipstick.compositor
        function onDisplayAmbientEntered() {
            var m = lite.modeNow()
            if (m === "lite" || m === "media")
                lite.begin(m)
        }
        function onDisplayAmbientUpdate() { lite.update() }
        function onDisplayAboutToBeOn() { lite.end() }
        function onDisplayOn() { lite.end() }
    }

    // The entry hold is over: the sensor hub draws this layout from now on and
    // the AP can sleep. False: the hub refused it, the AP keeps drawing.
    function handOver() {
        if (!showing)
            return false
        return hubOffload.updateOverlay(hubFace, use12h, layoutKey, shown)
    }

    readonly property bool showing: kind !== "none"
    // the item whose eosHubHour / eosHubMinute children the hub draws
    readonly property Item hubFace: clock
    // the key of what the hub's layout shows (another one: a new layout)
    readonly property string layoutKey: kind === "media" ? "media:" + Ambient.mediaKey(media) : "lite:" + serial
    readonly property var parts: Ambient.clockParts(shown, use12h)
    readonly property real clockScale: Ambient.clockScaleAt(progress)

    visible: showing
    opacity: 1

    function refreshTime() {
        shown = new Date()
    }

    // The ambient entry with an application (kind "lite") or the media
    // player (kind "media") in front
    function begin(k) {
        exitAnim.stop()
        refreshTime()
        kind = k
        serial++
        if (k === "lite")
            snapshot.scheduleUpdate()
        if (Motion.animationScale > 0 && k === "lite") {
            progress = 0
            enterAnim.restart()
        } else {
            progress = 1
        }
    }

    // A minute update on the AP: the time, and the snapshot kept
    function update() {
        if (!showing)
            return
        refreshTime()
        if (kind === "lite")
            snapshot.scheduleUpdate()
    }

    // The wake: the animation backwards, then gone
    function end() {
        if (!showing)
            return
        enterAnim.stop()
        if (Motion.animationScale > 0 && kind === "lite" && progress > 0)
            exitAnim.restart()
        else
            finish()
    }
    function finish() {
        progress = 0
        kind = "none"
    }

    NumberAnimation {
        id: enterAnim
        target: lite
        property: "progress"
        from: 0
        to: 1
        duration: Ambient.LITE.ENTER_MS
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Ambient.LITE.EASING
    }
    NumberAnimation {
        id: exitAnim
        target: lite
        property: "progress"
        to: 0
        duration: Ambient.LITE.ENTER_MS
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Ambient.LITE.EASING
        onFinished: lite.finish()
    }

    // the black layer
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // the application's last frame, blurred, scaled 0.95 about the centre
    ShaderEffectSource {
        id: snapshot
        sourceItem: lite.kind === "lite" ? lite.sourceItem : null
        live: false
        visible: false
        recursive: false
        hideSource: false
    }
    MultiEffect {
        objectName: "eosLiteSnapshot"
        anchors.fill: parent
        visible: lite.kind === "lite"
        source: snapshot
        blurEnabled: true
        blur: 1.0
        blurMax: Ambient.LITE.BLUR_PX
        autoPaddingEnabled: false
        scale: Ambient.snapshotScaleAt(lite.progress)
    }

    // the time: Ambient Lite's in the middle, the media layout's at the top
    Item {
        id: clock
        objectName: "eosLiteClock"
        readonly property bool media: lite.kind === "media"
        readonly property int pixelSize: media ? Math.round(Theme.type.arcMedium.pixelSize) : Ambient.clockPixelSize()
        readonly property real spacing: media ? Theme.type.arcMedium.letterSpacing : Ambient.clockLetterSpacing()
        width: hourText.width + colonText.width + minuteText.width
        height: hourText.height
        x: (lite.width - width) / 2
        y: media ? Math.round(Theme.dp(14)) : (lite.height - height) / 2
        visible: lite.showing
        opacity: media ? 1 : lite.progress
        // 1.1 -> 0.95 of the final size: scale 1.1/0.95 -> 1 (the hub cannot scale a glyph)
        scale: media ? 1 : lite.clockScale
        transformOrigin: Item.Center

        Text {
            id: hourText
            objectName: "eosHubHour"
            x: 0
            text: Ambient.localizeDigits(lite.parts.hour, lite.zeroDigit)
            color: "white"
            renderType: Text.NativeRendering
            font { family: Theme.fontFamily; pixelSize: clock.pixelSize; weight: Font.DemiBold; letterSpacing: clock.spacing }
        }
        Text {
            id: colonText
            objectName: "eosLiteColon"
            x: hourText.width
            text: ":"
            color: "white"
            renderType: Text.NativeRendering
            font: hourText.font
        }
        Text {
            id: minuteText
            objectName: "eosHubMinute"
            x: hourText.width + colonText.width
            text: Ambient.localizeDigits(lite.parts.minute, lite.zeroDigit)
            color: "white"
            renderType: Text.NativeRendering
            font: hourText.font
        }
    }

    // ---- the media player's ambient layout (media-controls-15) -------------
    Item {
        id: mediaLayout
        objectName: "eosAmbientMedia"
        anchors.fill: parent
        visible: lite.kind === "media"

        readonly property color outline: Qt.rgba(Theme.color.primaryDim.r, Theme.color.primaryDim.g,
                                                Theme.color.primaryDim.b, 0.5)
        readonly property color pill: Qt.rgba(Theme.color.onSurface.r, Theme.color.onSurface.g,
                                              Theme.color.onSurface.b, 0.38)

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.20)
            width: parent.width * 0.8
            spacing: Math.round(parent.height * 0.01)
            Text {
                objectName: "eosAmbientTitle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                text: lite.media && lite.media.title ? lite.media.title : ""
                color: Theme.color.onSurface
                font { family: Theme.fontFamily; pixelSize: Math.round(Theme.type.titleMedium.pixelSize); weight: Font.Medium }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                text: lite.media && lite.media.artist ? lite.media.artist : ""
                color: Theme.color.onSurface
                opacity: 0.7
                font { family: Theme.fontFamily; pixelSize: Math.round(Theme.type.bodySmall.pixelSize) }
            }
        }

        // previous, play or pause, next: transparent, 1 dp border, primaryDim icons
        Row {
            objectName: "eosAmbientButtons"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.40)
            spacing: Math.round(parent.width * 0.03)
            Repeater {
                model: ["previous", "play", "next"]
                delegate: Item {
                    readonly property bool main: modelData === "play"
                    objectName: "eosAmbientButton-" + modelData
                    width: Math.round(lite.width * (main ? 0.24 : 0.17))
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: Math.round(Theme.dp(1))
                        border.color: mediaLayout.outline
                    }
                    Icon {
                        anchors.centerIn: parent
                        width: parent.width * 0.5
                        height: width
                        color: Theme.color.primaryDim
                        name: modelData === "previous" ? "ios-skip-backward"
                              : modelData === "next" ? "ios-skip-forward"
                              : lite.media && lite.media.state === "Playing" ? "ios-pause" : "ios-play"
                    }
                }
            }
        }

        // the output pill at the bottom
        Rectangle {
            objectName: "eosAmbientPill"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.76)
            width: Math.round(parent.width * 0.42)
            height: Math.round(Theme.dp(26))
            radius: height / 2
            color: "transparent"
            border.width: Math.round(Theme.dp(1))
            border.color: mediaLayout.pill
        }
    }
}
