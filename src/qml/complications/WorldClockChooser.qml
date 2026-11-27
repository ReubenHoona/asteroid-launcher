/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import "faceeditor.js" as FE

/*
 * The World clock's zone chooser (A-13), as stock's WorldClockProviderConfigActivity
 * (ACTION_CHOOSE_TIMEZONE): a list of the regions, then the zones of the region tapped
 * ("City (CODE)", sorted by their offset now and then by name); a zone is the source
 * "worldclock:<id>". Back from the zones goes to the regions, back from the regions
 * closes it. Two lists of the face editor's kind (EditorParamList).
 *
 * The face editor opens it as the World clock's second page (its pick is the editor's
 * choice). A tap on a World clock slot of the face opens it for that slot (stock: the
 * complication's own tap, no world clock app here): openFor(current, faceName, slotId)
 * then stores the pick in the face's complications itself.
 *
 * sources: the ComplicationSources (its zones, names, the config key of a face).
 */
Item {
    id: chooser

    property var sources: null
    // where a pick is stored by the chooser itself (a tap on the face), else only `picked`
    property string faceName: ""
    property string slotId: ""
    readonly property bool shown: regionList.shown || zoneList.shown
    readonly property Item regionSheet: regionList
    readonly property Item zoneSheet: zoneList
    // what the crown turns: the open list
    readonly property Item rotaryTarget: zoneList.shown ? zoneList.list : (regionList.shown ? regionList.list : null)

    // a zone was picked: the full source ("worldclock:<id>")
    signal picked(string source)
    // back out of the regions (nothing picked)
    signal closed()
    signal poked()

    anchors.fill: parent

    // stock's region names (region_name_*), by the keys of WorldZones.regions()
    function regionNames() {
        return {
            //% "Africa"
            africa: qsTrId("id-comp-region-africa"),
            //% "Asia"
            asia: qsTrId("id-comp-region-asia"),
            //% "Atlantic"
            atlantic: qsTrId("id-comp-region-atlantic"),
            //% "Australia"
            australia: qsTrId("id-comp-region-australia"),
            //% "Europe"
            europe: qsTrId("id-comp-region-europe"),
            //% "Indian Ocean"
            indian: qsTrId("id-comp-region-indian"),
            //% "North America"
            northamerica: qsTrId("id-comp-region-north-america"),
            //% "Pacific"
            pacific: qsTrId("id-comp-region-pacific"),
            //% "South America"
            southamerica: qsTrId("id-comp-region-south-america"),
            //% "Universal"
            universal: qsTrId("id-comp-region-universal")
        }
    }

    // current: the slot's source param (a zone id, an old offset, or ""); the regions list opens on its region
    function openFor(current, face, slot) {
        faceName = face !== undefined ? String(face) : ""
        slotId = slot !== undefined ? String(slot) : ""
        var z = sources ? sources.zones : null
        var rows = FE.regionRows(z ? z.regions() : [], regionNames())
        var mine = z && current ? z.regionOfZone(String(current)) : ""
        var at = 0
        for (var i = 0; i < rows.length; i++)
            if (FE.regionOfRow(rows[i].value) === mine)
                at = i
        zoneList.closeNow()
        regionList.title = sources ? sources.name("worldclock") : ""
        regionList.model = rows
        regionList.open(at)
        currentZone = current !== undefined ? String(current) : ""
    }
    property string currentZone: ""
    function openRegion(key) {
        var z = sources ? sources.zones : null
        var rows = FE.zoneRows(z ? z.zones(key, sources.now.getTime()) : [])
        zoneList.title = regionNames()[key] || key
        zoneList.model = rows
        zoneList.open(Math.max(0, FE.rowIndex(rows, "worldclock:" + currentZone)))
    }
    function choose(source) {
        if (faceName !== "" && slotId !== "" && sources)
            config.value = sources.withSource(config.value, slotId, source)
        closeNow()
        picked(source)
    }
    function closeNow() {
        zoneList.closeNow()
        regionList.closeNow()
    }
    // a swipe right, or the editor's back
    function back() {
        if (zoneList.shown) {
            zoneList.back()
            return true
        }
        if (regionList.shown) {
            regionList.back()
            return true
        }
        return false
    }

    ConfigurationValue {
        id: config
        key: chooser.faceName !== "" && chooser.sources ? chooser.sources.configKey(chooser.faceName) : ""
        defaultValue: []
    }

    EditorParamList {
        id: regionList
        objectName: "eosWorldRegions"
        onPicked: (value) => { if (FE.isRegionRow(value)) chooser.openRegion(FE.regionOfRow(value)) }
        onBackRequested: chooser.closed()
        onPoked: chooser.poked()
    }
    // over the regions: back shows them again
    EditorParamList {
        id: zoneList
        objectName: "eosWorldZones"
        onPicked: (value) => chooser.choose(value)
        onPoked: chooser.poked()
    }
}
