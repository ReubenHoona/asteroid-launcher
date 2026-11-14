/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Amber.Mpris
import Nemo.Configuration
import org.asteroid.launcher

/* Autolaunch media controls (media-controls-16), as stock's Media Controls (jbk.java, MS/fxl.java):
 * with the setting on (Settings > General > "Autolaunch media controls", dconf
 * /org/asteroidos/ux/autolaunch-media, off by default), a new session of the phone that starts
 * playing opens the music app (the one MediaOngoing's tap opens), unless something that must not
 * be covered is up (a call, a firing alarm, the assistant, setup, the emergency screens, the touch
 * lock) or the app in front claimed the keys (a workout: stock's "restricted" app). The display is
 * not turned on: with the display off or ambient the always-on media layout shows instead.
 * One single-shot timer of 600 s starts with the launch; a touch or a key press while it runs, or
 * the session ending, cancels it; when it ends with no interaction the watch goes to the face.
 * The player is followed by D-Bus signals only (Amber.Mpris); nothing polls and nothing runs
 * while the setting is off. Fed by the arbiter (`blocked`, `restricted`, `appFront`, `userInput()`). */
Item {
    id: auto
    objectName: "mediaAutoLaunch"
    visible: false

    /* a surface that must not be covered is up */
    property bool blocked: false
    /* the app in front claimed the side button or the crown */
    property bool restricted: false
    /* an app is in front: leaving it at the end of the 600 s is a Home */
    property bool appFront: false

    // the 600 s of stock (MS/fxl.java:739-741)
    readonly property int interactionMs: 600000
    readonly property bool autoLaunchOn: setting.value === true || setting.value === "true"
    // we opened the app and nobody touched it since
    readonly property bool waiting: giveUp.running
    readonly property alias timer: giveUp
    // what was opened (the test reads it)
    property int launches: 0
    property string lastLaunched: ""

    // the end of the 600 s: the watch goes to the face
    signal goHome()

    ConfigurationValue { id: setting; key: "/org/asteroidos/ux/autolaunch-media"; defaultValue: false }
    AppLauncher { id: launcher }

    property MprisController mpris: MprisController { }

    readonly property string service: mpris.currentService === undefined ? "" : mpris.currentService
    readonly property string title: mpris.metaData && mpris.metaData.title !== undefined ? String(mpris.metaData.title) : ""
    readonly property bool playing: service !== "" && title !== "" && mpris.playbackStatus === Mpris.Playing
    // the session that is playing; a new one is a different service or a different track that
    // started playing (the key of the last one opened is kept)
    readonly property string sessionKey: playing ? service + "|" + title : ""
    property string handledKey: ""

    onSessionKeyChanged: {
        if (sessionKey === "") {
            // stopped, paused or gone: the session ended
            cancel()
            return
        }
        if (sessionKey === handledKey)
            return
        handledKey = sessionKey
        if (autoLaunchOn && !blocked && !restricted)
            open()
    }

    function open() {
        launcher.launchApp("asteroid-music")
        launches++
        lastLaunched = "asteroid-music"
        giveUp.restart()
    }

    // a touch or a key press (the arbiter): the user is there, the 600 s end
    function userInput() {
        if (giveUp.running)
            giveUp.stop()
    }
    function cancel() {
        if (giveUp.running)
            giveUp.stop()
    }

    Timer {
        id: giveUp
        interval: auto.interactionMs
        repeat: false
        onTriggered: if (auto.appFront) auto.goHome()
    }
}
