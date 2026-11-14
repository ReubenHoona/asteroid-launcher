/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus

/* The GPS fix of the setup's place page (setup-wizard-04), moved out of the old first-run wizard. A fix gives
 * the time zone (and the clock) without asking. Positioning runs only while `searching` is set (the place page
 * is up, with the display on) and the provider holds one reference; the page is the only user. The provider is
 * asked once a second only in that time (it is not asked at all on the first screens any more). */
Item {
    id: gps
    objectName: "setupGps"

    // the place page is up: ask for positions
    property bool searching: false
    // the user picked GPS before a fix was there: the fix is applied when it comes
    property bool waitingForFix: false
    // a fix arrived while `waitingForFix` was set
    signal fixReady()

    // GPS through the GeoClue hybris provider (session bus)
    readonly property string gpsService: "org.freedesktop.Geoclue.Providers.Hybris"
    readonly property string gpsPath: "/org/freedesktop/Geoclue/Providers/Hybris"
    property bool referenced: false
    property bool available: true         // false once the provider failed to answer
    property int status: 1                // GeoClue: 0 error, 1 unavailable, 2 acquiring, 3 available
    property int satellitesUsed: 0
    property int satellitesVisible: 0     // satellites with a signal
    property bool fix: false
    property real latitude: 0
    property real longitude: 0
    property real clockOffset: 0          // GPS UTC time minus the system clock, in seconds

    DBusInterface {
        id: provider
        service: gps.gpsService
        path: gps.gpsPath
        iface: "org.freedesktop.Geoclue"
    }
    DBusInterface {
        id: position
        service: gps.gpsService
        path: gps.gpsPath
        iface: "org.freedesktop.Geoclue.Position"
    }

    // Satellite counts; the provider's satellite structs are read in C++
    Connections {
        target: typeof firstRun !== "undefined" ? firstRun : null
        function onGpsSatellitesChanged(used, heard) {
            gps.satellitesUsed = used
            gps.satellitesVisible = heard
        }
    }

    function start() {
        if (referenced)
            return
        referenced = true
        provider.call("AddReference", undefined, undefined,
                      function(error, message) {
                          console.log("SetupGps: GPS unavailable:", error, message)
                          gps.referenced = false
                          gps.available = false
                      })
    }

    function stop() {
        if (!referenced)
            return
        referenced = false
        provider.call("RemoveReference", undefined)
    }

    onSearchingChanged: searching ? start() : stop()
    Component.onCompleted: if (searching) start()
    Component.onDestruction: stop()

    function statusText() {
        if (!available || status === 0)
            //% "Not available"
            return qsTrId("id-gps-unavailable") + localeManager.changesObserver
        var satellites = fix && satellitesUsed > 0 ? satellitesUsed : satellitesVisible
        if (fix)
            //% "Fix · %n satellite(s)"
            return qsTrId("id-gps-fix", satellites) + localeManager.changesObserver
        if (waitingForFix)
            //% "Searching · %n satellite(s)"
            return qsTrId("id-gps-waiting", satellites) + localeManager.changesObserver
        //% "No fix · %n satellite(s)"
        return qsTrId("id-gps-no-fix", satellites) + localeManager.changesObserver
    }

    // The provider checks the GNSS HAL once, when it starts. If it was asked before the HAL was up it stays in
    // error, so let it go (it exits after 30 s without clients) and ask a fresh one.
    Timer {
        id: retry
        interval: 35000
        onTriggered: if (gps.searching) gps.start()
    }

    Timer {
        id: poll
        objectName: "setupGpsPoll"
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: gps.searching && gps.referenced
        onTriggered: {
            provider.call("GetStatus", undefined, function(s) {
                gps.status = s
                if (s === 0 && gps.referenced) {
                    gps.stop()
                    retry.restart()
                }
            })
            if (typeof firstRun !== "undefined")
                firstRun.requestGpsSatellites()
            position.call("GetPosition", undefined,
                          function(fields, timestamp, lat, lon) {
                              // fields: bit 0 latitude, bit 1 longitude
                              if ((fields & 3) !== 3 || timestamp <= 0)
                                  return
                              gps.latitude = lat
                              gps.longitude = lon
                              gps.clockOffset = timestamp - Date.now() / 1000
                              gps.fix = true
                              if (gps.waitingForFix)
                                  gps.fixReady()
                          })
        }
    }
}
