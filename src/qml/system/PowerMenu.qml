/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import org.asteroid.controls
import "system.js" as Sys

/* The power menu (power-boot-warnings-01): the crown held 3000 ms (mce's
 * long_press_delay, power_button_trigger "asteroid-crown-long"; from the
 * always-on screen too) opens it while the button is still down, with the
 * long-press thud. Stock WearGlobalActionsProvider: rows Power off, Restart
 * and Touch lock, as tonal pills (52 dp, 26 dp corners, surfaceContainer
 * container, primary icon, onSurface label: the shared Button's tonal
 * variant has exactly these numbers) in a scaling list, 5.2 % at the sides,
 * 21.8 % above and below, 2 dp above and below each row, no curved time.
 * Power off and Restart run at once, no second question. The menu closes on
 * the crown (close-system-dialogs), a swipe back and the display going off
 * (OverlayArbiter). No emergency rows: they have nothing to open here
 * (DECISIONS Q32).
 *
 * Instantiated by OverlayArbiter at z `arbiter.layers.powerMenu`. */
Item {
    id: menu
    objectName: "powerMenu"
    anchors.fill: parent

    /* open: the menu is up */
    property bool open: false
    readonly property bool shown: open
    /* the touch lock exists: its row shows */
    property bool touchLockAvailable: false
    readonly property var rows: Sys.powerMenuRows(touchLockAvailable)
    readonly property var metrics: Sys.powerMenuMetrics(width, height)
    readonly property alias list: list

    // the row of touch lock was chosen (the menu has closed)
    signal touchLockRequested()

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    function show() {
        if (open)
            return
        open = true
        // the first row at the top padding (positionViewAtBeginning ignores it)
        list.contentY = list.originY - list.topMargin
        // LONG_PRESS_POWER_BUTTON: a thud as the menu opens
        Haptics.longPress()
    }
    function close() { open = false }

    // the label of a row (stock android global_action_power_off, _restart, and the
    // sysui global_action_touch_lock)
    function labelOf(id) {
        if (id === "powerOff")
            //% "Power off"
            return qsTrId("id-power-off") + localeManager.changesObserver
        if (id === "restart")
            //% "Restart"
            return qsTrId("id-restart") + localeManager.changesObserver
        //% "Touch lock"
        return qsTrId("id-qs-touch-lock") + localeManager.changesObserver
    }

    // A row was pressed. Power off and Restart go to logind at once; the
    // menu closes so that the shutdown screen (under it) shows.
    function activate(id) {
        switch (id) {
        case "powerOff":
            login1.call("PowerOff", [false])
            break
        case "restart":
            login1.call("SetRebootParameter", [""])
            login1.call("Reboot", [false])
            break
        case "touchLock":
            touchLockRequested()
            break
        default:
            return
        }
        close()
    }

    DBusInterface {
        id: login1
        bus: DBus.SystemBus
        service: "org.freedesktop.login1"
        path: "/org/freedesktop/login1"
        iface: "org.freedesktop.login1.Manager"
    }

    // black behind the rows, and every touch stays on the menu
    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    BackSwipeArea {
        id: swipe
        anchors.fill: parent
        onFinished: {
            var go = committed
            reset()
            if (go)
                menu.close()
        }

        Item {
            width: parent.width
            height: parent.height
            x: swipe.value

            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }

            ScalingList {
                id: list
                objectName: "powerList"
                anchors.fill: parent
                sideMargin: menu.metrics.sideMargin
                topMargin: menu.metrics.verticalMargin
                bottomMargin: menu.metrics.verticalMargin
                spacing: menu.metrics.rowGap
                model: menu.rows
                itemDelegate: Button {
                    property var modelData
                    objectName: "powerRow_" + (modelData ? modelData.id : "")
                    variant: "tonal"
                    text: modelData ? menu.labelOf(modelData.id) : ""
                    iconName: modelData ? modelData.icon : ""
                    iconSize: Theme.dp(24)
                    onClicked: menu.activate(modelData.id)
                }
            }
        }
    }
}
