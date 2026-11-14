/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "wear"

/*
 * The app list in the manner of Wear OS 6 (Pixel Watch, W2-launcher-app-list):
 * an "Apps" header 13 % under the top, one app per row (52 dp pills, the app's
 * circle icon and its name up to two lines, no scale on a press, the ripple),
 * rows shrinking and fading towards the top and especially the bottom of the
 * round screen as the launcher's own spec says, and a "Grid view" edge button
 * at the end. The curved position indicator and the crown (with its haptic
 * ticks) come with the list. No TimeText. See wear/WearApps.qml and
 * wear/WearList.qml.
 */
WearApps {
    columns: 1
    //% "Apps"
    headerText: qsTrId("id-apps-header") + localeManager.changesObserver
    //% "Grid view"
    edgeText: qsTrId("id-grid-view") + localeManager.changesObserver
    edgeIcon: "ios-grid"
    otherView: Qt.resolvedUrl("007-wear-grid.qml")
}
