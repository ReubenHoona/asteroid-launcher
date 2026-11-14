/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import "tilecontent.js" as TC

/*
 * Maps, after the Google Maps tile (tiles-individual-28, apps-misc-11; maps_tile_*): the title, a map card (our own
 * drawing, a street map with a pin; a tap opens the Map app) and two green shortcut buttons "Home" and "Work" that
 * open the Map app at the saved place of that name, or on the map when there is none yet (a place is saved in the
 * Map app, with that name). The edge button "Map" (stock's own label of the map button, maps_tile_compass_button_text)
 * opens the Map app. Stock's "Search" and "Recents" need Google's online search: the Map app (OSM, offline) has none,
 * so the tile has no search button.
 *
 * Saved places are asteroid-map's /map/waypointList ([icon, [lat, lon], colour, name, date] each); opening at one
 * writes the map's view (/map/view/location/lat and long, millionths of a degree) and starts the app.
 * Battery: nothing runs.
 */
TileBase {
    id: tile
    objectName: "mapsTile"
    //% "Search & go"
    title: qsTrId("id-tile-maps-title") + localeManager.changesObserver
    backgroundTap: false
    //% "Map"
    chipText: qsTrId("id-tile-map") + localeManager.changesObserver
    onChipClicked: desktop.launchByName("asteroid-map", null)

    ConfigurationValue { id: waypoints; key: "/map/waypointList"; defaultValue: "[]" }
    ConfigurationValue { id: viewLat; key: "/map/view/location/lat"; defaultValue: 0 }
    ConfigurationValue { id: viewLon; key: "/map/view/location/long"; defaultValue: 0 }

    readonly property var home: TC.savedPlace(String(waypoints.value), "Home")
    readonly property var work: TC.savedPlace(String(waypoints.value), "Work")

    // opens the map at a place (the map reads its view when it starts)
    function go(place, from) {
        if (place) {
            viewLat.value = Math.round(place.lat * 1000000)
            viewLon.value = Math.round(place.lon * 1000000)
        }
        desktop.launchByName("asteroid-map", from)
    }

    Column {
        anchors.fill: parent
        spacing: Theme.dp(4)

        // the map: a drawing of streets with the pin
        TileCard {
            id: mapCard
            objectName: "mapsCard"
            width: parent.width
            height: Math.round((parent.height - parent.spacing) * 0.5)
            radius: Theme.dp(26)
            containerColor: "#34463A"
            contentColor: "#FFFFFF"
            preview: tile.preview
            //% "Open the map"
            accessibleName: qsTrId("id-tile-open-map")
            onClicked: tile.go(null, mapCard)
            // streets well inside the rounded ends
            Rectangle { x: mapCard.width * 0.18; y: mapCard.height * 0.5; width: mapCard.width * 0.64; height: Theme.dp(3); radius: height / 2; color: "#7A8F80" }
            Rectangle { x: mapCard.width * 0.35; y: mapCard.height * 0.2; width: Theme.dp(3); height: mapCard.height * 0.6; radius: width / 2; color: "#7A8F80" }
            Rectangle { x: mapCard.width * 0.68; y: mapCard.height * 0.22; width: Theme.dp(2); height: mapCard.height * 0.56; radius: width / 2; color: "#5E7364" }
            Rectangle { x: mapCard.width * 0.22; y: mapCard.height * 0.28; width: mapCard.width * 0.5; height: Theme.dp(2); radius: height / 2; color: "#5E7364" }
            Icon {
                x: mapCard.width * 0.35 + Theme.dp(1.5) - width / 2
                y: mapCard.height * 0.5 - height + Theme.dp(2)
                name: "ios-pin"
                color: "#F2655C"
                width: Theme.dp(22)
                height: width
            }
        }

        Row {
            width: parent.width
            spacing: Theme.dp(4)
            readonly property real buttonWidth: (width - spacing) / 2
            TileCard {
                id: homeButton
                objectName: "mapsHome"
                width: parent.buttonWidth
                height: parent.parent.height - mapCard.height - parent.parent.spacing
                containerColor: TC.GREEN
                contentColor: "#00391C"
                preview: tile.preview
                //% "Home"
                accessibleName: qsTrId("id-tile-home")
                onClicked: tile.go(tile.home, homeButton)
                Column {
                    anchors.centerIn: parent
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "ios-home"
                        color: "#00391C"
                        width: Theme.dp(18)
                        height: width
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: homeButton.accessibleName
                        role: "labelMedium"
                        color: "#00391C"
                        maximumLineCount: 1
                    }
                }
            }
            TileCard {
                id: workButton
                objectName: "mapsWork"
                width: parent.buttonWidth
                height: homeButton.height
                containerColor: TC.GREEN
                contentColor: "#00391C"
                preview: tile.preview
                //% "Work"
                accessibleName: qsTrId("id-tile-work")
                onClicked: tile.go(tile.work, workButton)
                Column {
                    anchors.centerIn: parent
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "ios-briefcase"
                        color: "#00391C"
                        width: Theme.dp(18)
                        height: width
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: workButton.accessibleName
                        role: "labelMedium"
                        color: "#00391C"
                        maximumLineCount: 1
                    }
                }
            }
        }
    }
}
