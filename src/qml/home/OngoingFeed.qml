/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.nemomobile.lipstick

/* What feeds the ongoing activity registry from the notification list, and what a tap on
 * the chip does (W2-launcher-status, audit status-indicators-11, -12). An app that posts
 * a notification with the hints of eosongoing.h (x-eos-ongoing, ...) is an ongoing
 * activity: the list goes to ongoingRegistry.syncNotifications() when it changes
 * (coalesced: once per burst, never polled), the registry keeps the ongoing ones. The
 * apps the user turned off (Settings > Notifications > an app > Live updates, or the
 * chip's long press) are in the dconf list /org/asteroidos/ongoing/muted-apps (desktop
 * file ids) and go to the registry, whose `top` skips them.
 * A tap on the chip: the registry says which entry and app; an app opens like a launch
 * from the app list (the home screen's launchByName); a call and the media session
 * answer on their own (IncomingCall).
 * Reads the home screen's `desktop` through the context. */
Item {
    id: feed
    visible: false

    readonly property QtObject registry: typeof ongoingRegistry !== "undefined" ? ongoingRegistry : null
    property alias mutedApps: muted.value
    // how many times the list went to the registry (the tests)
    property int syncs: 0

    ConfigurationValue {
        id: muted
        key: "/org/asteroidos/ongoing/muted-apps"
        defaultValue: []
    }

    // a mute of the registry's `mutedApps` follows the setting
    Binding {
        target: feed.registry
        property: "mutedApps"
        value: muted.value ? muted.value : []
        when: feed.registry !== null
    }

    function mute(app) {
        if (!app)
            return
        var list = []
        var cur = muted.value
        for (var i = 0; cur && i < cur.length; i++)
            list.push(cur[i])
        if (list.indexOf(app) < 0)
            list.push(app)
        muted.value = list
    }

    function sync() {
        if (!syncPending) {
            syncPending = true
            Qt.callLater(doSync)
        }
    }
    property bool syncPending: false
    function doSync() {
        syncPending = false
        if (registry === null)
            return
        var items = []
        for (var i = 0; i < model.itemCount; i++) {
            var n = model.get(i)
            if (n)
                items.push({ id: n.replacesId, appName: n.appName, category: n.category, hints: n.hints })
        }
        syncs++
        registry.syncNotifications(items)
    }

    NotificationListModel {
        id: model
        onItemAdded: feed.sync()
        onRowsRemoved: feed.sync()
    }
    Connections {
        target: model
        ignoreUnknownSignals: true
        function onDataChanged() { feed.sync() }
        function onRowsMoved() { feed.sync() }
    }
    Component.onCompleted: sync()

    // the chip was tapped: an app opens
    Connections {
        target: feed.registry
        ignoreUnknownSignals: true
        function onActivated(key, app) {
            if (app && typeof desktop !== "undefined" && desktop && desktop.launchByName)
                desktop.launchByName(app, null)
        }
    }
}
