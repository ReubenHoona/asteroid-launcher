/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.launcher
import org.nemomobile.lipstick

/* The app error dialogs of the compositor (system-dialogs-misc-01, -02, -03):
 * the crash watcher's `appWatcher` (a context object, src/appwatcher.cpp)
 * tells that a program died of a crash for the second time within 120 s, the
 * compositor tells that the app in front did not answer its ping for 5 s
 * (clientNotResponding); this item shows CrashDialog for either and does
 * what its buttons ask.
 *   App info   Settings > Apps > the app (the launcher's own app info route)
 *   Close app  a crashed app is gone already; an unresponsive one is killed
 *   Wait       the compositor pings again and waits another 5 s
 * Nothing here runs while no dialog is up. Instantiated by OverlayArbiter
 * at z `arbiter.layers.errorDialog`. */
Item {
    id: errors
    objectName: "appErrors"
    anchors.fill: parent

    readonly property alias dialog: dialog
    readonly property alias launcher: launcher
    readonly property bool shown: dialog.shown
    readonly property bool cancelable: dialog.cancelable
    // the window of the unresponsive app now on the dialog
    property int anrWindowId: -1

    function close() { dialog.close() }

    /* the name of an app for its title: its desktop entry's, else the window's */
    function titleOf(key, fallback) {
        var t = typeof appWatcher !== "undefined" && appWatcher ? appWatcher.titleFor(key) : ""
        return t !== "" ? t : (fallback || key)
    }

    function showCrash(key, title) {
        if (dialog.shown && dialog.kind === "anr")
            return
        dialog.show("crash", title !== "" ? title : titleOf(key, key), key)
    }

    function showAnr(windowId, key, title) {
        anrWindowId = windowId
        dialog.show("anr", titleOf(key, title), key)
    }

    Connections {
        target: typeof appWatcher !== "undefined" ? appWatcher : null
        ignoreUnknownSignals: true
        function onRepeatedCrash(key, title) { errors.showCrash(key, title) }
    }
    Connections {
        target: Lipstick.compositor
        ignoreUnknownSignals: true
        function onClientNotResponding(windowId, appKey, title) { errors.showAnr(windowId, appKey, title) }
    }

    AppLauncher { id: launcher }
    ConfigurationValue { id: settingsOpenApp; key: "/org/asteroidos/settings/ui/open-app"; defaultValue: "" }
    ConfigurationValue { id: settingsOpen; key: "/org/asteroidos/settings/ui/open"; defaultValue: "" }

    CrashDialog {
        id: dialog
        onAppInfoRequested: (key) => {
            // Settings reads the app's file name and the route, as MainScreen.openAppInfo
            settingsOpenApp.value = key + ".desktop"
            settingsOpen.value = "app_info@" + Date.now()
            launcher.launchApp("asteroid-settings")
        }
        onCloseAppRequested: (key) => {
            if (kind === "anr" && errors.anrWindowId >= 0 && Lipstick.compositor.killClientForWindowId)
                Lipstick.compositor.killClientForWindowId(errors.anrWindowId)
        }
        onWaitRequested: (key) => {
            if (errors.anrWindowId >= 0 && Lipstick.compositor.waitForClientForWindowId)
                Lipstick.compositor.waitForClientForWindowId(errors.anrWindowId)
        }
    }
}
