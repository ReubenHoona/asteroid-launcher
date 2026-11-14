/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The content of Recents (app-launcher-18, -19): the frame of the app list
 * with the header "Recents", the apps that were used last as the same
 * rows (newest first, at most 8), an "All apps" edge button (up to 2 lines,
 * no icon) and, when there is none, "Recently used apps will appear here".
 * A row of an app with an ongoing activity shows its status line.
 *
 * entries: [{ item, key, desktop, front, ongoing, status }] from recents.js
 * build(). Recents.qml (the overlay) owns the history and answers the signals.
 */
WearList {
    id: root

    property var entries: []

    signal allAppsClicked()

    // the rows' items, rebuilt when the entries change
    ListModel { id: rows }
    function _fill() {
        rows.clear()
        for (var i = 0; i < entries.length; i++)
            rows.append({ object: entries[i].item })
    }
    onEntriesChanged: _fill()
    Component.onCompleted: _fill()

    model: rows
    //% "Recents"
    headerText: qsTrId("id-recents-header") + localeManager.changesObserver
    //% "Recently used apps will appear here"
    emptyText: qsTrId("id-recents-empty") + localeManager.changesObserver
    //% "All apps"
    edgeText: qsTrId("id-all-apps") + localeManager.changesObserver
    edgeIcon: ""
    colorOf: function (path) { return alb.centerColor(path) }
    statusOf: function (object) {
        for (var i = 0; i < root.entries.length; i++)
            if (object && root.entries[i].item.filePath === object.filePath)
                return root.entries[i].status
        return ""
    }
    onEdgeClicked: allAppsClicked()
}
