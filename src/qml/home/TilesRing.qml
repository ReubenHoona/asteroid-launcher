/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *               2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import "../tiles"

/* The tiles of the carousel, a ring with the watch face (split out of
 * MainScreen.qml): which tiles (dconf), their panels in the grid (1..n, 0),
 * the editor's entry and the app icon at the top (TilesIndicator).
 * Instantiated once in MainScreen as `tilesRing`; MainScreen forwards
 * tileRegistry, builtTiles, tileCount, buildTiles() and openTilesEditor().
 * Reads MainScreen's shared ids (desktop, grid, tilesEditor, launcherModel)
 * through the context. With no tile the carousel has one page, the empty
 * tile (stock nax.java:117-127). Owned by the tiles packages
 * (W2-launcher-tiles-carousel). */
Item {
    id: tilesRing
    anchors.fill: parent
    z: 2

    // the tiles: id -> the app they belong to (its icon is the page indicator's),
    // file, name and the icon of the tiles editor's list
    readonly property var tileRegistry: ({
        //% "Heart rate"
        "heartrate": { app: "asteroid-hrm", file: "tiles/HeartRateTile.qml", name: qsTrId("id-tile-heart-rate"), icon: "ios-heart-outline" },
        //% "Steps"
        "steps": { app: "asteroid-health", file: "tiles/StepsTile.qml", name: qsTrId("id-tile-steps"), icon: "ios-walk" },
        //% "Weather"
        "weather": { app: "asteroid-weather", file: "tiles/WeatherTile.qml", name: qsTrId("id-tile-weather"), icon: "ios-partly-sunny-outline" },
        //% "Agenda"
        "agenda": { app: "asteroid-calendar", file: "tiles/AgendaTile.qml", name: qsTrId("id-tile-agenda"), icon: "ios-calendar-outline" },
        //% "Timer"
        "timer": { app: "asteroid-timer", file: "tiles/TimerTile.qml", name: qsTrId("id-tile-timer"), icon: "ios-timer-outline" },
        //% "Media"
        "media": { app: "asteroid-music", file: "tiles/MediaTile.qml", name: qsTrId("id-tile-media"), icon: "ios-musical-notes-outline" },
        //% "Assistant"
        "assistant": { app: "asteroid-assistant", file: "tiles/AssistantTile.qml", name: qsTrId("id-tile-assistant"), icon: "ios-microphone-outline" },
        //% "Alarm"
        "alarm": { app: "asteroid-alarmclock", file: "tiles/AlarmTile.qml", name: qsTrId("id-tile-alarm"), icon: "ios-alarm-outline" },
        //% "Battery"
        "battery": { app: "asteroid-settings", file: "tiles/BatteryTile.qml", name: qsTrId("id-tile-battery"), icon: "ios-battery-full" }
    })
    ConfigurationValue {
        id: tilesSetting
        key: "/org/asteroidos/ux/tiles"
        // stock's eos set and order (Main goal, Daily heart rate, Next event,
        // Google/Assistant, Forecast) with our tiles; Exercise, Sleep and Maps have none.
        // Alarm, timer, battery and media stay in the add list. A saved list wins.
        defaultValue: ["steps", "heartrate", "agenda", "assistant", "weather"]
        onValueChanged: if (desktop.wearLayout && grid.panels.size > 0) desktop.buildTiles()
    }
    property var builtTiles: []
    readonly property int tileCount: builtTiles.length
    property bool _built: false

    /* The app icon of a tile (the page indicator): the icon of its app in the
     * launcher, else the registry's. Looked up once per tile and again when
     * the launcher's list changes. */
    property var _iconCache: ({})
    Connections {
        target: launcherModel
        function onItemCountChanged() { tilesRing._iconCache = ({}) }
    }
    function appIcon(id) {
        if (_iconCache[id] !== undefined)
            return _iconCache[id]
        var entry = tileRegistry[id]
        var name = entry ? entry.icon : "ios-help"
        if (entry && entry.app && typeof launcherModel !== "undefined") {
            for (var i = 0; i < launcherModel.itemCount; i++) {
                var it = launcherModel.get(i)
                if (it && it.object)
                    it = it.object
                if (it && it.filePath && it.iconId && it.filePath.split("/").pop() === entry.app + ".desktop") {
                    name = it.iconId
                    break
                }
            }
        }
        _iconCache[id] = name
        return name
    }
    // the icon of the page (1..n; the empty page has the plus)
    function pageIcon(page) {
        return builtTiles.length === 0 ? "ios-add-circle-outline" : appIcon(builtTiles[page - 1])
    }

    // the tiles from dconf, unknown ids left out, as panels (1..n, 0)
    function buildTiles() {
        var wanted = []
        var list = tilesSetting.value || []
        for (var i = 0; i < list.length; i++)
            if (tileRegistry[list[i]] && wanted.indexOf(list[i]) < 0)
                wanted.push(list[i])
        if (_built && JSON.stringify(wanted) === JSON.stringify(builtTiles))
            return
        var onTiles = grid.currentHorizontalPos > 0
        for (var r = 1; r <= grid.tilePages; r++)
            grid.removePanel(r, 0)
        for (var t = 0; t < wanted.length; t++) {
            var panel = grid.addPanel(t + 1, 0, tilePanel)
            panel.tileFile = tileRegistry[wanted[t]].file
            panel.z = 2          // over the face and its black layer
        }
        // no tile: the carousel is one page, 'Add a widget' (nax.java:117-127)
        if (wanted.length === 0)
            grid.addPanel(1, 0, emptyPanel).z = 2
        grid.tilePages = Math.max(1, wanted.length)
        _built = true
        // drawn once offscreen (first textures, text, shapes made now, not
        // in the first frames of a swipe), then hidden
        grid.hideSoon()
        builtTiles = wanted
        if (onTiles)
            grid.moveTo(Math.min(grid.currentHorizontalPos, grid.tilePages), 0)
        else
            grid.ringPlace()
        grid.changeAllowedDirections()
    }

    // the tiles editor's new list
    function saveTiles(tiles) {
        tilesSetting.value = tiles
    }

    // the tile on screen (a long press on it) in the middle of the editor
    function openTilesEditor() {
        tilesEditor.registry = tileRegistry
        tilesEditor.open(builtTiles, Math.max(0, grid.currentHorizontalPos - 1))
    }

    Component {
        id: tilePanel
        Loader {
            property string tileFile
            property bool forbidTop: true
            property bool forbidBottom: true
            source: tileFile !== "" ? Qt.resolvedUrl("../" + tileFile) : ""
        }
    }
    Component {
        id: emptyPanel
        EmptyTile {
            property bool forbidTop: true
            property bool forbidBottom: true
        }
    }

    // the app icon of the page at the top, in place of page dots (stock TilesIndicator)
    TilesIndicator {
        id: tileIndicator
        z: 2
        count: desktop.wearLayout ? grid.tilePages : 0
        position: grid.ringPosition
        iconFor: tilesRing.pageIcon
        emptyPage: tilesRing.builtTiles.length === 0
        visible: grid.ringActive && grid.currentVerticalPos === 0 && !displayAmbient
    }
}
