/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.nemomobile.lipstick
import org.asteroid.controls

/*
 * The apps of the Wear layout, as list (006-wear-list.qml) or grid
 * (007-wear-grid.qml): the installed apps alphabetically by label in the
 * locale's order (LauncherSortModel: a new app lands in its place,
 * app-launcher-22) in a WearList, a tap launches (the splash grows out of the
 * icon), a long press opens the app's info (app-launcher-14), and the edge
 * button at the end switches to the other view and saves it
 * (/desktop/asteroid/applauncher, the key Settings > General > App view
 * writes too).
 *
 * What the panel grid expects of its app launcher (the Loader's toTopAllowed,
 * forbidTop... and launcherColorOverride) is set here: the swipe down leaves
 * the list only from its top, the list does not open any other panel.
 */
WearList {
    id: root

    // the view the edge button switches to
    property string otherView: ""
    property real tutorialScroll: 0
    property alias sorted: sortedModel
    // rows through the long press and edge button, for the tests
    property string viewKey: "/desktop/asteroid/applauncher"

    LauncherSortModel {
        id: sortedModel
        sourceModel: launcherModel
    }

    // a language change: the labels and their order change
    Connections {
        target: localeManager
        function onChangesObserverChanged() { sortedModel.resort() }
    }

    model: root.columns > 1 ? null : sortedModel
    cells: root.columns > 1 ? sortedModel : null
    colorOf: function (path) { return alb.centerColor(path) }

    onActivated: (object, origin) => {
        if (typeof desktop !== "undefined" && desktop.launchApp)
            desktop.launchApp(object, origin)
        else
            object.launchApplication()
    }
    // the long press opens the app's info page at once, no menu
    onLongPressed: (object) => {
        if (typeof desktop !== "undefined" && desktop.openAppInfo)
            desktop.openAppInfo(object)
    }
    onEdgeClicked: viewSetting.value = otherView

    ConfigurationValue {
        id: viewSetting
        key: root.viewKey
        defaultValue: ""
    }

    // the status slot's indicators pulse as the list moves from row to row
    property int _pos: 0
    Connections {
        target: root.view
        function onContentYChanged() {
            var p = Math.round((root.view.contentY + root.view.topMargin) / root.pitch)
            if (p === root._pos)
                return
            root._pos = p
            rightIndicator.animate()
            leftIndicator.animate()
            topIndicator.animate()
            bottomIndicator.animate()
        }
        function onAtYBeginningChanged() {
            // the grid only moves back to the watchface from the top of the list
            if ((grid.currentHorizontalPos === 0) && (grid.currentVerticalPos === 1)) {
                forbidTop = !root.view.atYBeginning
                grid.changeAllowedDirections()
            }
        }
    }

    Connections {
        target: grid
        function onCurrentVerticalPosChanged() {
            if (grid.currentVerticalPos === 0) {
                // back on the watchface: the list opens at the top again
                root.resetPosition()
            } else if (grid.currentVerticalPos === 1) {
                forbidTop = !root.view.atYBeginning
                grid.changeAllowedDirections()
            }
        }
    }

    Component.onCompleted: {
        toLeftAllowed = false
        toRightAllowed = false
        toBottomAllowed = Qt.binding(function() { return !root.view.atYBeginning })
        toTopAllowed = Qt.binding(function() { return !root.view.atYEnd })
        forbidTop = Qt.binding(function() { return !root.view.atYBeginning })
        forbidBottom = false
        forbidLeft = false
        forbidRight = false
        launcherColorOverride = true
    }
}
