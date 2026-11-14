/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import "tilecontent.js" as TC
import "exercisetypes.js" as Types

/*
 * Quick start, as the Fitbit exercise quick launch tile (tiles-individual-23, -24, health-fitness-31; aapr.java:47-103,
 * tile_quickstart_preview.xml): the title "Quick start", the three exercises started last as tall stadium buttons
 * with the sport icon (the first green #6DD58C, the others #A8C7FA; six on a screen of 225 dp or more, in two
 * rows), a tap starts that exercise ("Start Run" for the screen reader), the dark edge button "More" opens the
 * Exercise app. With no history the Exercise app's own six (Run, Hike, Bike, ...). While a workout runs: the title
 * "Exercise", a card "In progress" and the exercise name, and the edge button "Open".
 *
 * The recent list is the Exercise app's (/org/asteroidos/exercise/recent, newest first, comma separated). A tap
 * writes the app's start request ('<type>@<ms>', /org/asteroidos/exercise/start-request, as the launcher's own
 * "Start tracking?" action does) and starts the app. A running workout is the app's ongoing activity (the
 * launcher's ongoing registry), nothing is polled and nothing runs here.
 */
TileBase {
    id: tile
    objectName: "exerciseTile"
    title: (tile.running
            //% "Exercise"
            ? qsTrId("id-tile-exercise")
            //% "Quick start"
            : qsTrId("id-tile-quick-start")) + localeManager.changesObserver
    backgroundTap: false
    chipText: (tile.running
               //% "Open"
               ? qsTrId("id-tile-open")
               //% "More"
               : qsTrId("id-tile-more")) + localeManager.changesObserver
    chipColor: tile.running ? Theme.color.primary : Theme.color.surfaceContainerHigh
    chipContentColor: tile.running ? Theme.color.onPrimary : Theme.color.onSurface
    onChipClicked: desktop.launchByName("asteroid-exercise", null)

    ConfigurationValue { id: recent; key: "/org/asteroidos/exercise/recent"; defaultValue: "" }
    ConfigurationValue { id: startRequest; key: "/org/asteroidos/exercise/start-request"; defaultValue: "" }

    // the buttons the screen has: 3 on the Pixel Watch 2 (192 dp), 6 from 225 dp
    readonly property int count: Theme.isLargeScreen ? 6 : TC.EXERCISE_SHOWN
    readonly property var keys: TC.exerciseKeys(String(recent.value), function (k) { return Types.find(k) !== null }, count)

    // a workout running: the Exercise app's ongoing activity
    property var ongoing: null
    readonly property var activity: {
        var list = tile.entries
        for (var i = 0; i < list.length; i++)
            if (list[i] && list[i].app === "asteroid-exercise")
                return list[i]
        return null
    }
    readonly property var entries: ongoing && ongoing.entries ? ongoing.entries : []
    readonly property bool running: activity !== null
    Component.onCompleted: ongoing = typeof ongoingRegistry !== "undefined" ? ongoingRegistry : null

    function start(key) {
        startRequest.value = TC.exerciseRequest(key, Date.now())
        desktop.launchByName("asteroid-exercise", tile)
    }

    Grid {
        id: grid
        objectName: "exerciseButtons"
        visible: !tile.running
        anchors.fill: parent
        columns: 3
        spacing: Theme.dp(4)
        readonly property int rows: Math.ceil(tile.keys.length / 3)
        readonly property real cellWidth: (width - (columns - 1) * spacing) / columns
        readonly property real cellHeight: (height - (rows - 1) * spacing) / Math.max(1, rows)

        Repeater {
            model: tile.keys
            delegate: TileCard {
                id: button
                objectName: "exerciseButton" + index
                readonly property var type: Types.find(modelData)
                width: grid.cellWidth
                height: grid.cellHeight
                containerColor: index === 0 ? TC.EXERCISE_FIRST : TC.EXERCISE_OTHER
                contentColor: "#1B1B1F"
                preview: tile.preview
                //% "Start %1"
                accessibleName: qsTrId("id-tile-start-exercise").replace("%1", type ? type.name : modelData)
                onClicked: tile.start(modelData)

                Icon {
                    anchors.centerIn: parent
                    name: button.type ? button.type.icon : "ms-directions_walk"
                    color: "#1B1B1F"
                    width: Theme.dp(24)
                    height: width
                }
            }
        }
    }

    // a workout is on: "In progress" and its name
    TileCard {
        id: progress
        objectName: "exerciseProgress"
        visible: tile.running
        width: parent.width
        height: Math.min(Theme.dp(52), parent.height)
        anchors.verticalCenter: parent.verticalCenter
        containerColor: Theme.color.surfaceContainer
        contentColor: Theme.color.onSurface
        radius: Theme.dp(26)
        preview: tile.preview
        accessibleName: tile.title
        onClicked: desktop.launchByName("asteroid-exercise", progress)

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.dp(14)
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                //% "In progress"
                text: qsTrId("id-tile-in-progress") + localeManager.changesObserver
                role: "titleSmall"
                color: Theme.color.primary
                maximumLineCount: 1
            }
            Label {
                objectName: "exerciseName"
                visible: text !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.activity && tile.activity.status ? String(tile.activity.status) : ""
                role: "bodyMedium"
                color: Theme.color.onSurface
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }
}
