/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "wear"

/*
 * The app grid of Wear OS 6 (W2-launcher-app-list, app-launcher-16): the same
 * "Apps" header and edge button frame as the list, then the apps as 48 dp
 * circle icons without labels, three to a row, 6 dp apart, alphabetical by
 * name. Stock's grid edge spec: rows shrink to 0.2 and fade out at both
 * edges, and the two side columns of a row come together and move up or down
 * as it shrinks. The "List view" edge button goes back and saves the choice
 * (Settings > General > App view shows the same key). See wear/WearApps.qml.
 */
WearApps {
    columns: 3
    //% "Apps"
    headerText: qsTrId("id-apps-header") + localeManager.changesObserver
    //% "List view"
    edgeText: qsTrId("id-list-view") + localeManager.changesObserver
    edgeIcon: "ios-list"
    otherView: Qt.resolvedUrl("006-wear-list.qml")
}
