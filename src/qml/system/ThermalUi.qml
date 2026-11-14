/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import Nemo.DBus
import org.asteroid.controls
import "thermal.js" as Thermal

/* The thermal screens (power-boot-warnings-12), as stock's ThermalUiImpl, driven by the dconf key
 * /org/asteroidos/thermal/state that a thermal monitor writes (none / warning / cooldown; event driven,
 * the launcher polls nothing and runs no timer while it is "none"):
 *   warning   a black dialog: the thermostat icon, "Watch is getting warm", "Watch will enter cooldown mode
 *             in 15 seconds" and a round OK button (the monitor moves on by itself)
 *   cooldown  "Cooling down..." for 3000 ms (icon 48 dp, its top at 32 % of the height), then an overlay that
 *             takes every touch and hides nothing; a tap on it shows "Your watch has overheated" with
 *             "Move your watch to a cooler place" (icon at 12 %) for 3 s. Theater mode is on for the
 *             cooldown (turned on here, turned off at its end only if it was this that turned it on);
 *             airplane mode and Bluetooth / Wi-Fi are the monitor's. The crown does nothing (keymap).
 *   end       the notice "Watch was too warm" / "It is now running normally"
 *   shutdown  the first boot after a thermal shutdown (the monitor writes
 *             /org/asteroidos/thermal/shutdown-notice): "Watch was too warm" / "It turned off to cool down
 *             and is now running normally"
 * The display is turned on for the warning and the cooldown. The icon is ios-thermometer until the
 * stock thermostat glyph is in the icon set. */
Item {
    id: thermal
    objectName: "thermalUi"
    anchors.fill: parent

    // the screen the state shows: none, warning, warningDismissed, cooling, blocked, overheated
    property string phase: "none"
    readonly property bool shown: Thermal.shows(phase)
    readonly property bool blocking: Thermal.blocks(phase)
    // the crown may close only the warning
    readonly property bool closableByCrown: phase === "warning"
    readonly property string thermalState: stateValue.value === undefined ? "none" : String(stateValue.value)
    // Theater mode was turned on by the cooldown
    property bool theaterByUs: false
    property int notices: 0
    property string lastNotice: ""
    readonly property alias coolingTimer: coolingTimer
    readonly property alias cardTimer: cardTimer
    readonly property alias okButton: ok
    readonly property string icon: "ios-thermometer"

    ConfigurationValue { id: stateValue; key: Thermal.STATE_KEY; defaultValue: "none" }
    ConfigurationValue { id: shutdownNotice; key: Thermal.SHUTDOWN_KEY; defaultValue: false }

    onThermalStateChanged: follow()
    Component.onCompleted: {
        follow()
        bootNotice()
    }

    function follow() {
        var next = Thermal.phaseFor(thermalState, phase)
        if (next === phase)
            return
        var was = phase
        phase = next
        if (phase === "warning") {
            displayOn()
        } else if (phase === "cooling") {
            displayOn()
            coolingTimer.restart()
            if (typeof modes !== "undefined" && modes !== null && modes.theater !== true) {
                modes.theater = true
                theaterByUs = true
            }
        } else if (phase === "none") {
            coolingTimer.stop()
            cardTimer.stop()
            if (Thermal.blocks(was))
                endCooldown()
        }
    }

    function endCooldown() {
        if (theaterByUs && typeof modes !== "undefined" && modes !== null)
            modes.theater = false
        theaterByUs = false
        //% "Watch was too warm"
        notice(qsTrId("id-thermal-end-title"),
               //% "It is now running normally"
               qsTrId("id-thermal-end-text"))
    }

    // the first boot after a thermal shutdown
    function bootNotice() {
        if (shutdownNotice.value !== true && shutdownNotice.value !== "true")
            return
        shutdownNotice.value = false
        //% "Watch was too warm"
        notice(qsTrId("id-thermal-end-title"),
               //% "It turned off to cool down and is now running normally"
               qsTrId("id-thermal-boot-text"))
    }

    function dismissWarning() { phase = "warningDismissed" }
    // a tap on the blocked screen: the overheated card for a while
    function tapBlocked() {
        if (phase !== "blocked")
            return
        phase = "overheated"
        cardTimer.restart()
    }

    function notice(summary, body) {
        notices++
        lastNotice = body
        notifier.typedCall("Notify",
                           [{ "type": "s", "value": "Settings" }, { "type": "u", "value": 0 },
                            { "type": "s", "value": "ios-thermometer" }, { "type": "s", "value": summary },
                            { "type": "s", "value": body }, { "type": "as", "value": [] },
                            { "type": "a{sv}", "value": {} }, { "type": "i", "value": -1 }])
    }

    function displayOn() {
        mce.typedCall("req_display_state_on", [])
    }

    DBusInterface {
        id: notifier
        bus: DBus.SessionBus
        service: "org.freedesktop.Notifications"
        path: "/org/freedesktop/Notifications"
        iface: "org.freedesktop.Notifications"
    }
    DBusInterface {
        id: mce
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
    }

    // "Cooling down..." shows for 3000 ms, then the overlay takes the touches
    Timer {
        id: coolingTimer
        interval: Thermal.COOLING_SCREEN_MS
        onTriggered: if (thermal.phase === "cooling") thermal.phase = "blocked"
    }
    Timer {
        id: cardTimer
        interval: Thermal.OVERHEATED_CARD_MS
        onTriggered: if (thermal.phase === "overheated") thermal.phase = "blocked"
    }

    // ---- the touch-blocking overlay: nothing under it reacts, it draws nothing while blocked
    MouseArea {
        id: blocker
        objectName: "thermalBlocker"
        anchors.fill: parent
        enabled: thermal.blocking
        visible: thermal.blocking
        onClicked: thermal.tapBlocked()
    }

    // ---- the warning dialog
    Rectangle {
        id: warning
        objectName: "thermalWarning"
        anchors.fill: parent
        visible: thermal.phase === "warning"
        color: "#000000"
        MouseArea { anchors.fill: parent }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.07)
            width: parent.width * 0.88
            spacing: Theme.dp(2)

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.dp(24)
                height: width
                name: thermal.icon
                color: Theme.color.error
            }
            Label {
                objectName: "thermalWarningTitle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                role: "titleMedium"
                color: "#ffffff"
                //% "Watch is getting warm"
                text: qsTrId("id-thermal-warm-title") + localeManager.changesObserver
            }
            Label {
                objectName: "thermalWarningText"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                role: "bodySmall"
                color: Theme.color.onSurfaceVariant
                //% "Watch will enter cooldown mode in %1 seconds"
                text: qsTrId("id-thermal-warm-text").arg(Thermal.WARNING_SECONDS) + localeManager.changesObserver
            }
        }
        // the round OK button
        Rectangle {
            id: ok
            objectName: "thermalOk"
            width: Theme.dp(44)
            height: width
            radius: width / 2
            color: Theme.color.primary
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(parent.height * 0.04)
            DialogGlyph {
                anchors.centerIn: parent
                width: Theme.dp(24)
                height: width
                glyph: "check"
                color: Theme.color.onPrimary
            }
            MouseArea {
                anchors.fill: parent
                onClicked: thermal.dismissWarning()
                Accessible.role: Accessible.Button
                //% "OK"
                Accessible.name: qsTrId("id-thermal-ok")
            }
        }
    }

    // ---- "Cooling down..."
    Rectangle {
        id: cooling
        objectName: "thermalCooling"
        anchors.fill: parent
        visible: thermal.phase === "cooling"
        color: "#000000"
        Icon {
            id: coolingIcon
            objectName: "thermalCoolingIcon"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * Thermal.COOLING_ICON_TOP)
            width: Theme.dp(Thermal.COOLING_ICON_DP)
            height: width
            name: thermal.icon
            color: Theme.color.error
        }
        Label {
            objectName: "thermalCoolingTitle"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: coolingIcon.bottom
            anchors.topMargin: Theme.dp(8)
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            role: "titleMedium"
            color: "#ffffff"
            //% "Cooling down…"
            text: qsTrId("id-thermal-cooling") + localeManager.changesObserver
        }
    }

    // ---- "Your watch has overheated"
    Rectangle {
        id: overheated
        objectName: "thermalOverheated"
        anchors.fill: parent
        visible: thermal.phase === "overheated"
        color: "#000000"
        Icon {
            id: overheatedIcon
            objectName: "thermalOverheatedIcon"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * Thermal.OVERHEATED_ICON_TOP)
            width: Theme.dp(32)
            height: width
            name: thermal.icon
            color: Theme.color.error
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: overheatedIcon.bottom
            anchors.topMargin: Theme.dp(8)
            width: parent.width * 0.8
            spacing: Theme.dp(4)
            Label {
                objectName: "thermalOverheatedTitle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                role: "titleMedium"
                color: "#ffffff"
                //% "Your watch has overheated"
                text: qsTrId("id-thermal-hot-title") + localeManager.changesObserver
            }
            Label {
                objectName: "thermalOverheatedText"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                role: "bodySmall"
                color: Theme.color.onSurfaceVariant
                //% "Move your watch to a cooler place"
                text: qsTrId("id-thermal-hot-text") + localeManager.changesObserver
            }
        }
    }
}
