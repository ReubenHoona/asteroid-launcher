/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.nemomobile.lipstick
import org.asteroid.controls
import "desktop.js" as Desktop
import "recents.js" as RecentsRules
import "compositor/lifecycle.js" as Life

/*
 * Recents, the side button's short press (W2-launcher-app-list,
 * app-launcher-18, -19, -20): the frame of the app list (AppDrawer: it comes in
 * as an app does, a swipe right or the crown closes it; no TimeText) with the
 * rows of the apps used last, at most 8, newest first, the one in front first.
 *
 *   - the side button again closes it (toggle(), KeyRouter);
 *   - a tap on a row opens the app (it comes back from the background when it
 *     runs: MainScreen.launchApp);
 *   - a long press opens a dialog titled with the app's name and two buttons:
 *     "Clear from Recents" (the app leaves the list and, running in the
 *     background, is closed) and "App Info" (Settings, as the list's long press);
 *   - "All apps" closes Recents and opens the list at its top;
 *   - an app with an ongoing activity shows its status line.
 *
 * The history ({file name, launch time}) is written to dconf when an app is
 * launched or cleared, never read on a timer. Recents opens over the home
 * screen and over the app in front: MainScreen raises itself while it is open
 * (z 2.4: under calls, alarms and the assistant).
 */
AppDrawer {
    id: recents

    /* Over the face the face behind shrinks and dims (AppDrawer face*); over an
     * application the application does (AppDrawer behind*, WindowTransitions):
     * stock opens Recents with the app launch transition, whose closing task is
     * whatever is in front (WearAppLaunchMixinTransition$$ExternalSyntheticLambda0
     * .java:29-35: scale 1 - 0.3 p about the centre, a black dim 0.5 p, on the
     * 1.0/260 baseline spring). Decided when it opens (show()). */
    movesFace: false

    /* Over an application the face is not drawn behind Recents (MainScreen's
     * faceStack): the application is there. Read live, not fixed at show():
     * when the application leaves while Recents is open (the crown: keymap
     * leaveApp), the home screen is in front again and the face is drawn under
     * the closing disc, as before Recents moved what is behind it. */
    readonly property bool hidesFace: isOpen && !movesFace && !Lipstick.compositor.homeActive

    // the list: the file of the shared frame, loaded at the first opening
    // (AppDrawer loads its source at once, so none is set until then)
    readonly property string listSource: "file:///usr/share/asteroid-launcher/applauncher/wear/WearRecents.qml"

    /* what is shown: recents.js build() */
    property var entries: []
    property var statuses: ({})
    // the dialog's app
    property var dialogEntry: null
    readonly property alias history: store
    readonly property alias dialogBox: dialog

    signal allAppsRequested()
    signal appInfoRequested(var item)
    // show() was called, movesFace is decided: WindowTransitions notes the window
    // in front, the one Recents opens over (only it shrinks and dims behind it)
    signal showing()

    ConfigurationValue {
        id: store
        key: "/org/asteroidos/ux/recents"
        defaultValue: "[]"
    }

    // the apps the user hid leave Recents too (CR-19: the list, the grid and Recents)
    ConfigurationValue {
        id: hiddenApps
        key: "/org/asteroidos/launcher/hidden-apps"
        defaultValue: []
    }

    // all the apps of the launcher but the hidden ones
    function launcherItems() {
        var items = []
        if (typeof launcherModel === "undefined")
            return items
        var hidden = hiddenApps.value
        for (var i = 0; i < launcherModel.itemCount; i++) {
            var it = launcherModel.get(i)
            if (it && it.object)
                it = it.object
            if (it && !RecentsRules.hiddenApp(it.filePath, hidden))
                items.push(it)
        }
        return items
    }

    function keyOf(item) {
        return Life.appKey(item.exec ? item.exec : item.filePath)
    }

    // an app was launched: it is the newest
    function record(item) {
        if (!item || !item.filePath)
            return
        var d = RecentsRules.desktopId(item.filePath)
        if (!RecentsRules.recordable(d))
            return
        store.value = RecentsRules.stringify(RecentsRules.record(RecentsRules.parse(store.value), d, Date.now()))
    }

    function forget(desktop) {
        store.value = RecentsRules.stringify(RecentsRules.forget(RecentsRules.parse(store.value), desktop))
    }

    // the list for the apps in front and running now
    function rebuild() {
        var comp = Desktop.compositorRoot
        var live = comp && comp.recents ? comp.recents() : []
        var front = live.length > 0 && live[0].front ? live[0].key : ""
        var running = []
        for (var i = 0; i < live.length; i++)
            if (!live[i].front)
                running.push(live[i].key)
        var life = comp && comp.lifecycle ? comp.lifecycle : null
        statuses = life && life.ongoingStatus ? life.ongoingStatus : ({})
        entries = RecentsRules.build(launcherItems(), keyOf, front, running,
                                     life && life.ongoingKeys ? life.ongoingKeys : ({}),
                                     RecentsRules.parse(store.value), statuses)
    }

    // the side button: opens it, or closes it when it is open (true: it did one of them)
    function toggle() {
        if (isOpen && progress > 0.5) {
            close()
            return true
        }
        show()
        return true
    }

    function show() {
        rebuild()
        if (String(source) === "")
            source = listSource
        movesFace = Lipstick.compositor.homeActive
        showing()
        open()
    }

    // the list's rows
    Connections {
        target: launcher.item
        ignoreUnknownSignals: true
        function onActivated(object, origin) { recents.activate(object, origin) }
        function onLongPressed(object) { recents.longPress(object) }
        function onAllAppsClicked() { recents.closeNow(); recents.allAppsRequested() }
    }
    Connections {
        target: launcher
        function onLoaded() {
            launcher.item.entries = Qt.binding(function() { return recents.entries })
        }
    }

    function activate(object, origin) {
        closeNow()
        if (typeof desktop !== "undefined" && desktop.launchApp)
            desktop.launchApp(object, null)
        else if (object && object.launchApplication)
            object.launchApplication()
    }

    function entryOf(object) {
        for (var i = 0; i < entries.length; i++)
            if (object && entries[i].item.filePath === object.filePath)
                return entries[i]
        return null
    }

    function longPress(object) {
        var e = entryOf(object)
        if (!e)
            return
        dialogEntry = e
        dialog.open()
    }

    // "Clear from Recents": out of the history; an app in the background closes
    function clear(entry) {
        if (!entry)
            return
        forget(entry.desktop)
        var comp = Desktop.compositorRoot
        if (comp && comp.recents && comp.closeHidden) {
            var live = comp.recents()
            for (var i = 0; i < live.length; i++)
                if (!live[i].front && live[i].key === entry.key)
                    comp.closeHidden(live[i].windowId)
        }
        rebuild()
    }

    AlertDialog {
        id: dialog
        z: 20
        title: recents.dialogEntry ? recents.dialogEntry.item.title : ""
        buttons: "none"
        closeOnAction: true

        Button {
            id: clearButton
            objectName: "clearFromRecents"
            width: parent ? parent.width : Theme.dp(172)
            centered: true
            maximumLineCount: 2
            //% "Clear from Recents"
            text: qsTrId("id-recents-clear")
            onClicked: {
                recents.clear(recents.dialogEntry)
                dialog.close()
            }
        }
        Button {
            id: infoButton
            objectName: "appInfo"
            width: parent ? parent.width : Theme.dp(172)
            centered: true
            //% "App Info"
            text: qsTrId("id-recents-app-info")
            onClicked: {
                var item = recents.dialogEntry ? recents.dialogEntry.item : null
                dialog.close()
                if (item) {
                    recents.closeNow()
                    recents.appInfoRequested(item)
                }
            }
        }
    }
}
