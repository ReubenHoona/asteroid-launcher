/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "../desktop.js" as Desktop

/*
 * What the modes show over everything while they come on and go off, as
 * stock (CSUI modes/transitions/DefaultTransitionUiHandler.java,
 * AnimationFactory.java; the launcher's modes engine, modes.h, sends the
 * signals):
 *
 * Bedtime on (bedtimeStarting), "Starting Bedtime mode…": the screen fades
 * in over 1000 ms (the view and its content both, 0 to 1), the content
 * holds 2000 ms, fades out over 1000 ms (3000 to 4000 ms) and the black
 * stays 1000 ms more (to 5000 ms); then the watch face and the engine's
 * screen off. DefaultTransitionUiHandler.java:93-108 (mFadeOutToBlackBackground).
 * A button press that turns the screen off meanwhile ends it
 * (transitionCancelled): the face is put on top, as stock's finalize.
 * With the screen off the face is put on top after 2500 ms (bedtimeSkipped).
 *
 * Bedtime off (bedtimeEnding), "Turning off Bedtime mode…", only with the
 * home screen on top (BedtimeModeUiController.java:59-69): the same layout,
 * 1000 ms in, 2000 ms held, then two 150 ms steps (content 1 -> 0.1 and the
 * view 1 -> 0.9, then content 0.1 -> 0 and the view 0.9 -> 0), no face jump
 * and no sleep (DefaultTransitionUiHandler.java:109-124, AnimationFactory
 * createAlphaTransitionPhase). No toast.
 *
 * Theater on (theaterStarting): a black overlay fades in over 225 ms after
 * 225 ms (kzl.java: ah = 225), the face is put on top at 450 ms, where the
 * engine turns the screen off, and the overlay goes after 1000 ms.
 *
 * The layout is bedtime_entry_screen_v2.xml (px at 2 px per dp): a 160 px
 * square container with 48 px corners in system_primary_container_light
 * (#DBE2F9 on the Pixel Watch overlay), the glyph 72 px in
 * system_on_primary_container_light (#404759), 16 px under it; the text 32 px
 * (16 sp), white, weight 500, centred, 52 px (26 dp) either side, 16 px
 * under. The bed glyph is an original drawing in that box (the stock vector
 * is a Google asset).
 *
 * Mode transitions do not cover calls or firing alarms (they are activities
 * on top, stock; interruptions-16): no screen and no jump to the face while
 * one is up.
 */
Item {
    id: screen
    anchors.fill: parent
    visible: view.opacity > 0 || theaterOverlay.opacity > 0

    // the stock timings, ms (the tests read them)
    readonly property var timing: ({
        fadeIn: 1000,
        hold: 2000,
        fadeOut: 1000,
        black: 1000,
        exitStep: 150,
        exitStepContent: 0.1,
        exitStepView: 0.9,
        theaterDelay: 225,
        theaterFade: 225,
        theaterOverlayMs: 1000
    })
    // the stock layout, px
    readonly property real containerSize: Theme.dp(80)
    readonly property real containerRadius: Theme.dp(24)
    readonly property real glyphSize: Theme.dp(36)
    readonly property real iconMarginBottom: Theme.dp(8)
    readonly property real contentPadding: Theme.dp(26)
    readonly property real messagePaddingBottom: Theme.dp(8)
    readonly property color containerColor: "#DBE2F9"   // system_primary_container_light (AndroidOverlayPixelWatch)
    readonly property color glyphColor: "#404759"       // system_on_primary_container_light

    // "entry", "exit" or "": which of the two screens is up
    property string kind: ""
    // the content (container and text) fades apart from the view
    property real contentOpacity: 1
    readonly property bool playing: entryAnimation.running || exitAnimation.running

    readonly property bool interrupted: typeof arbiter !== "undefined" && arbiter && arbiter.interrupting
    // the home screen is on top (no application in front): asked when the
    // exit starts (desktop.js is a plain library, nothing tells a binding)
    function homeOnTop() {
        return !Desktop.compositorRoot || !Desktop.compositorRoot.lifecycle
               || Desktop.compositorRoot.lifecycle.homeActive !== false
    }

    // the watch face was put on top (tests listen)
    signal showingFace()
    function showFace() {
        showingFace()
        if (Desktop.desktop && Desktop.desktop.showWatchface)
            Desktop.desktop.showWatchface()
    }
    function reset() {
        entryAnimation.stop()
        exitAnimation.stop()
        theaterAnimation.stop()
        view.opacity = 0
        screen.contentOpacity = 1
        theaterOverlay.opacity = 0
        screen.kind = ""
    }
    function startEntry() {
        reset()
        kind = "entry"
        entryAnimation.start()
    }
    function startExit() {
        reset()
        kind = "exit"
        exitAnimation.start()
    }
    function cancel() {
        reset()
        showFace()
    }

    Connections {
        target: typeof modes !== "undefined" ? modes : null
        function onBedtimeStarting() {
            if (screen.interrupted)
                return
            screen.startEntry()
        }
        function onBedtimeSkipped() {
            if (screen.interrupted)
                return
            screen.showFace()
        }
        function onBedtimeEnding() {
            if (screen.interrupted || !screen.homeOnTop())
                return
            screen.startExit()
        }
        function onTransitionCancelled() {
            // the entry was cut short: stock's finalize puts the face on top
            // (and sleeps); the exit has nothing to finalize
            const wasEntry = screen.kind === "entry"
            screen.reset()
            if (wasEntry && !screen.interrupted)
                screen.showFace()
        }
        function onTheaterStarting() {
            if (screen.interrupted)
                return
            screen.reset()
            theaterAnimation.start()
        }
    }

    // Bedtime on: 1000 in, 2000 held, content 1000 out, 1000 black, then the face
    SequentialAnimation {
        id: entryAnimation
        ParallelAnimation {
            NumberAnimation { target: view; property: "opacity"; from: 0; to: 1; duration: screen.timing.fadeIn }
            NumberAnimation { target: screen; property: "contentOpacity"; from: 0; to: 1; duration: screen.timing.fadeIn }
        }
        PauseAnimation { duration: screen.timing.hold }
        NumberAnimation { target: screen; property: "contentOpacity"; to: 0; duration: screen.timing.fadeOut }
        PauseAnimation { duration: screen.timing.black }
        ScriptAction {
            script: {
                screen.showFace()
                screen.reset()
            }
        }
    }

    // Bedtime off: 1000 in, 2000 held, two steps of 150
    SequentialAnimation {
        id: exitAnimation
        ParallelAnimation {
            NumberAnimation { target: view; property: "opacity"; from: 0; to: 1; duration: screen.timing.fadeIn }
            NumberAnimation { target: screen; property: "contentOpacity"; from: 0; to: 1; duration: screen.timing.fadeIn }
        }
        PauseAnimation { duration: screen.timing.hold }
        ParallelAnimation {
            NumberAnimation { target: screen; property: "contentOpacity"; from: 1; to: screen.timing.exitStepContent; duration: screen.timing.exitStep }
            NumberAnimation { target: view; property: "opacity"; from: 1; to: screen.timing.exitStepView; duration: screen.timing.exitStep }
        }
        ParallelAnimation {
            NumberAnimation { target: screen; property: "contentOpacity"; from: screen.timing.exitStepContent; to: 0; duration: screen.timing.exitStep }
            NumberAnimation { target: view; property: "opacity"; from: screen.timing.exitStepView; to: 0; duration: screen.timing.exitStep }
        }
        ScriptAction { script: screen.reset() }
    }

    // Theater on: black 225 ms in after 225 ms, the face, away at 1000 ms
    SequentialAnimation {
        id: theaterAnimation
        PauseAnimation { duration: screen.timing.theaterDelay }
        NumberAnimation {
            target: theaterOverlay
            property: "opacity"
            from: 0
            to: 1
            duration: screen.timing.theaterFade
            easing.type: Easing.Linear
        }
        ScriptAction { script: screen.showFace() }
        PauseAnimation { duration: screen.timing.theaterOverlayMs - screen.timing.theaterDelay - screen.timing.theaterFade }
        ScriptAction { script: theaterOverlay.opacity = 0 }
    }

    // the Theater overlay is not under the view's own fade
    Rectangle {
        id: theaterOverlay
        objectName: "theaterOverlay"
        anchors.fill: parent
        color: "#000000"
        opacity: 0
    }
    // takes touches while a screen is up
    MouseArea {
        anchors.fill: parent
        enabled: screen.visible
    }

    // the Bedtime screen: black, faded as a whole (view) with its content
    Item {
        id: view
        objectName: "modeView"
        anchors.fill: parent
        opacity: 0

        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }

        Item {
            id: content
            objectName: "modeContent"
            anchors.fill: parent
            visible: screen.kind !== ""
            opacity: screen.contentOpacity

            Column {
                anchors.centerIn: parent
                width: parent.width - 2 * screen.contentPadding
                spacing: screen.iconMarginBottom

                Rectangle {
                    objectName: "modeContainer"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: screen.containerSize
                    height: width
                    radius: screen.containerRadius
                    color: screen.containerColor

                    // the bed, drawn in the glyph box (36 x 36 dp, the bed 33 x 22 in it)
                    Item {
                        id: glyph
                        objectName: "modeGlyph"
                        anchors.centerIn: parent
                        width: screen.glyphSize
                        height: width
                        readonly property real u: width / 36
                        // headboard
                        Rectangle {
                            x: 1.5 * glyph.u; y: 7.5 * glyph.u
                            width: 2.6 * glyph.u; height: 22 * glyph.u
                            radius: width / 2
                            color: screen.glyphColor
                        }
                        // footboard
                        Rectangle {
                            x: 31.8 * glyph.u; y: 17.5 * glyph.u
                            width: 2.6 * glyph.u; height: 12 * glyph.u
                            radius: width / 2
                            color: screen.glyphColor
                        }
                        // base
                        Rectangle {
                            x: 1.5 * glyph.u; y: 22.2 * glyph.u
                            width: 32.9 * glyph.u; height: 2.7 * glyph.u
                            radius: height / 2
                            color: screen.glyphColor
                        }
                        // blanket
                        Rectangle {
                            x: 16.8 * glyph.u; y: 10.8 * glyph.u
                            width: 17.6 * glyph.u; height: 9 * glyph.u
                            topLeftRadius: 2.5 * glyph.u; topRightRadius: 5 * glyph.u
                            color: screen.glyphColor
                        }
                        // pillow
                        Rectangle {
                            x: 5.4 * glyph.u; y: 12.6 * glyph.u
                            width: 8.4 * glyph.u; height: width
                            radius: width / 2
                            color: screen.glyphColor
                        }
                    }
                }
                Label {
                    objectName: "bedtimeStarting"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    clip: false
                    font.weight: Theme.weight(500)
                    bottomPadding: screen.messagePaddingBottom
                    text: screen.kind === "exit"
                          //% "Turning off Bedtime mode…"
                          ? qsTrId("id-bedtime-ending")
                          //% "Starting Bedtime mode…"
                          : qsTrId("id-bedtime-starting")
                }
            }
        }
    }
}
