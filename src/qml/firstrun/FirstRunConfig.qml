/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *               2017 Florent Revest <revestflo@gmail.com>
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
import org.asteroid.controls
import org.asteroid.utils
import org.asteroid.settings
import Nemo.Configuration
import "desktop.js" as Desktop
import Nemo.DBus

FlatMesh {
    id: config
    anchors.fill: parent
    centerColor: "#222222"
    outerColor: "#000000"

    Component.onCompleted: firstRun.startFirstRun()
    Component.onDestruction: config.stopGps()

    ConfigurationValue {
        id: use12H
        key: "/org/asteroidos/settings/use-12h-format"
        defaultValue: false
    }

    state: "LANGUAGE"

    states: [
        State { name: "LANGUAGE" },
        State { name: "LOCATION_SOURCE" },
        State { name: "TIMEZONE_REGION" },
        State { name: "TIMEZONE_CITY" },
        State { name: "TIME" },
        State { name: "DATE" }
    ]

    LanguageModel { id: langSettings }
    Spinner {
        id: langLV
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        height: Dims.h(60)
        model: langSettings
        visible: config.state == "LANGUAGE"
        enabled: visible

        delegate: SpinnerDelegate { text: langSettings.languageName(index) }

        property bool _positioned: false
        onContentHeightChanged: {
            if (!_positioned && contentHeight > 0) {
                _positioned = true;
                var i = langSettings.currentIndex;
                if (i !== -1) {
                    positionViewAtIndex(i, ListView.SnapPosition);
                    currentIndex = i;
                }
            }
        }
    }

    DateTimeSettings { id: dtSettings }
    WallClock { id: wallClock}
    Row {
        id: timeSelector
        anchors.top: title.bottom
        height: Dims.h(60)
        width: parent.width
        visible: config.state == "TIME"
        enabled: visible

        property int spinnerWidth: use12H.value ? width/3 : width/2

        CircularSpinner {
            id: hourLV
            height: parent.height
            width: parent.spinnerWidth
            model: use12H.value ? 12 : 24
            showSeparator: true
        }

        CircularSpinner {
            id: minuteLV
            height: parent.height
            width: parent.spinnerWidth
            model: 60
            showSeparator: use12H.value
        }

        Spinner {
            id: amPmLV
            height: parent.height
            width: parent.spinnerWidth
            model: 2
            delegate: SpinnerDelegate { text: index == 0 ? "AM" : "PM" }
        }

        Component.onCompleted: {
            var hour = wallClock.time.getHours();
            if(use12H.value) {
                amPmLV.currentIndex = hour / 12;
                hour = hour % 12;
            }
            hourLV.currentIndex = hour;
            minuteLV.currentIndex = wallClock.time.getMinutes();
        }
    }

    Row {
        id: dateSelector
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        height: Dims.h(60)
        visible: config.state == "DATE"
        enabled: visible

        CircularSpinner {
            id: dayLV
            height: parent.height
            width: parent.width/3
            model: 31
            showSeparator: true
            delegate: SpinnerDelegate { text: index+1 }
        }

        CircularSpinner {
            id: monthLV
            height: parent.height
            width: parent.width/3
            model: 12
            showSeparator: true
            delegate: SpinnerDelegate { text: Qt.locale().monthName(index, Locale.ShortFormat) + localeManager.changesObserver }
        }

        CircularSpinner {
            id: yearLV
            height: parent.height
            width: parent.width/3
            model: 100
            delegate: SpinnerDelegate { text: index+2000 }
        }

        Component.onCompleted: {
            var d = new Date();
            dayLV.currentIndex = d.getDate()-1;
            monthLV.currentIndex = d.getMonth();
            yearLV.currentIndex = d.getFullYear()-2000;
        }
    }

    property var timezoneList: []
    property string pendingRegion: ""
    property string currentTz: ""

    onTimezoneListChanged: buildRegionModel()

    function buildRegionModel() {
        var allowlist = ["Africa", "America", "Antarctica", "Arctic", "Asia", "Atlantic", "Australia", "Europe", "Indian", "Pacific"]
        regionModel.clear()
        for (var i = 0; i < allowlist.length; i++) {
            regionModel.append({ "name": allowlist[i], "visualName": allowlist[i], "isLeaf": false, "fullPath": "" })
        }
        regionModel.append({ "name": "Zulu", "visualName": "Zulu", "isLeaf": true, "fullPath": "Zulu" })
        selectCurrentRegion()
    }

    // Point the region spinner at the current time zone's region (e.g. after
    // the GPS picked it), else at the default entry.
    function selectCurrentRegion() {
        var index = 5
        var region = config.currentTz.split("/")[0]
        for (var i = 0; i < regionModel.count; i++) {
            if (regionModel.get(i).name === region) {
                index = i
                break
            }
        }
        regionLV.forceLayout()
        regionLV.positionViewAtIndex(index, ListView.SnapPosition)
        regionLV.currentIndex = index
    }

    function buildCityModel(region) {
        cityModel.clear()
        var prefix = region + "/"
        var selectIdx = 0
        var count = 0
        for (var i = 0; i < timezoneList.length; i++) {
            var tz = timezoneList[i]
            if (tz.indexOf(prefix) === 0) {
                var sub = tz.substring(prefix.length).replace(/_/g, " ")
                cityModel.append({ "fullPath": tz, "visualName": sub })
                if (tz === config.currentTz)
                    selectIdx = count
                count++
            }
        }
        cityLV.forceLayout()
        cityLV.positionViewAtIndex(selectIdx, ListView.SnapPosition)
        cityLV.currentIndex = selectIdx
    }

    DBusInterface {
        id: timedateDbus
        bus: DBus.SystemBus
        service: "org.freedesktop.timedate1"
        path: "/org/freedesktop/timedate1"
        iface: "org.freedesktop.timedate1"
    }

    // GPS through the GeoClue hybris provider (session bus). Positioning runs
    // only while the location page holds a reference on the provider.
    readonly property string gpsService: "org.freedesktop.Geoclue.Providers.Hybris"
    readonly property string gpsPath: "/org/freedesktop/Geoclue/Providers/Hybris"
    property bool gpsReferenced: false
    property bool gpsAvailable: true      // false once the provider failed to answer
    property int gpsStatus: 1             // GeoClue: 0 error, 1 unavailable, 2 acquiring, 3 available
    property int gpsSatellitesUsed: 0
    property int gpsSatellitesVisible: 0
    property bool gpsFix: false
    property real gpsLatitude: 0
    property real gpsLongitude: 0
    property bool gpsWaitingForFix: false // the GPS option was picked before a fix
    property bool gpsApplied: false
    property real gpsClockOffset: 0       // GPS UTC time minus the system clock, in seconds

    DBusInterface {
        id: gpsProvider
        service: config.gpsService
        path: config.gpsPath
        iface: "org.freedesktop.Geoclue"
    }
    DBusInterface {
        id: gpsPositionDbus
        service: config.gpsService
        path: config.gpsPath
        iface: "org.freedesktop.Geoclue.Position"
    }
    DBusInterface {
        id: gpsSatelliteDbus
        service: config.gpsService
        path: config.gpsPath
        iface: "org.freedesktop.Geoclue.Satellite"
    }

    function startGps() {
        if (gpsReferenced)
            return
        gpsReferenced = true
        gpsProvider.call("AddReference", undefined,
                         function() { console.log("FirstRunConfig: GPS started") },
                         function(error, message) {
                             console.log("FirstRunConfig: GPS unavailable:", error, message)
                             config.gpsReferenced = false
                             config.gpsAvailable = false
                         })
    }

    function stopGps() {
        if (!gpsReferenced)
            return
        gpsReferenced = false
        gpsProvider.call("RemoveReference", undefined)
    }

    function gpsStatusText() {
        if (!gpsAvailable || gpsStatus === 0)
            //% "Not available"
            return qsTrId("id-gps-unavailable") + localeManager.changesObserver
        var satellites = gpsFix && gpsSatellitesUsed > 0 ? gpsSatellitesUsed : gpsSatellitesVisible
        if (gpsFix)
            //% "Fix · %1 satellites"
            return qsTrId("id-gps-fix").arg(satellites) + localeManager.changesObserver
        if (gpsWaitingForFix)
            //% "Searching · %1 satellites"
            return qsTrId("id-gps-waiting").arg(satellites) + localeManager.changesObserver
        //% "No fix · %1 satellites"
        return qsTrId("id-gps-no-fix").arg(satellites) + localeManager.changesObserver
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: config.state === "LOCATION_SOURCE" && config.gpsReferenced
        onTriggered: {
            gpsProvider.call("GetStatus", undefined, function(status) { config.gpsStatus = status })
            gpsSatelliteDbus.call("GetSatellite", undefined,
                                  function(timestamp, used, visible) {
                                      config.gpsSatellitesUsed = used
                                      config.gpsSatellitesVisible = visible
                                  })
            gpsPositionDbus.call("GetPosition", undefined,
                                 function(fields, timestamp, latitude, longitude) {
                                     // fields: bit 0 latitude, bit 1 longitude
                                     if ((fields & 3) !== 3 || timestamp <= 0)
                                         return
                                     config.gpsLatitude = latitude
                                     config.gpsLongitude = longitude
                                     config.gpsClockOffset = timestamp - Date.now() / 1000
                                     config.gpsFix = true
                                     if (config.gpsWaitingForFix)
                                         config.applyGpsFix()
                                 })
        }
    }

    // Time zone, time and date from the GPS fix; the remaining pages then
    // start pre-filled with them and only need confirming.
    function applyGpsFix() {
        if (gpsApplied || config.state !== "LOCATION_SOURCE")
            return
        var tz = firstRun.timezoneForPosition(gpsLatitude, gpsLongitude)
        if (tz === "") {
            chooseTimezoneManually()
            return
        }
        gpsApplied = true
        console.log("FirstRunConfig: GPS position maps to time zone", tz)
        config.currentTz = tz
        timedateDbus.typedCall("SetTimezone", [
            { "type": "s", "value": tz },
            { "type": "b", "value": false }
        ],
        function(result) { console.log("FirstRunConfig: time zone set to", tz) },
        function(error, message) { console.log("FirstRunConfig: SetTimezone failed:", error, message) })
        stopGps()
        selectCurrentRegion()
        title.text = qsTrId("id-timezone-page") + localeManager.changesObserver
        config.state = "TIMEZONE_REGION"
    }

    function chooseTimezoneManually() {
        gpsWaitingForFix = false
        stopGps()
        //% "Time Zone"
        title.text = qsTrId("id-timezone-page") + localeManager.changesObserver
        config.state = "TIMEZONE_REGION"
    }

    // Local time now, from the GPS clock, in the time zone picked so far.
    function gpsLocalNow() {
        if (!gpsApplied || config.currentTz === "")
            return null
        var local = firstRun.localDateTime(config.currentTz, Math.round(Date.now() / 1000 + gpsClockOffset))
        return local.hour === undefined ? null : local
    }

    function prefillTime() {
        var local = gpsLocalNow()
        if (!local)
            return
        var hour = local.hour
        if (use12H.value) {
            amPmLV.currentIndex = Math.floor(hour / 12)
            hour = hour % 12
        }
        hourLV.currentIndex = hour
        minuteLV.currentIndex = local.minute
    }

    function prefillDate() {
        var local = gpsLocalNow()
        if (!local)
            return
        dayLV.currentIndex = local.day - 1
        monthLV.currentIndex = local.month - 1
        yearLV.currentIndex = local.year - 2000
    }

    ListModel {
        id: regionModel
        Component.onCompleted: {
            config.currentTz = dtSettings.currentTimezone()
            timedateDbus.call("ListTimezones", undefined, function(m) {
                config.timezoneList = m
            })
        }
    }

    ListModel { id: cityModel }

    Spinner {
        id: regionLV
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        height: Dims.h(60)
        model: regionModel
        visible: config.state == "TIMEZONE_REGION"
        enabled: visible

        delegate: SpinnerDelegate { text: visualName }
    }

    Spinner {
        id: cityLV
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        height: Dims.h(60)
        model: cityModel
        visible: config.state == "TIMEZONE_CITY"
        enabled: visible

        delegate: SpinnerDelegate { text: visualName }
    }

    // A tappable row with an icon, a title and a status line underneath.
    component SetupOption: Item {
        id: option
        property alias iconName: optionIcon.name
        property alias title: optionTitle.text
        property alias subtitle: optionSubtitle.text
        signal clicked()

        width: parent ? parent.width : 0
        height: Dims.h(24)

        HighlightBar { onClicked: option.clicked() }

        Icon {
            id: optionIcon
            width: Dims.h(13)
            height: width
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                leftMargin: DeviceSpecs.hasRoundScreen ? Dims.w(16) : Dims.w(10)
            }
        }

        Column {
            anchors {
                verticalCenter: parent.verticalCenter
                left: optionIcon.right
                leftMargin: Dims.w(4)
                right: parent.right
                // the rows sit near the middle, where a round screen is widest
                rightMargin: DeviceSpecs.hasRoundScreen ? Dims.w(8) : Dims.w(6)
            }
            Label {
                id: optionTitle
                width: parent.width
                font.pixelSize: Dims.l(8)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Dims.l(6)
                elide: Text.ElideRight
            }
            Label {
                id: optionSubtitle
                width: parent.width
                font.pixelSize: Dims.l(5)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Dims.l(4)
                opacity: 0.75
                elide: Text.ElideRight
            }
        }
    }

    // Where the time zone comes from: the GPS fix, or picking a region by hand.
    Column {
        id: locationSource
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        visible: config.state === "LOCATION_SOURCE"
        enabled: visible

        SetupOption {
            iconName: config.gpsFix ? "ios-navigate" : "ios-navigate-outline"
            //% "GPS"
            title: qsTrId("id-gps") + localeManager.changesObserver
            subtitle: config.gpsStatusText()
            onClicked: {
                if (!config.gpsAvailable || config.gpsStatus === 0)
                    return
                if (config.gpsFix) {
                    config.applyGpsFix()
                } else {
                    config.gpsWaitingForFix = true
                    config.startGps()
                }
            }
        }

        SetupOption {
            iconName: "ios-globe-outline"
            //% "Country selection"
            title: qsTrId("id-country-selection") + localeManager.changesObserver
            //% "Choose your time zone"
            subtitle: qsTrId("id-country-selection-hint") + localeManager.changesObserver
            onClicked: config.chooseTimezoneManually()
        }
    }

    PageHeader {
        id: title
        //% "Language"
        text: qsTrId("id-language-page") + localeManager.changesObserver
    }

    IconButton {
        id: nextButton
        iconName: "ios-arrow-dropright"
        // the location page is answered by tapping one of its two options
        visible: config.state !== "LOCATION_SOURCE"
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: Dims.iconButtonMargin
        }
        onClicked: {
            switch(config.state) {
                case "LANGUAGE":
                    var locale = langSettings.locale(langLV.currentIndex)
                    langSettings.setSystemLocale(locale, LanguageModel.UpdateWithoutReboot)

                    //% "Location"
                    title.text = qsTrId("id-location-page") + localeManager.changesObserver

                    config.state = "LOCATION_SOURCE";
                    // start searching now, so the GPS option shows live status
                    config.startGps();
                    break;
                case "TIMEZONE_REGION":
                    var selectedEntry = regionModel.get(regionLV.currentIndex)
                    if (selectedEntry.isLeaf) {
                        timedateDbus.typedCall("SetTimezone", [
                            { "type": "s", "value": selectedEntry.fullPath },
                            { "type": "b", "value": false }
                        ],
                        function(result) { console.log("FirstRunConfig: time zone set to", selectedEntry.fullPath) },
                        function(error, message) { console.log("FirstRunConfig: SetTimezone failed:", error, message) })

                        //% "Time"
                        title.text = qsTrId("id-time-page") + localeManager.changesObserver

                        config.state = "TIME";
                        config.prefillTime();
                    } else {
                        config.pendingRegion = selectedEntry.name
                        buildCityModel(config.pendingRegion)
                        title.text = qsTrId("id-timezone-page") + localeManager.changesObserver
                        config.state = "TIMEZONE_CITY";
                    }
                    break;
                case "TIMEZONE_CITY":
                    var tzName = cityModel.get(cityLV.currentIndex).fullPath
                    timedateDbus.typedCall("SetTimezone", [
                        { "type": "s", "value": tzName },
                        { "type": "b", "value": false }
                    ],
                    function(result) { console.log("FirstRunConfig: time zone set to", tzName) },
                    function(error, message) { console.log("FirstRunConfig: SetTimezone failed:", error, message) })

                    //% "Time"
                    title.text = qsTrId("id-time-page") + localeManager.changesObserver

                    config.state = "TIME";
                    config.prefillTime();
                    break;
                case "TIME":
                    var hour = hourLV.currentIndex;
                    if(use12H.value)
                        hour += amPmLV.currentIndex*12;
                    dtSettings.setTime(hour, minuteLV.currentIndex)
                    
                    //% "Date"
                    title.text = qsTrId("id-date-page") + localeManager.changesObserver
                    
                    config.state = "DATE";
                    config.prefillDate();
                    break;
                case "DATE":
                    var date = new Date();
                    date.setDate(dayLV.currentIndex+1)
                    date.setMonth(monthLV.currentIndex)
                    date.setFullYear(yearLV.currentIndex+2000)
                    dtSettings.setDate(date)
                    
                    config.destroy()
                    break;
                default:
                    console.log("FirstRunConfig: Unhandled state detected");
            }
        }
    }
}
